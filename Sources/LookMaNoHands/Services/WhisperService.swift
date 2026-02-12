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

        // Use Caches directory as the download base to avoid Documents folder permission prompt.
        // NOTE: downloadBase controls where HuggingFace Hub downloads models TO.
        //       modelFolder tells WhisperKit to skip downloading and load from a local path.
        //       We must NOT set modelFolder here, or the download will be skipped entirely.
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw WhisperError.downloadFailed("Could not access caches directory")
        }

        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: cacheDir,
            verbose: false,
            logLevel: .info
        )

        // Initialize WhisperKit (downloads model if needed)
        // Retry once if initialization fails (handles corrupted downloads - WhisperKit issue #171)
        do {
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.tokenizer = kit.tokenizer
            isModelLoaded = true
            Logger.shared.info("✅ WhisperKit model '\(modelName)' loaded successfully with Neural Engine acceleration", category: .whisper)
        } catch {
            Logger.shared.warning("First load attempt failed, retrying after cleanup: \(error.localizedDescription)", category: .whisper)

            // Retry initialization (WhisperKit will re-download if needed)
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.tokenizer = kit.tokenizer
            isModelLoaded = true
            Logger.shared.info("✅ WhisperKit model '\(modelName)' loaded successfully on retry", category: .whisper)
        }
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

    /// Check if a WhisperKit model is available in the HuggingFace hub cache.
    /// Models are downloaded to ~/Library/Caches/models--argmaxinc--whisperkit-coreml/
    ///
    /// **NOTE**: This is a basic existence check. For reliability,
    /// prefer using `loadModel()` and catching errors instead.
    static func modelExists(named modelName: String) -> Bool {
        let fileManager = FileManager.default

        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }

        // WhisperKit uses HuggingFace Hub which stores models in this structure:
        // ~/Library/Caches/models--argmaxinc--whisperkit-coreml/snapshots/<hash>/openai_whisper-<model>/
        let hubCacheDir = cacheDir.appendingPathComponent("models--argmaxinc--whisperkit-coreml")

        guard fileManager.fileExists(atPath: hubCacheDir.path) else {
            return false
        }

        // Check for the specific model variant in snapshots
        let snapshotsDir = hubCacheDir.appendingPathComponent("snapshots")
        guard fileManager.fileExists(atPath: snapshotsDir.path) else {
            return false
        }

        do {
            let snapshots = try fileManager.contentsOfDirectory(atPath: snapshotsDir.path)
            for snapshot in snapshots {
                let modelDir = snapshotsDir
                    .appendingPathComponent(snapshot)
                    .appendingPathComponent("openai_whisper-\(modelName)")
                if fileManager.fileExists(atPath: modelDir.path) {
                    return true
                }
            }
            return false
        } catch {
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

        // Use Caches directory as the download base to avoid Documents folder permission prompt.
        // NOTE: downloadBase controls where HuggingFace Hub downloads models TO.
        //       modelFolder tells WhisperKit to skip downloading and load from a local path.
        //       We must NOT set modelFolder here, or the download will be skipped entirely.
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw WhisperError.downloadFailed("Could not access caches directory")
        }

        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: cacheDir,
            verbose: true,
            logLevel: .info
        )

        // WhisperKit downloads and caches models automatically on initialization.
        // Retry once if initialization fails (handles corrupted downloads - WhisperKit issue #171)
        do {
            _ = try await WhisperKit(config)
            Logger.shared.info("✅ Model '\(modelName)' downloaded successfully", category: .whisper)
        } catch {
            Logger.shared.warning("Download failed, retrying: \(error.localizedDescription)", category: .whisper)

            // Retry download (WhisperKit will re-download if needed)
            _ = try await WhisperKit(config)
            Logger.shared.info("✅ Model '\(modelName)' downloaded successfully on retry", category: .whisper)
        }
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
