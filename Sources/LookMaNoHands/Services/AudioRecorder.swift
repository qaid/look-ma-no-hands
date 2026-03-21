import Foundation
import AVFoundation
import Accelerate

/// Records audio from the microphone
/// Outputs audio data suitable for Whisper transcription (16kHz, mono)
class AudioRecorder: @unchecked Sendable {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()  // Thread-safe access to audioBuffer
    private var inputSampleRate: Double = 0
    private var recordingStartTime: Date?

    /// Whether recording is currently in progress
    private(set) var isRecording = false

    /// Whether to enable voice processing (echo cancellation) for meeting mode.
    /// Set at init time; read during startRecording() to configure the audio engine.
    let useVoiceProcessing: Bool

    init(useVoiceProcessing: Bool = false) {
        self.useVoiceProcessing = useVoiceProcessing
    }

    /// The sample rate required by Whisper
    private let targetSampleRate: Double = 16000

    /// Minimum recording duration in seconds (helps avoid false detections)
    private let minimumDuration: TimeInterval = 0.5

    
    // MARK: - Public Methods
    
    /// Start recording audio from the microphone
    /// - Throws: If audio engine fails to start
    func startRecording() throws {
        guard !isRecording else { return }

        // Clear any previous buffer (thread-safe)
        bufferLock.withLock {
            audioBuffer = []
        }

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode

        // Optional voice processing (echo cancellation). Currently unused in
        // meeting mode because it causes macOS to duck system audio even with
        // duckingLevel=.min. Meeting mode instead compensates for speaker bleed
        // in MixedAudioRecorder.classifySource.
        if useVoiceProcessing {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                print("AudioRecorder: Voice processing (AEC) enabled")
            } catch {
                print("AudioRecorder: Failed to enable voice processing: \(error)")
            }
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Store the input sample rate for resampling later
        self.inputSampleRate = inputFormat.sampleRate

        print("AudioRecorder: Input format - \(inputFormat)")
        print("AudioRecorder: Sample rate: \(inputFormat.sampleRate) Hz, Channels: \(inputFormat.channelCount)")

        // Install tap on input to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }

        try audioEngine.start()
        isRecording = true
        recordingStartTime = Date()

        print("AudioRecorder: Started recording")
    }
    
    /// Drain buffered microphone samples for mixing, keeping only recent samples for visualization.
    /// Returns resampled audio at 16kHz. Drained samples are removed from the buffer.
    /// - Parameter normalize: If true (default), normalizes audio to 0.9 peak. Pass false when
    ///   raw samples are needed for RMS comparison (e.g., source classification).
    func drainAvailableSamples(normalize: Bool = true) -> [Float] {
        guard isRecording else { return [] }

        let rawSamples: [Float] = bufferLock.withLock {
            // Keep last 2048 samples for frequency visualization
            let vizSamples = 2048
            let drainCount = max(0, audioBuffer.count - vizSamples)
            guard drainCount > 0 else { return [] }
            let samples = Array(audioBuffer.prefix(drainCount))
            audioBuffer.removeFirst(drainCount)
            return samples
        }

        guard !rawSamples.isEmpty else { return [] }

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(inputSampleRate - targetSampleRate) > 0.1 {
            resampled = resampleToTarget(rawSamples)
        } else {
            resampled = rawSamples
        }

        // Normalize audio levels to match stopRecording() behavior
        return normalize ? normalizeAudio(resampled) : resampled
    }

    /// Get frequency band levels for waveform visualization
    /// - Parameter bandCount: Number of frequency bands to analyze (default: 20)
    /// - Returns: Array of normalized amplitude values (0-1 range) for each band
    func getFrequencyBands(bandCount: Int = 20) -> [Float] {
        guard isRecording else {
            return Array(repeating: 0.0, count: bandCount)
        }

        // Thread-safe copy of recent samples
        let recentSamples: [Float] = bufferLock.withLock {
            // Use smaller threshold - 512 samples ≈ 32ms at 16kHz
            guard audioBuffer.count > 512 else {
                return []
            }

            // Get recent samples (copy while holding lock)
            let sampleCount = min(1024, audioBuffer.count)
            return Array(audioBuffer.suffix(sampleCount))
        }

        guard !recentSamples.isEmpty else {
            return Array(repeating: 0.0, count: bandCount)
        }

        let bandSize = recentSamples.count / bandCount
        var bands: [Float] = []

        // Calculate RMS for each frequency band
        for i in 0..<bandCount {
            let start = i * bandSize
            let end = min(start + bandSize, recentSamples.count)
            let bandSamples = Array(recentSamples[start..<end])

            var rms: Float = 0
            bandSamples.withUnsafeBufferPointer { ptr in
                vDSP_rmsqv(ptr.baseAddress!, 1, &rms, vDSP_Length(bandSamples.count))
            }

            // Amplification: moderate gain so typical speech sits around 0.4–0.7
            // rather than constantly peaking at 1.0
            let amplified = min(rms * 15.0, 1.0)
            bands.append(amplified)
        }

        return bands
    }

