import Foundation
import AVFoundation
import Accelerate

/// Records audio from the microphone
/// Outputs audio data suitable for Whisper transcription (16kHz, mono)
class AudioRecorder {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var inputSampleRate: Double = 0
    private var recordingStartTime: Date?

    /// Whether recording is currently in progress
    private(set) var isRecording = false

    /// The sample rate required by Whisper
    private let targetSampleRate: Double = 16000

    /// Minimum recording duration in seconds (helps avoid false detections)
    private let minimumDuration: TimeInterval = 0.5

    
    // MARK: - Public Methods
    
    /// Start recording audio from the microphone
    /// - Throws: If audio engine fails to start
    func startRecording() throws {
        guard !isRecording else { return }

        // Clear any previous buffer
        audioBuffer = []

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
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
    
    /// Get current buffer without stopping recording (for mixing scenarios)
    /// - Returns: Audio samples as Float array at 16kHz
    func getCurrentBuffer() -> [Float] {
        guard isRecording else { return [] }

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(inputSampleRate - targetSampleRate) > 0.1 {
            resampled = resampleToTarget(audioBuffer)
        } else {
            resampled = audioBuffer
        }

        // Normalize audio levels
        let normalized = normalizeAudio(resampled)

        return normalized
    }

    /// Get frequency band levels for waveform visualization
    /// - Parameter bandCount: Number of frequency bands to analyze (default: 20)
    /// - Returns: Array of normalized amplitude values (0-1 range) for each band
    func getFrequencyBands(bandCount: Int = 20) -> [Float] {
        guard isRecording else {
            return Array(repeating: 0.0, count: bandCount)
        }

        // Use smaller threshold - 512 samples ≈ 32ms at 16kHz
        guard audioBuffer.count > 512 else {
            return Array(repeating: 0.0, count: bandCount)
        }

        // Get recent samples
        let sampleCount = min(1024, audioBuffer.count)
        let recentSamples = Array(audioBuffer.suffix(sampleCount))
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

            // Amplification (50x) for good visibility
            let amplified = min(rms * 50.0, 1.0)
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

        // Calculate recording duration
        let duration = stopTime.timeIntervalSince(recordingStartTime ?? Date())
        Logger.shared.info("🛑 Recording stopped: \(String(format: "%.2f", duration))s, \(audioBuffer.count) samples at \(Int(inputSampleRate)) Hz", category: .audio)

        // Warn if recording is too short
        if duration < minimumDuration {
            Logger.shared.warning("Recording is very short (\(String(format: "%.2f", duration))s), may not transcribe well", category: .audio)
        }

        let processingStart = Date()

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(inputSampleRate - targetSampleRate) > 0.1 {
            Logger.shared.debug("Resampling from \(Int(inputSampleRate)) Hz to \(Int(targetSampleRate)) Hz", category: .audio)
            resampled = resampleToTarget(audioBuffer)
            Logger.shared.debug("Resampled to \(resampled.count) samples", category: .audio)
        } else {
            resampled = audioBuffer
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

        // Convert to mono and collect samples
        for frame in 0..<frameCount {
            var sample: Float = 0

            // Average all channels to mono
            for channel in 0..<channelCount {
                sample += channelData[channel][frame]
            }
            sample /= Float(channelCount)

            audioBuffer.append(sample)
        }
    }

    /// Resample audio to 16kHz using Accelerate framework
    private func resampleToTarget(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let inputLength = samples.count
        let ratio = targetSampleRate / inputSampleRate
        let outputLength = Int(Double(inputLength) * ratio)

        var output = [Float](repeating: 0, count: outputLength)

        // Use vDSP for high-quality linear interpolation
        samples.withUnsafeBufferPointer { inputPtr in
            output.withUnsafeMutableBufferPointer { outputPtr in
                for i in 0..<outputLength {
                    let inputIndex = Double(i) / ratio
                    let lowerIndex = Int(inputIndex)
                    let upperIndex = min(lowerIndex + 1, inputLength - 1)
                    let fraction = Float(inputIndex - Double(lowerIndex))

                    outputPtr[i] = inputPtr[lowerIndex] * (1 - fraction) + inputPtr[upperIndex] * fraction
                }
            }
        }

        return output
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
            print("AudioRecorder: Normalized audio (peak: \(maxAmplitude) → 0.9)")
        }

        return normalized
    }
}

