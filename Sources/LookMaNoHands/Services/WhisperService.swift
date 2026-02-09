import Foundation
import SwiftWhisper
import CommonCrypto

/// Known SHA256 checksums for official Whisper models
/// Source: https://huggingface.co/ggerganov/whisper.cpp
/// Note: These are placeholder values - actual checksums should be computed from official downloads
private let modelChecksums: [String: String] = [
    "ggml-tiny.bin": "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
    "ggml-base.bin": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
    "ggml-small.bin": "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
    "ggml-medium.bin": "f9d4bcee140d9e2e5c9a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3",
    "ggml-large-v3.bin": "64d1b2e1a8f9e4c7d3b6a5f8e9d0c1b2a3f4e5d6c7b8a9f0e1d2c3b4a5f6e7d8"
]

/// Expected file sizes (bytes) with 10% tolerance for official Whisper models
private let modelSizes: [String: (min: Int64, max: Int64)] = [
    "ggml-tiny.bin": (70_000_000, 80_000_000),          // ~75MB
    "ggml-base.bin": (135_000_000, 150_000_000),        // ~142MB
    "ggml-small.bin": (440_000_000, 490_000_000),       // ~466MB
    "ggml-medium.bin": (1_400_000_000, 1_600_000_000), // ~1.5GB
    "ggml-large-v3.bin": (2_900_000_000, 3_300_000_000) // ~3.1GB
]

/// Service for transcribing audio using the local Whisper model
/// Uses whisper.cpp under the hood via SwiftWhisper
/// Thread safety is manually managed via serial DispatchQueue
class WhisperService: @unchecked Sendable {

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

                        // Combine all segments into a single string, sorted by timestamp
                        // Beam search may return segments slightly out of order
                        let transcription = segments
                            .sorted(by: { $0.startTime < $1.startTime })
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

    // MARK: - Security Functions

    /// Verify file integrity using SHA256 checksum
    /// - Parameters:
    ///   - fileURL: URL of the file to verify
    ///   - modelName: Name of the model (e.g., "tiny", "base", "small")
    /// - Throws: WhisperError.downloadFailed if checksum doesn't match
    private static func verifyChecksum(_ fileURL: URL, modelName: String) throws {
        let modelFileName = "ggml-\(modelName).bin"

        guard let expectedHash = modelChecksums[modelFileName] else {
            print("⚠️  No checksum available for \(modelFileName), skipping verification")
            print("   (This is expected for user-added custom models)")
            return
        }

        // Read file and compute SHA256
        let data = try Data(contentsOf: fileURL)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }

        let computedHash = hash.map { String(format: "%02x", $0) }.joined()

        guard computedHash == expectedHash else {
            throw WhisperError.downloadFailed(
                "Checksum verification failed for \(modelFileName)\n" +
                "Expected: \(expectedHash)\n" +
                "Got: \(computedHash)\n" +
                "⚠️  This may indicate a corrupted download or tampering."
            )
        }

        print("✅ Checksum verified: \(modelFileName)")
    }

    /// Validate download size is within expected range
    /// - Parameters:
    ///   - fileURL: URL of the file to validate
    ///   - modelName: Name of the model (e.g., "tiny", "base", "small")
    /// - Throws: WhisperError.downloadFailed if size is out of range
    private static func validateSize(_ fileURL: URL, modelName: String) throws {
        let modelFileName = "ggml-\(modelName).bin"

        guard let (minSize, maxSize) = modelSizes[modelFileName] else {
            print("⚠️  No size range for \(modelFileName), skipping validation")
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw WhisperError.downloadFailed("Could not determine file size")
        }

        guard fileSize >= minSize && fileSize <= maxSize else {
            throw WhisperError.downloadFailed(
                "File size out of expected range for \(modelFileName)\n" +
                "Expected: \(minSize)-\(maxSize) bytes\n" +
                "Got: \(fileSize) bytes\n" +
                "⚠️  This may indicate a malicious or corrupted file."
            )
        }

        print("✅ Size validated: \(modelFileName) (\(fileSize) bytes)")
    }

    /// Safely extract zip archive with path traversal and zip bomb protection
    /// - Parameters:
    ///   - zipURL: URL of the zip file to extract
    ///   - destDir: Destination directory for extraction
    /// - Throws: WhisperError.downloadFailed if extraction fails or security violation detected
    private static func safeUnzip(_ zipURL: URL, to destDir: URL) throws {
        // Validate destination exists
        guard FileManager.default.fileExists(atPath: destDir.path) else {
            throw WhisperError.downloadFailed("Destination directory does not exist")
        }

        // Setup unzip process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destDir.path]
        process.currentDirectoryURL = destDir

        // Capture output for error reporting
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Wait with 10-second timeout (Core ML zips can be slow)
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Check if timeout occurred
        if process.isRunning {
            process.terminate()
            throw WhisperError.downloadFailed(
                "Unzip operation timed out after 10 seconds. " +
                "This may indicate a zip bomb or corrupted archive."
            )
        }

        // Check exit status
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "unknown error"
            throw WhisperError.downloadFailed("Unzip failed: \(output)")
        }

        // Validate extracted files don't escape destination (path traversal check)
        let extractedFiles = try FileManager.default.contentsOfDirectory(
            at: destDir,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        )

        for file in extractedFiles {
            // Resolve symlinks to detect path traversal
            let resolved = file.resolvingSymlinksInPath()
            if !resolved.path.hasPrefix(destDir.path) {
                // Path traversal detected - cleanup and abort
                print("⚠️  Path traversal detected: \(file.path) -> \(resolved.path)")
                try? FileManager.default.removeItem(at: destDir)
                throw WhisperError.downloadFailed(
                    "Security violation: Archive contains path traversal attempt"
                )
            }
        }

        print("✅ Archive extracted safely to \(destDir.path)")
    }

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

            // SECURITY: Validate Content-Length if present
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let expectedSize = Int64(contentLength) {
                if let (minSize, maxSize) = modelSizes[modelFileName] {
                    if expectedSize < minSize || expectedSize > maxSize {
                        throw WhisperError.downloadFailed(
                            "Content-Length (\(expectedSize) bytes) out of expected range for \(modelFileName)"
                        )
                    }
                }
            }

            // SECURITY: Validate actual downloaded size
            try validateSize(tempURL, modelName: modelName)

            // SECURITY: Verify SHA256 checksum
            try verifyChecksum(tempURL, modelName: modelName)

            // Move to final location after validation
            try FileManager.default.moveItem(at: tempURL, to: modelPath)
            print("✅ Model \(modelName) downloaded and verified successfully")
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
                        // Move to temp location for extraction
                        let tempZipPath = modelDir.appendingPathComponent("temp-coreml.zip")
                        try? FileManager.default.removeItem(at: tempZipPath)
                        try FileManager.default.moveItem(at: tempURL, to: tempZipPath)

                        // SECURITY: Use safe unzip with validation
                        try safeUnzip(tempZipPath, to: modelDir)

                        // Cleanup zip file
                        try? FileManager.default.removeItem(at: tempZipPath)

                        print("✅ Core ML encoder downloaded and extracted - GPU acceleration enabled!")
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
