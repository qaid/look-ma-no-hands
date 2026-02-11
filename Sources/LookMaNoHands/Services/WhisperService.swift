import Foundation
import WhisperKit

/// Service for transcribing audio using the local Whisper model
/// Uses WhisperKit by Argmax with Apple Silicon optimizations
/// Thread safety is handled internally by WhisperKit
class WhisperService: @unchecked Sendable {

    // MARK: - Properties

    /// The WhisperKit instance
    private var whisperKit: WhisperKit?

    /// Tokenizer for converting prompts to token IDs
    private var tokenizer: (any WhisperTokenizer)?

    /// Whether the model is loaded and ready
    private(set) var isModelLoaded = false

    /// Whether model is currently loading
    private(set) var isModelLoading = false
    
    // MARK: - Initialization

    /// Initialize and load the Whisper model
    /// - Parameter modelName: Name of the model (e.g., "base", "small", "tiny", "large-v3-turbo")
    func loadModel(named modelName: String = "base") async throws {
        isModelLoading = true
        defer { isModelLoading = false }

        Logger.shared.info("Loading WhisperKit model '\(modelName)'...", category: .whisper)

        // Configure WhisperKit
        let config = WhisperKitConfig(
            model: modelName,
            verbose: false,
            logLevel: .info
        )

        // Initialize WhisperKit (downloads model if needed)
        let kit = try await WhisperKit(config)

        self.whisperKit = kit
        self.tokenizer = kit.tokenizer
        isModelLoaded = true

        Logger.shared.info("✅ WhisperKit model '\(modelName)' loaded successfully with Neural Engine acceleration", category: .whisper)
    }
    
    // MARK: - Transcription

    /// Tokenize a prompt string for WhisperKit's DecodingOptions.promptTokens
    /// Filters out special tokens that would confuse the decoder
    private func tokenizePrompt(_ text: String, tokenizer: any WhisperTokenizer) -> [Int] {
        let tokens = tokenizer.encode(text: text)
        return tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }

    /// Transcribe audio samples to text
    /// - Parameters:
    ///   - samples: Audio samples at 16kHz, mono, Float32
    ///   - initialPrompt: Optional context prompt to bias Whisper toward specific vocabulary/style
    /// - Returns: Transcribed text
    func transcribe(samples: [Float], initialPrompt: String? = nil) async throws -> String {
        guard let whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw WhisperError.emptyAudio
        }

        let startTime = Date()
        let audioDuration = Double(samples.count) / 16000.0
        Logger.shared.info("🎤 Starting transcription: \(samples.count) samples (\(String(format: "%.1f", audioDuration))s of audio)", category: .transcription)

