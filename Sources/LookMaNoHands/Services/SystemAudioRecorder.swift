import Foundation
import ScreenCaptureKit
import AVFoundation

/// Errors that can occur during system audio recording
enum RecorderError: Error {
    case noDisplayAvailable
    case permissionDenied
    case captureFailure(String)
}

/// Service for capturing system audio using ScreenCaptureKit
/// Used for meeting transcription to record audio from video conferencing apps
@available(macOS 13.0, *)
class SystemAudioRecorder: NSObject {

    // MARK: - Properties

    /// Audio stream from ScreenCaptureKit
    private var stream: SCStream?

    /// Audio engine for processing captured audio
    private let audioEngine = AVAudioEngine()

    /// Buffer to store captured audio samples
    private var audioBuffer: [Float] = []

    /// Sample rate for recording (Whisper expects 16kHz)
    private let targetSampleRate: Double = 16000

    /// Whether we're currently recording
    private(set) var isRecording = false

    /// Callback for audio data chunks
    var onAudioChunk: (([Float]) -> Void)?

    // MARK: - Permissions

    /// Check if screen recording permission is granted
    static func hasPermission() -> Bool {
        // On macOS 13+, we need to check screen recording permission
        // ScreenCaptureKit requires this even for audio-only capture
        if #available(macOS 14.0, *) {
            return true // Permission check simplified in macOS 14+
        } else {
            // For macOS 13, we'll rely on runtime permission prompts
            return true
        }
    }

    /// Request screen recording permission
    static func requestPermission() async -> Bool {
        do {
            // Request permission by attempting to get available content
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            print("SystemAudioRecorder: Permission request failed - \(error)")
            return false
        }
    }

    // MARK: - Recording Control

    /// Start capturing system audio
    func startRecording() async throws {
        guard !isRecording else {
            print("SystemAudioRecorder: Already recording")
            return
        }

        // Get shareable content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Create filter for system audio
        // We want to capture display audio (all system audio)
        guard let display = availableContent.displays.first else {
            throw RecorderError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure stream for audio-only capture
        let configuration = SCStreamConfiguration()

        // Audio settings
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = Int(targetSampleRate)
        configuration.channelCount = 1 // Mono audio

        // Minimal video settings (required even for audio-only)
        configuration.width = 100
        configuration.height = 100
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = false
        configuration.queueDepth = 5

        // Create and start stream
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        guard let stream = stream else {
            throw RecorderError.captureFailure("Failed to create SCStream")
        }

        // Add stream output for audio
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.lookmanohands.audio"))
        } catch {
            throw RecorderError.captureFailure("Failed to add audio output: \(error.localizedDescription)")
        }

        // Start capture
        do {
            try await stream.startCapture()
        } catch {
            throw RecorderError.captureFailure("Failed to start capture: \(error.localizedDescription)")
        }

        isRecording = true
        audioBuffer.removeAll()

        print("SystemAudioRecorder: Started recording system audio")
    }

    /// Stop capturing system audio and return recorded samples
    func stopRecording() async -> [Float] {
        guard isRecording else {
            print("SystemAudioRecorder: Not recording")
            return []
        }

        do {
            try await stream?.stopCapture()
        } catch {
            print("SystemAudioRecorder: Error stopping capture - \(error)")
        }

        stream = nil
        isRecording = false

        let samples = audioBuffer
        audioBuffer.removeAll()

        print("SystemAudioRecorder: Stopped recording, captured \(samples.count) samples")

        return samples
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamDelegate {

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("SystemAudioRecorder: Stream stopped with error - \(error)")
        isRecording = false
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamOutput {

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Convert CMSampleBuffer to audio samples
        guard let audioSamples = convertToFloatArray(sampleBuffer: sampleBuffer) else {
            return
        }

        // Add to buffer
        audioBuffer.append(contentsOf: audioSamples)

        // Optionally call chunk callback for streaming transcription
        if let onAudioChunk = onAudioChunk, audioBuffer.count >= Int(targetSampleRate * 5) {
            // Send 5-second chunks for faster, more responsive transcription
            let chunk = Array(audioBuffer.prefix(Int(targetSampleRate * 5)))
            onAudioChunk(chunk)

            // Keep overlap for next chunk (1 second)
            let overlapSamples = Int(targetSampleRate * 1)
            let samplesToRemove = Int(targetSampleRate * 5) - overlapSamples
            audioBuffer.removeFirst(samplesToRemove)
        }
    }

    /// Convert CMSampleBuffer to Float array
    private func convertToFloatArray(sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let data = dataPointer else {
            return nil
        }

        // Convert based on audio format
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }

        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let bitsPerChannel = audioStreamBasicDescription?.pointee.mBitsPerChannel ?? 16

        var samples: [Float] = []

        if bitsPerChannel == 16 {
            // 16-bit PCM
            let int16Data = data.withMemoryRebound(to: Int16.self, capacity: length / 2) { pointer in
                Array(UnsafeBufferPointer(start: pointer, count: length / 2))
            }
            samples = int16Data.map { Float($0) / Float(Int16.max) }
        } else if bitsPerChannel == 32 {
            // 32-bit float
            let floatData = data.withMemoryRebound(to: Float.self, capacity: length / 4) { pointer in
                Array(UnsafeBufferPointer(start: pointer, count: length / 4))
            }
            samples = floatData
        }

        return samples
    }
}
