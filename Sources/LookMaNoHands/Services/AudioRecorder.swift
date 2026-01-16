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

    /// Stop recording and return the captured audio data
    /// - Returns: Audio samples as Float array at 16kHz
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false

        // Calculate recording duration
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        print("AudioRecorder: Stopped recording after \(String(format: "%.2f", duration))s, captured \(audioBuffer.count) samples at \(inputSampleRate) Hz")

        // Warn if recording is too short
        if duration < minimumDuration {
            print("AudioRecorder: Warning - Recording is very short (\(String(format: "%.2f", duration))s), may not transcribe well")
        }

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(inputSampleRate - targetSampleRate) > 0.1 {
            print("AudioRecorder: Resampling from \(inputSampleRate) Hz to \(targetSampleRate) Hz")
            resampled = resampleToTarget(audioBuffer)
            print("AudioRecorder: Resampled to \(resampled.count) samples")
        } else {
            resampled = audioBuffer
        }

        // Normalize audio levels
        let normalized = normalizeAudio(resampled)

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