        // Configure decoding options
        var options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            suppressBlank: false,
            compressionRatioThreshold: 2.4,
            noSpeechThreshold: 0.6
        )

        // Token-based prompt (converted from string)
        if let prompt = initialPrompt, let tokenizer = self.tokenizer {
            options.promptTokens = tokenizePrompt(prompt, tokenizer: tokenizer)
            Logger.shared.info("📋 Initial prompt set (\(prompt.count) chars, \(options.promptTokens?.count ?? 0) tokens): \"\(prompt.prefix(100))...\"", category: .transcription)
        }

        // Transcribe using WhisperKit
        let transcribeStart = Date()
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let transcribeElapsed = Date().timeIntervalSince(transcribeStart)

        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // Fallback: retry without prompt if we got empty output (WhisperKit #372 bug)
        if text.isEmpty, options.promptTokens != nil {
            Logger.shared.warning("Empty result with promptTokens, retrying without prompt", category: .transcription)
            var fallbackOptions = options
            fallbackOptions.promptTokens = nil
            let fallbackResults = try await whisperKit.transcribe(audioArray: samples, decodeOptions: fallbackOptions)
            let fallbackText = fallbackResults.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let totalElapsed = Date().timeIntervalSince(startTime)
            let realTimeRatio = totalElapsed / audioDuration
            Logger.shared.info("✅ Transcription complete (fallback) in \(String(format: "%.2f", totalElapsed))s (RTF: \(String(format: "%.2f", realTimeRatio))x) - \"\(fallbackText)\"", category: .transcription)

            return fallbackText
        }

        let totalElapsed = Date().timeIntervalSince(startTime)
        let realTimeRatio = totalElapsed / audioDuration
        Logger.shared.info("✅ Transcription complete in \(String(format: "%.2f", totalElapsed))s (transcribe: \(String(format: "%.2f", transcribeElapsed))s, RTF: \(String(format: "%.2f", realTimeRatio))x) - \"\(text)\"", category: .transcription)

        return text
    }
    
    // MARK: - Model Management

    /// Check if a WhisperKit model is available in the Hugging Face cache
    /// WhisperKit downloads models from Hugging Face and caches them in ~/Library/Caches/huggingface/
    static func modelExists(named modelName: String) -> Bool {
        // WhisperKit models are stored in: ~/Library/Caches/huggingface/hub/models--argmaxinc--whisperkit-coreml
        let fileManager = FileManager.default

        // Get the user's cache directory
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            Logger.shared.warning("Could not access caches directory", category: .whisper)
            return false
        }

        // WhisperKit stores models in the Hugging Face Hub cache structure
        let huggingfaceDir = cacheDir.appendingPathComponent("huggingface/hub")
        let modelsDir = huggingfaceDir.appendingPathComponent("models--argmaxinc--whisperkit-coreml")

        // Check if the huggingface models directory exists at all
        guard fileManager.fileExists(atPath: modelsDir.path) else {
            Logger.shared.info("WhisperKit cache directory does not exist: \(modelsDir.path)", category: .whisper)
            return false
        }

        // Check for snapshot directories (each model has a snapshot/commit hash subdirectory)
        let snapshotsDir = modelsDir.appendingPathComponent("snapshots")
        guard fileManager.fileExists(atPath: snapshotsDir.path) else {
            Logger.shared.info("No WhisperKit model snapshots found", category: .whisper)
            return false
        }

        // If the snapshots directory exists and has content, check for the specific model
        // Model files are typically named like: openai_whisper-{modelName}/...
        do {
            let snapshots = try fileManager.contentsOfDirectory(atPath: snapshotsDir.path)

            for snapshot in snapshots {
                let snapshotPath = snapshotsDir.appendingPathComponent(snapshot)

                // Check if this snapshot contains the model we're looking for
                // WhisperKit models are in directories like "openai_whisper-base", "openai_whisper-tiny", etc.
                let modelDirName = "openai_whisper-\(modelName)"
                let modelPath = snapshotPath.appendingPathComponent(modelDirName)

                if fileManager.fileExists(atPath: modelPath.path) {
                    Logger.shared.info("✅ Found WhisperKit model '\(modelName)' at: \(modelPath.path)", category: .whisper)
                    return true
                }
            }

            Logger.shared.info("Model '\(modelName)' not found in \(snapshots.count) snapshot(s)", category: .whisper)
            return false
        } catch {
            Logger.shared.warning("Error checking for model '\(modelName)': \(error.localizedDescription)", category: .whisper)
            return false
        }
    }

    /// Get available WhisperKit models to download
    static func getAvailableModels() -> [(name: String, size: String, description: String)] {
        return [
            ("tiny", "~80 MB", "Fastest, lowest accuracy"),
            ("base", "~150 MB", "Good balance for most uses"),
            ("small", "~500 MB", "Better accuracy"),
            ("medium", "~1.5 GB", "High accuracy"),
            ("large-v3-turbo", "~600 MB", "Best accuracy (recommended for meetings)")
        ]
    }


    /// Download a model from Hugging Face.
    ///
    /// **NETWORK ACTIVITY**: This method triggers WhisperKit to download models from
    /// `https://huggingface.co/argmaxinc/whisperkit-coreml`. It is only called when the user
    /// explicitly triggers a model download (button click in Onboarding or Settings).
    /// No automatic/background downloads ever occur.
    ///
    /// **Note**: WhisperKit does not expose incremental download progress. The UI should show
    /// an indeterminate progress indicator. This method blocks until the download completes.
    static func downloadModel(named modelName: String) async throws {
        Logger.shared.info("Downloading WhisperKit model '\(modelName)'...", category: .whisper)

        // WhisperKit downloads and caches models automatically on initialization
        let config = WhisperKitConfig(
            model: modelName,
            verbose: true,
            logLevel: .info
        )

        // This will download the model if not already cached (blocks until complete)
        _ = try await WhisperKit(config)

        Logger.shared.info("✅ Model '\(modelName)' downloaded successfully", category: .whisper)
    }
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case emptyAudio
    case transcriptionFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Whisper model '\(name)' not found. Please download the model first."
        case .modelNotLoaded:
            return "Whisper model not loaded. Call loadModel() first."
        case .emptyAudio:
            return "No audio data to transcribe."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        }
    }
}
