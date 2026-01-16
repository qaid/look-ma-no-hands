import Foundation
import AVFoundation

/// Segment of transcribed audio with timing information
struct TranscriptSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let timestamp: Date
}

/// Service for continuous transcription of long-form audio
/// Handles chunking, overlapping windows, and segment stitching
@available(macOS 13.0, *)
class ContinuousTranscriber {

    // MARK: - Properties

    /// Whisper service for transcription
    private let whisperService: WhisperService

    /// Buffer of transcribed segments
    private var segments: [TranscriptSegment] = []

    /// Audio buffer for chunking
    private var audioBuffer: [Float] = []

    /// Sample rate (should match recorder, Whisper expects 16kHz)
    private let sampleRate: Double = 16000

    /// Chunk size in seconds (5 seconds for fast, responsive transcription)
    private let chunkDuration: TimeInterval = 5

    /// Overlap between chunks in seconds (1 second to prevent word clipping)
    private let overlapDuration: TimeInterval = 1

    /// Minimum audio energy threshold for silence detection
    private let silenceThreshold: Float = 0.01

    /// Duration of silence (in seconds) before processing chunk early
    private let silenceDuration: TimeInterval = 2.0

    /// Whether we're currently transcribing
    private(set) var isTranscribing = false

    /// Start time of current recording session
    private var sessionStartTime: Date?

    /// Total samples processed in current session
    private var totalSamplesProcessed: Int = 0

    /// Queue for processing audio chunks
    private let processingQueue = DispatchQueue(label: "com.lookmanohands.transcription", qos: .userInitiated)

    /// Callback for new transcript segments
    var onSegmentTranscribed: ((TranscriptSegment) -> Void)?

    /// Callback for processing status updates
    var onStatusUpdate: ((String) -> Void)?

    // MARK: - Initialization

    init(whisperService: WhisperService) {
        self.whisperService = whisperService
    }

    // MARK: - Session Control

    /// Start a new transcription session
    func startSession() {
        guard !isTranscribing else {
            print("ContinuousTranscriber: Already transcribing")
            return
        }

        isTranscribing = true
        sessionStartTime = Date()
        totalSamplesProcessed = 0
        audioBuffer.removeAll()
        segments.removeAll()

        print("ContinuousTranscriber: Started new session")
        onStatusUpdate?("Ready to transcribe")
    }

    /// End transcription session and return all segments
    func endSession() async -> [TranscriptSegment] {
        guard isTranscribing else {
            print("ContinuousTranscriber: Not transcribing")
            return []
        }

        // Process any remaining audio in buffer
        if !audioBuffer.isEmpty {
            await processChunk(audioBuffer, isFinal: true)
        }

        isTranscribing = false
        sessionStartTime = nil
        audioBuffer.removeAll()

        let allSegments = segments
        segments.removeAll()

        print("ContinuousTranscriber: Session ended, \(allSegments.count) segments")
        onStatusUpdate?("Transcription complete")

        return allSegments
    }

    // MARK: - Audio Input

    /// Add audio samples to the buffer for processing
    /// Processes chunks automatically when threshold is reached
    func addAudio(_ samples: [Float]) async {
        guard isTranscribing else { return }

        audioBuffer.append(contentsOf: samples)

        let chunkSamples = Int(chunkDuration * sampleRate)

        // Check if we have enough samples for a chunk
        if audioBuffer.count >= chunkSamples {
            await processNextChunk()
        } else {
            // Check for silence to process early
            if detectSilence(in: samples) {
                await processSilenceChunk()
            }
        }
    }

    // MARK: - Chunk Processing

    /// Process the next chunk from the buffer
    private func processNextChunk() async {
        let chunkSamples = Int(chunkDuration * sampleRate)
        let overlapSamples = Int(overlapDuration * sampleRate)

        // Extract chunk with overlap consideration
        let chunk = Array(audioBuffer.prefix(chunkSamples))

        // Process the chunk
        await processChunk(chunk, isFinal: false)

        // Remove processed samples, keeping overlap for next chunk
        let samplesToRemove = chunkSamples - overlapSamples
        audioBuffer.removeFirst(min(samplesToRemove, audioBuffer.count))
    }

    /// Process a chunk early if silence is detected
    private func processSilenceChunk() async {
        guard !audioBuffer.isEmpty else { return }

        let silenceSamples = Int(silenceDuration * sampleRate)

        // Only process if we have enough audio before the silence
        if audioBuffer.count > silenceSamples {
            let chunk = Array(audioBuffer)
            await processChunk(chunk, isFinal: false)

            // Clear buffer after processing
            audioBuffer.removeAll()
        }
    }

    /// Process a single audio chunk through Whisper
    private func processChunk(_ samples: [Float], isFinal: Bool) async {
        guard !samples.isEmpty else { return }

        let duration = Double(samples.count) / sampleRate
        print("ContinuousTranscriber: Processing \(String(format: "%.1f", duration))s chunk (final: \(isFinal))")

        onStatusUpdate?("Transcribing...")

        do {
            // Transcribe the chunk
            let text = try await whisperService.transcribe(samples: samples)

            guard !text.isEmpty else {
                print("ContinuousTranscriber: Empty transcription result")
                return
            }

            // Calculate timing for this segment
            let startTime = Double(totalSamplesProcessed) / sampleRate
            let endTime = startTime + duration

            let segment = TranscriptSegment(
                text: text,
                startTime: startTime,
                endTime: endTime,
                timestamp: Date()
            )

            segments.append(segment)
            totalSamplesProcessed += samples.count

            print("ContinuousTranscriber: Transcribed segment [\(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s]: \"\(text)\"")

            onSegmentTranscribed?(segment)
            onStatusUpdate?("Recording")

        } catch {
            print("ContinuousTranscriber: Transcription error - \(error)")
            onStatusUpdate?("Transcription error: \(error.localizedDescription)")
        }
    }

    // MARK: - Silence Detection

    /// Detect if the audio samples contain silence
    private func detectSilence(in samples: [Float]) -> Bool {
        guard samples.count >= Int(silenceDuration * sampleRate) else {
            return false
        }

        // Check last N samples for silence
        let silenceSamples = Int(silenceDuration * sampleRate)
        let recentSamples = samples.suffix(silenceSamples)

        // Calculate RMS energy
        let sumOfSquares = recentSamples.reduce(0.0) { $0 + ($1 * $1) }
        let rms = sqrt(sumOfSquares / Float(recentSamples.count))

        return rms < silenceThreshold
    }

    // MARK: - Transcript Access

    /// Get the full transcript from all segments
    func getFullTranscript() -> String {
        return segments
            .map { $0.text }
            .joined(separator: " ")
    }

    /// Get transcript with timestamps
    func getTimestampedTranscript() -> String {
        return segments
            .map { segment in
                let timestamp = formatTimestamp(segment.startTime)
                return "[\(timestamp)] \(segment.text)"
            }
            .joined(separator: "\n")
    }

    /// Format a timestamp for display
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
