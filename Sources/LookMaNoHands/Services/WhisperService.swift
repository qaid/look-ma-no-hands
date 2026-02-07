import Foundation
import SwiftWhisper

/// Service for transcribing audio using the local Whisper model
/// Uses whisper.cpp under the hood via SwiftWhisper
class WhisperService {

    // MARK: - Properties

    /// The Whisper instance
    private var whisper: Whisper?

    /// Whether the model is loaded and ready
    private(set) var isModelLoaded = false

    /// Serial queue to ensure only one transcription happens at a time
    /// Using userInteractive for maximum priority - transcription is time-sensitive
    private let transcriptionQueue = DispatchQueue(label: "com.whisperdictation.transcription", qos: .userInteractive)

    /// Persistent C string for initial_prompt (must stay alive during transcription)
    private var initialPromptCString: UnsafeMutablePointer<CChar>?
    
    // MARK: - Initialization
    
    /// Initialize and load the Whisper model
    /// - Parameter modelName: Name of the model (e.g., "base", "small", "tiny")
    func loadModel(named modelName: String = "base") async throws {
        // Construct path to model file
        let modelFileName = "ggml-\(modelName).bin"

        // Check common locations for the model
        let possiblePaths = [
            // Bundle resources
            Bundle.main.resourcePath.map { "\($0)/whisper-model/\(modelFileName)" },
            // Application Support
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first.map { "\($0.path)/LookMaNoHands/models/\(modelFileName)" },
            // Home directory (for development)
            NSHomeDirectory() + "/.whisper/models/\(modelFileName)"
        ].compactMap { $0 }

        // Find the first existing model file
        var modelPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                modelPath = path
                break
            }
        }

        guard let modelPath = modelPath else {
            throw WhisperError.modelNotFound(modelName)
        }

        Logger.shared.info("Loading Whisper model '\(modelName)' from \(modelPath)", category: .whisper)

        // Check if Core ML model exists
        let coreMLFileName = "ggml-\(modelName)-encoder.mlmodelc"
        let coreMLPath = modelPath.replacingOccurrences(of: modelFileName, with: coreMLFileName)
        let hasCoreML = FileManager.default.fileExists(atPath: coreMLPath)

        if hasCoreML {
            Logger.shared.info("✅ Core ML model found at \(coreMLPath) - GPU acceleration will be available", category: .whisper)
        } else {
            Logger.shared.warning("⚠️ Core ML model NOT found (expected at \(coreMLPath)) - will use CPU only (slower)", category: .whisper)
        }

        // Load the model using SwiftWhisper with optimized decoding parameters
        let modelURL = URL(fileURLWithPath: modelPath)
        let params = WhisperParams(strategy: .beamSearch)

        // Beam search with 5 beams explores multiple hypotheses for better accuracy
        params.beam_search.beam_size = 5

        // Short dictation clips benefit from single-segment mode (avoids boundary artifacts)
        params.single_segment = true

        // Explicit English avoids misdetection on noisy/short audio
        params.language = .english

        // Disabling suppress_blank prevents hallucinations like "Thank you for listening"
        params.suppress_blank = false

        Logger.shared.info("Whisper params: beam_size=5, single_segment=true, language=en, suppress_blank=false", category: .whisper)

        self.whisper = Whisper(fromFileURL: modelURL, withParams: params)

        isModelLoaded = true
        Logger.shared.info("✅ Whisper model '\(modelName)' loaded successfully (Core ML: \(hasCoreML ? "YES" : "NO"))", category: .whisper)
    }
    
    /// Transcribe audio samples to text
    /// - Parameters:
    ///   - samples: Audio samples at 16kHz, mono, Float32
    ///   - initialPrompt: Optional context prompt to bias Whisper toward specific vocabulary/style
    /// - Returns: Transcribed text
    func transcribe(samples: [Float], initialPrompt: String? = nil) async throws -> String {
        guard isModelLoaded, whisper != nil else {
            throw WhisperError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw WhisperError.emptyAudio
        }

        // Set initial_prompt on the Whisper params before transcription
        if let prompt = initialPrompt, let whisper = self.whisper {
            // Free previous C string if any
            if let prev = initialPromptCString {
                free(prev)
            }
            initialPromptCString = strdup(prompt)
            whisper.params.initial_prompt = UnsafePointer(initialPromptCString)
            Logger.shared.info("📋 Initial prompt set (\(prompt.count) chars): \"\(prompt.prefix(100))...\"", category: .transcription)
        } else if let whisper = self.whisper {
            // Clear any previous prompt
            if let prev = initialPromptCString {
                free(prev)
                initialPromptCString = nil
            }
            whisper.params.initial_prompt = nil
        }

        let startTime = Date()
        let audioDuration = Double(samples.count) / 16000.0
        Logger.shared.info("🎤 Starting transcription: \(samples.count) samples (\(String(format: "%.1f", audioDuration))s of audio)", category: .transcription)

        // Use a serial queue to ensure only one transcription at a time
        // Whisper instance can't handle concurrent requests
        return try await withCheckedThrowingContinuation { continuation in
            transcriptionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: WhisperError.modelNotLoaded)
                    return
                }

                guard let whisper = self.whisper else {
                    continuation.resume(throwing: WhisperError.modelNotLoaded)
                    return
                }

                // Use Task with high priority for time-sensitive transcription
                Task(priority: .userInitiated) {
                    do {
                        let transcribeStart = Date()

                        // Transcribe using SwiftWhisper
                        let segments = try await whisper.transcribe(audioFrames: samples)

                        let transcribeElapsed = Date().timeIntervalSince(transcribeStart)

                        // Combine all segments into a single string
                        let transcription = segments
                            .map { $0.text }
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        let totalElapsed = Date().timeIntervalSince(startTime)
                        let realTimeRatio = totalElapsed / audioDuration

                        Logger.shared.info("✅ Transcription complete in \(String(format: "%.2f", totalElapsed))s (transcribe: \(String(format: "%.2f", transcribeElapsed))s, RTF: \(String(format: "%.2f", realTimeRatio))x) - \"\(transcription)\"", category: .transcription)

                        continuation.resume(returning: transcription)
                    } catch {
                        let elapsed = Date().timeIntervalSince(startTime)
                        Logger.shared.error("❌ Transcription failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)", category: .transcription)
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    deinit {
        if let ptr = initialPromptCString {
            free(ptr)
        }
    }
    
    // MARK: - Model Management

    /// Get the model directory path
    static func getModelDirectory() -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let modelDir = homeDir.appendingPathComponent(".whisper/models")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        return modelDir
    }

    /// Check if a model exists locally
    static func modelExists(named modelName: String) -> Bool {
        let modelFileName = "ggml-\(modelName).bin"
        let modelDir = getModelDirectory()
        let modelPath = modelDir.appendingPathComponent(modelFileName)

        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// Get available models to download
    static func getAvailableModels() -> [(name: String, size: String, description: String)] {
        return [
            ("tiny", "75 MB", "Fastest, lowest accuracy"),
            ("base", "142 MB", "Good balance for most uses"),
            ("small", "466 MB", "Better accuracy, slower"),
            ("medium", "1.5 GB", "High accuracy"),
            ("large-v3", "3.1 GB", "Best accuracy, slowest")
        ]
    }

    /// Models known to have Core ML encoder versions on Hugging Face.
    /// Only these models will attempt a Core ML download; others skip the network request entirely.
    private static let coreMLAvailableModels: Set<String> = ["tiny", "base", "small"]

    /// Download a model from Hugging Face (both .bin and Core ML if available).
    ///
    /// **NETWORK ACTIVITY**: This is the ONLY method in the entire app that makes outgoing
    /// internet requests. It connects to `https://huggingface.co` to download Whisper model
    /// files. It is only called when the user explicitly triggers a model download (button click
    /// in Onboarding or Settings). No automatic/background downloads ever occur.
    static func downloadModel(named modelName: String, progress: @escaping (Double) -> Void) async throws {
        let modelFileName = "ggml-\(modelName).bin"
        let coreMLFileName = "ggml-\(modelName)-encoder.mlmodelc"
        let modelDir = getModelDirectory()
        let modelPath = modelDir.appendingPathComponent(modelFileName)
        let coreMLPath = modelDir.appendingPathComponent(coreMLFileName)

        // Hugging Face URL for whisper.cpp models
        let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

        // Download main model if needed
        if !FileManager.default.fileExists(atPath: modelPath.path) {
            let downloadURL = URL(string: "\(baseURL)/\(modelFileName)")!
            print("Downloading \(modelFileName) from \(downloadURL)")

            let session = URLSession.shared
            let (tempURL, response) = try await session.download(from: downloadURL, delegate: nil)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw WhisperError.downloadFailed("Failed to download model")
            }

            try FileManager.default.moveItem(at: tempURL, to: modelPath)
            print("Model \(modelName) downloaded successfully")
            progress(0.5)
        } else {
            print("Model \(modelName) already exists")
            progress(0.5)
        }

        // Try to download Core ML model for acceleration (only for models known to have Core ML versions)
        if !FileManager.default.fileExists(atPath: coreMLPath.path) {
            if coreMLAvailableModels.contains(modelName) {
                let coreMLZipURL = URL(string: "\(baseURL)/\(coreMLFileName).zip")!
                print("Downloading Core ML model from \(coreMLZipURL)")

                do {
                    let session = URLSession.shared
                    let (tempURL, response) = try await session.download(from: coreMLZipURL, delegate: nil)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        // Unzip the Core ML model
                        let tempZipPath = modelDir.appendingPathComponent("temp-coreml.zip")
                        try FileManager.default.moveItem(at: tempURL, to: tempZipPath)

                        // Use unzip command to extract
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        process.arguments = ["-o", tempZipPath.path, "-d", modelDir.path]
                        try process.run()
                        process.waitUntilExit()

                        // Clean up zip file
                        try? FileManager.default.removeItem(at: tempZipPath)

                        print("Core ML model downloaded and extracted successfully - will enable GPU acceleration!")
                    } else {
                        print("Core ML model not available for \(modelName) - will use CPU only")
                    }
                } catch {
                    print("Core ML model download failed (optional): \(error.localizedDescription)")
                }
            } else {
                print("Core ML model not available for '\(modelName)' (only available for: \(coreMLAvailableModels.sorted().joined(separator: ", "))) - will use CPU only")
            }
        } else {
            print("Core ML model already exists")
        }

        progress(1.0)
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
