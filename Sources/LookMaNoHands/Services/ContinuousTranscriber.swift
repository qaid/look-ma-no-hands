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
/// Handles chunking, segment deduplication, and segment stitching
@available(macOS 13.0, *)
class ContinuousTranscriber {

    // MARK: - Properties

    /// Whisper service for transcription
    private let whisperService: WhisperService

    /// Buffer of transcribed segments
    private(set) var segments: [TranscriptSegment] = []

    /// Audio buffer for chunking
    private var audioBuffer: [Float] = []

    /// Sample rate (should match recorder, Whisper expects 16kHz)
    private let sampleRate: Double = 16000

    /// Chunk size in seconds (default 5s for dictation, 10s recommended for meetings)
    private let chunkDuration: TimeInterval

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

    init(whisperService: WhisperService, chunkDuration: TimeInterval = 5) {
        self.whisperService = whisperService
        self.chunkDuration = chunkDuration
    }

    deinit {
        isTranscribing = false
        audioBuffer.removeAll()
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
        // Don't remove existing segments - preserve them to append new transcription

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

        // Extract chunk without overlap to prevent duplicate transcription
        let chunk = Array(audioBuffer.prefix(chunkSamples))

        // Process the chunk
        await processChunk(chunk, isFinal: false)

        // Remove all processed samples (no overlap needed - causes duplicates)
        audioBuffer.removeFirst(min(chunkSamples, audioBuffer.count))
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

            // Remove text that overlaps with the previous segment
            let dedupedText = deduplicateAgainstPrevious(text)
            guard !dedupedText.isEmpty else {
                print("ContinuousTranscriber: Segment fully duplicated, skipping")
                totalSamplesProcessed += samples.count
                return
            }

            // Calculate timing for this segment
            let startTime = Double(totalSamplesProcessed) / sampleRate
            let endTime = startTime + duration

            let segment = TranscriptSegment(
                text: dedupedText,
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

    // MARK: - Segment Deduplication

    /// Remove text from the start of `newText` that overlaps with the end of the previous segment.
    /// Finds the longest suffix of the previous segment that matches a prefix of the new text.
    func deduplicateAgainstPrevious(_ newText: String) -> String {
        guard let lastText = segments.last?.text else { return newText }

        let lastWords = lastText.split(separator: " ")
        let newWords = newText.split(separator: " ")
        guard !lastWords.isEmpty, !newWords.isEmpty else { return newText }

        // Check up to 15 words of overlap
        let maxCheck = min(lastWords.count, newWords.count, 15)
        var bestOverlap = 0
        for len in 1...maxCheck {
            let suffix = lastWords.suffix(len)
            let prefix = newWords.prefix(len)
            if Array(suffix).map({ $0.lowercased() }) == Array(prefix).map({ $0.lowercased() }) {
                bestOverlap = len
            }
        }

        if bestOverlap > 0 {
            let result = newWords.dropFirst(bestOverlap).joined(separator: " ")
            print("ContinuousTranscriber: Deduped \(bestOverlap) overlapping words")
            return result
        }
        return newText
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

    /// Append a segment directly (used for testing deduplication logic)
    func appendSegment(_ segment: TranscriptSegment) {
        segments.append(segment)
    }

    /// Clear all segments (for user-initiated transcript clearing)
    func clearSegments() {
        segments.removeAll()
        totalSamplesProcessed = 0
        print("ContinuousTranscriber: Cleared all segments")
    }

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
