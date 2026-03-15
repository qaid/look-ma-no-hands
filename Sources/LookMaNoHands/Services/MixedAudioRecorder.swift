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

    /// Callback for source-classified audio chunks (preferred over onAudioChunk for diarization)
    var onAudioChunkWithSource: ((AudioChunkWithSource) -> Void)?

    // MARK: - Source Classification

    /// Compute root-mean-square energy of audio samples
    static func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    /// Classify the dominant audio source based on pre-mix RMS values
    static func classifySource(
        micRMS: Float,
        systemRMS: Float,
        dominanceRatio: Float = 1.5,
        silenceThreshold: Float = 0.002
    ) -> DiarizationSource {
        let micSilent = micRMS < silenceThreshold
        let systemSilent = systemRMS < silenceThreshold

        if micSilent && systemSilent { return .mixed }
        if micSilent { return .remote }
        if systemSilent { return .local }

        if micRMS >= systemRMS * dominanceRatio { return .local }
        if systemRMS >= micRMS * dominanceRatio { return .remote }
        return .mixed
    }

    // MARK: - Initialization

    init(chunkDuration: TimeInterval = 5) {
        self.systemAudioRecorder = SystemAudioRecorder(chunkDuration: chunkDuration)
        // Enable echo cancellation so the mic doesn't pick up system audio.
        // Note: AEC suppresses mic amplitude during system audio playback, but
        // classifySource uses raw (unnormalized) RMS from both sources for fair
        // comparison. The silence threshold (0.002) is calibrated for raw 16kHz
        // audio where typical speech RMS is 0.01–0.1 and ambient noise is <0.001.
        self.microphoneRecorder = AudioRecorder(useVoiceProcessing: true)

        setupSystemAudioCallback()
    }

    deinit {
        if isRecording {
            _ = microphoneRecorder.stopRecording()
            isRecording = false
        }
    }

    // MARK: - Recording Control

    /// Start capturing and mixing both audio sources
    func startRecording() async throws {
        guard !isRecording else {
            print("MixedAudioRecorder: Already recording")
            return
        }

        // Start both recorders
        // Note: microphoneRecorder.startRecording() will activate the audio session
        // systemAudioRecorder uses ScreenCaptureKit and doesn't need session management
        do {
            try await systemAudioRecorder.startRecording()
            try microphoneRecorder.startRecording()
        } catch {
            // Clean up if either fails
            if systemAudioRecorder.isRecording {
                _ = await systemAudioRecorder.stopRecording()
            }
            if microphoneRecorder.isRecording {
                _ = microphoneRecorder.stopRecording()
            }
            throw error
        }

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

        print("MixedAudioRecorder: Stopped recording")

        return [] // Empty because chunks were sent in real-time
    }

    // MARK: - Audio Mixing

    /// Setup callback from system audio recorder
    /// When system audio has a chunk, drain corresponding microphone audio and mix
    private func setupSystemAudioCallback() {
        systemAudioRecorder.onAudioChunk = { [weak self] systemChunk in
            guard let self = self else { return }

            // Drain raw (unnormalized) mic samples for fair RMS comparison
            let micChunkRaw = self.microphoneRecorder.drainAvailableSamples(normalize: false)

            print("MixedAudioRecorder: System chunk: \(systemChunk.count), mic chunk: \(micChunkRaw.count) samples")

            // Classify source using raw RMS values (both unnormalized for fair comparison)
            let micRMS = Self.computeRMS(micChunkRaw)
            let systemRMS = Self.computeRMS(systemChunk)
            let source = Self.classifySource(micRMS: micRMS, systemRMS: systemRMS)

            // Normalize both sources independently before mixing so system audio
            // (which arrives at lower amplitude from ScreenCaptureKit) is brought
            // to the same level as mic audio
            let micChunk = self.normalizeAudio(micChunkRaw)
            let systemChunkNormalized = self.normalizeAudio(systemChunk)

            // Mix the normalized chunks
            let mixedChunk = self.mixAudio(systemSamples: systemChunkNormalized, micSamples: micChunk)

            // Send the mixed chunk via the source-aware callback if set, otherwise fall back
            if self.onAudioChunkWithSource != nil {
                self.onAudioChunkWithSource?(AudioChunkWithSource(samples: mixedChunk, source: source))
            } else {
                self.onAudioChunk?(mixedChunk)
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

        // Mix samples with equal balance (both sources are pre-normalized)
        for i in 0..<outputLength {
            var sample: Float = 0

            if i < systemSamples.count {
                sample += systemSamples[i] * 0.7
            }

            if i < micSamples.count {
                sample += micSamples[i] * 0.7
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

    // MARK: - Frequency Visualization

    /// Get frequency bands for waveform visualization
    /// Analyzes the mixed audio (system + microphone) to show all captured sound
    /// This visualizes both remote participants and your own voice
    func getFrequencyBands(bandCount: Int) -> [Float] {
        guard isRecording else {
            return Array(repeating: 0.0, count: bandCount)
        }

        // Get current samples from both sources
        let systemSamples = systemAudioRecorder.getFrequencyBands(bandCount: bandCount)
        let micSamples = microphoneRecorder.getFrequencyBands(bandCount: bandCount)

        // Mix the frequency bands (take the maximum of each band to show both sources)
        var mixedBands: [Float] = []
        for i in 0..<bandCount {
            let systemLevel = i < systemSamples.count ? systemSamples[i] : 0.0
            let micLevel = i < micSamples.count ? micSamples[i] : 0.0
            // Use max so whichever source is active drives the visualizer
            let mixed = max(systemLevel, micLevel)
            mixedBands.append(mixed)
        }

        return mixedBands
    }
}