    /// Stop recording and return the captured audio data
    /// - Returns: Audio samples as Float array at 16kHz
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        let stopTime = Date()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false

        // Thread-safe copy of buffer and clear it
        let bufferCopy = bufferLock.withLock {
            let copy = audioBuffer
            audioBuffer = []  // Clear for next recording
            return copy
        }

        // Calculate recording duration
        let duration = stopTime.timeIntervalSince(recordingStartTime ?? Date())
        Logger.shared.info("🛑 Recording stopped: \(String(format: "%.2f", duration))s, \(bufferCopy.count) samples at \(Int(inputSampleRate)) Hz", category: .audio)

        // Warn if recording is too short
        if duration < minimumDuration {
            Logger.shared.warning("Recording is very short (\(String(format: "%.2f", duration))s), may not transcribe well", category: .audio)
        }

        let processingStart = Date()

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(inputSampleRate - targetSampleRate) > 0.1 {
            Logger.shared.debug("Resampling from \(Int(inputSampleRate)) Hz to \(Int(targetSampleRate)) Hz", category: .audio)
            resampled = resampleToTarget(bufferCopy)
            Logger.shared.debug("Resampled to \(resampled.count) samples", category: .audio)
        } else {
            resampled = bufferCopy
        }

        // Normalize audio levels
        let normalized = normalizeAudio(resampled)

        let processingTime = Date().timeIntervalSince(processingStart)
        Logger.shared.info("✅ Audio processing complete in \(String(format: "%.3f", processingTime))s, output: \(normalized.count) samples", category: .audio)

        return normalized
    }
    
    // MARK: - Private Methods

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let length = vDSP_Length(frameCount)

        // Convert to mono using vectorized operations
        var samples: [Float]
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else if channelCount == 2 {
            samples = [Float](repeating: 0, count: frameCount)
            vDSP_vadd(channelData[0], 1, channelData[1], 1, &samples, 1, length)
            var half: Float = 0.5
            vDSP_vsmul(samples, 1, &half, &samples, 1, length)
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            for ch in 1..<channelCount {
                vDSP_vadd(samples, 1, channelData[ch], 1, &samples, 1, length)
            }
            var scale = 1.0 / Float(channelCount)
            vDSP_vsmul(samples, 1, &scale, &samples, 1, length)
        }

        // Thread-safe append to buffer
        bufferLock.withLock {
            audioBuffer.append(contentsOf: samples)
        }
    }

    /// Resample audio to 16kHz using vectorized vDSP linear interpolation
    private func resampleToTarget(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let inputLength = samples.count
        let ratio = targetSampleRate / inputSampleRate
        let outputLength = Int(Double(inputLength) * ratio)
        guard outputLength > 0 else { return [] }

        // Build fractional index ramp: [0, 1/ratio, 2/ratio, ...]
        // vDSP_vlint interprets each value as: integer part = base index, fractional part = blend weight
        var indices = [Float](repeating: 0, count: outputLength)
        var start: Float = 0.0
        var step = Float(1.0 / ratio)
        vDSP_vramp(&start, &step, &indices, 1, vDSP_Length(outputLength))

        // Clamp to valid range — vDSP_vlint reads index[i] and index[i]+1
        var maxIndex = Float(inputLength - 2)
        var zero: Float = 0.0
        vDSP_vclip(indices, 1, &zero, &maxIndex, &indices, 1, vDSP_Length(outputLength))

        var output = [Float](repeating: 0, count: outputLength)

        samples.withUnsafeBufferPointer { inputPtr in
            vDSP_vlint(
                inputPtr.baseAddress!,
                indices,
                1,
                &output,
                1,
                vDSP_Length(outputLength),
                vDSP_Length(inputLength)
            )
        }

        return output
    }

    /// Normalize audio levels to prevent clipping and improve recognition
    private func normalizeAudio(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        // Find the peak amplitude
        var maxAmplitude: Float = 0
        vDSP_maxmgv(samples, 1, &maxAmplitude, vDSP_Length(samples.count))

        // Skip normalization if peak is already in acceptable range for Whisper
        guard maxAmplitude > 0, maxAmplitude < 0.7 || maxAmplitude > 1.0 else {
            return samples
        }

        // Normalize to 0.9 to prevent clipping while maximizing volume
        var normalized = samples
        var scaleFactor = 0.9 / maxAmplitude
        vDSP_vsmul(samples, 1, &scaleFactor, &normalized, 1, vDSP_Length(samples.count))
        print("AudioRecorder: Normalized audio (peak: \(maxAmplitude) → 0.9)")

        return normalized
    }
}

