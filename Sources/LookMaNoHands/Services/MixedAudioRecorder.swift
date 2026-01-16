import Foundation
import AVFoundation
import Accelerate

/// Service that captures and mixes both system audio and microphone audio
/// Used for meeting transcription to capture both remote participants and local speaker
@available(macOS 13.0, *)
class MixedAudioRecorder {

    // MARK: - Properties

    /// System audio recorder (captures app audio/speakers)
    private let systemAudioRecorder: SystemAudioRecorder

    /// Microphone recorder
    private let microphoneRecorder: AudioRecorder

    /// Sample rate (Whisper expects 16kHz)
    private let sampleRate: Double = 16000

    /// Whether we're currently recording
    private(set) var isRecording = false

    /// Callback for mixed audio chunks (for real-time transcription)
    var onAudioChunk: (([Float]) -> Void)?

    /// Track how many mic samples we've already processed
    private var micSamplesProcessed: Int = 0

    // MARK: - Initialization

    init() {
        self.systemAudioRecorder = SystemAudioRecorder()
        self.microphoneRecorder = AudioRecorder()

        setupSystemAudioCallback()
    }

    // MARK: - Recording Control

    /// Start capturing and mixing both audio sources
    func startRecording() async throws {
        guard !isRecording else {
            print("MixedAudioRecorder: Already recording")
            return
        }

        // Reset tracking
        micSamplesProcessed = 0

        // Start both recorders
        try await systemAudioRecorder.startRecording()
        try microphoneRecorder.startRecording()

        isRecording = true

        print("MixedAudioRecorder: Started recording from both sources")
    }

    /// Stop capturing and return final mixed audio
    func stopRecording() async -> [Float] {
        guard isRecording else {
            print("MixedAudioRecorder: Not recording")
            return []
        }

        // Stop both recorders
        _ = await systemAudioRecorder.stopRecording()
        _ = microphoneRecorder.stopRecording()

        isRecording = false
        micSamplesProcessed = 0

        print("MixedAudioRecorder: Stopped recording")

        return [] // Empty because chunks were sent in real-time
    }

    // MARK: - Audio Mixing

    /// Setup callback from system audio recorder
    /// When system audio has a 30-second chunk, mix it with corresponding microphone audio
    private func setupSystemAudioCallback() {
        systemAudioRecorder.onAudioChunk = { [weak self] systemChunk in
            guard let self = self else { return }

            Task {
                // Get current full microphone buffer
                let fullMicBuffer = self.microphoneRecorder.getCurrentBuffer()

                print("MixedAudioRecorder: System chunk arrived: \(systemChunk.count) samples")
                print("MixedAudioRecorder: Microphone buffer size: \(fullMicBuffer.count) samples")
                print("MixedAudioRecorder: Mic samples already processed: \(self.micSamplesProcessed)")

                // Extract the portion of mic audio that corresponds to this system chunk
                // (from where we left off to the length of the system chunk)
                let micChunkStart = self.micSamplesProcessed
                let micChunkEnd = min(micChunkStart + systemChunk.count, fullMicBuffer.count)
                let micChunk: [Float]

                if micChunkStart < fullMicBuffer.count {
                    micChunk = Array(fullMicBuffer[micChunkStart..<micChunkEnd])
                    print("MixedAudioRecorder: Extracted mic chunk from \(micChunkStart) to \(micChunkEnd)")
                } else {
                    // If we don't have enough mic audio yet, use silence
                    micChunk = []
                    print("MixedAudioRecorder: WARNING - Not enough mic audio! Using silence.")
                }

                // Update processed count
                self.micSamplesProcessed = micChunkEnd

                // Mix the chunks
                let mixedChunk = self.mixAudio(systemSamples: systemChunk, micSamples: micChunk)

                print("MixedAudioRecorder: Mixed chunk - system: \(systemChunk.count) samples, mic: \(micChunk.count) samples → \(mixedChunk.count) mixed")

                // Send the mixed chunk to the callback
                if let onAudioChunk = self.onAudioChunk {
                    onAudioChunk(mixedChunk)
                }
            }
        }
    }

    /// Mix system and microphone audio samples
    /// Both sources should be at 16kHz mono
    private func mixAudio(systemSamples: [Float], micSamples: [Float]) -> [Float] {
        guard !systemSamples.isEmpty || !micSamples.isEmpty else { return [] }

        // Determine output length (use longer of the two)
        let outputLength = max(systemSamples.count, micSamples.count)

        var mixed = [Float](repeating: 0, count: outputLength)

        // Mix samples with balance (0.7 system, 0.8 microphone to favor user voice)
        for i in 0..<outputLength {
            var sample: Float = 0

            // Add system audio (slightly reduced to avoid drowning out mic)
            if i < systemSamples.count {
                sample += systemSamples[i] * 0.7
            }

            // Add microphone audio (keep at higher level)
            if i < micSamples.count {
                sample += micSamples[i] * 0.8
            }

            // Soft clipping to prevent distortion
            mixed[i] = tanh(sample)
        }

        // Normalize to prevent clipping while maximizing volume
        return normalizeAudio(mixed)
    }

    /// Normalize audio levels to prevent clipping and improve recognition
    private func normalizeAudio(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var normalized = samples

        // Find the peak amplitude
        var maxAmplitude: Float = 0
        vDSP_maxmgv(samples, 1, &maxAmplitude, vDSP_Length(samples.count))

        // Normalize to 0.9 to prevent clipping while maximizing volume
        if maxAmplitude > 0 {
            var scaleFactor = 0.9 / maxAmplitude
            vDSP_vsmul(samples, 1, &scaleFactor, &normalized, 1, vDSP_Length(samples.count))
        }

        return normalized
    }
}
