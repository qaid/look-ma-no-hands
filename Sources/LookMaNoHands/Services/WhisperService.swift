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

        print("WhisperService: Loading model from \(modelPath)")

        // Load the model using SwiftWhisper
        let modelURL = URL(fileURLWithPath: modelPath)
        self.whisper = Whisper(fromFileURL: modelURL)

        isModelLoaded = true
        print("WhisperService: Model loaded successfully")
    }
    
    /// Transcribe audio samples to text
    /// - Parameter samples: Audio samples at 16kHz, mono, Float32
    /// - Returns: Transcribed text
    func transcribe(samples: [Float]) async throws -> String {
        guard isModelLoaded, whisper != nil else {
            throw WhisperError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw WhisperError.emptyAudio
        }

        let startTime = Date()
        print("WhisperService: Transcribing \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s of audio)...")

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
                        // Transcribe using SwiftWhisper
                        let segments = try await whisper.transcribe(audioFrames: samples)

                        // Combine all segments into a single string
                        let transcription = segments
                            .map { $0.text }
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        let elapsed = Date().timeIntervalSince(startTime)
                        print("WhisperService: Transcription complete in \(String(format: "%.2f", elapsed))s - \(transcription)")

                        continuation.resume(returning: transcription)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
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

    /// Download a model from Hugging Face (both .bin and Core ML if available)
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

        // Try to download Core ML model for acceleration (optional, may not exist for all models)
        // Core ML models are compressed as .zip on Hugging Face
        if !FileManager.default.fileExists(atPath: coreMLPath.path) {
            let coreMLZipURL = URL(string: "\(baseURL)/\(coreMLFileName).zip")!
            print("Attempting to download Core ML model from \(coreMLZipURL)")

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
                print("Core ML model download optional and failed (expected for some models): \(error.localizedDescription)")
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
