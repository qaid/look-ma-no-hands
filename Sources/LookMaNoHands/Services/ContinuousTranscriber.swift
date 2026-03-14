import Foundation
import AVFoundation
import Accelerate

/// Segment of transcribed audio with timing information
struct TranscriptSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let timestamp: Date
    let source: DiarizationSource
    let speakerChangeOffsets: [TimeInterval]

    init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        timestamp: Date,
        source: DiarizationSource = .unknown,
        speakerChangeOffsets: [TimeInterval] = []
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.timestamp = timestamp
        self.source = source
        self.speakerChangeOffsets = speakerChangeOffsets
    }
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

    /// Minimum audio energy threshold for early chunk processing (higher = less sensitive).
    /// Intentionally higher than detectPauses' threshold (0.005) because this controls
    /// when to flush the buffer early, where false positives waste processing time.
    private let silenceThreshold: Float = 0.01

    /// Duration of silence (in seconds) before processing chunk early
    private let silenceDuration: TimeInterval = 2.0

    /// Whether we're currently transcribing
    private(set) var isTranscribing = false

    /// Start time of current recording session
    private var sessionStartTime: Date?

    /// Total samples processed in current session
    private var totalSamplesProcessed: Int = 0

    /// Accumulated time offset from previous sessions (for Continue Recording)
    private var timeOffset: TimeInterval = 0

    /// Queue for processing audio chunks
    private let processingQueue = DispatchQueue(label: "com.lookmanohands.transcription", qos: .userInitiated)

    /// Accumulated source classifications for chunks in the current audio buffer.
    /// Each entry records (sampleCount, source) so we can pick the dominant source
    /// when the buffer is finally processed (multiple small chunks may fill one buffer).
    private var sourceAccumulator: [(sampleCount: Int, source: DiarizationSource)] = []

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
        sourceAccumulator.removeAll()
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

        // Accumulate time offset so next session's timestamps continue from here
        timeOffset += Double(totalSamplesProcessed) / sampleRate

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

    /// Add a source-classified audio chunk for processing
    func addAudio(_ chunk: AudioChunkWithSource) async {
        sourceAccumulator.append((sampleCount: chunk.samples.count, source: chunk.source))
        await addAudio(chunk.samples)
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

        // Resolve the dominant source from accumulated classifications weighted by sample count
        let chunkSource = resolveDominantSource()
        sourceAccumulator.removeAll()

        // Detect speaker changes for remote/mixed audio before transcribing
        let pauseOffsets: [TimeInterval]
        if chunkSource == .remote || chunkSource == .mixed {
            pauseOffsets = detectPauses(in: samples)
        } else {
            pauseOffsets = []
        }

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
            let startTime = Double(totalSamplesProcessed) / sampleRate + timeOffset
            let endTime = startTime + duration

            let segment = TranscriptSegment(
                text: dedupedText,
                startTime: startTime,
                endTime: endTime,
                timestamp: Date(),
                source: chunkSource,
                speakerChangeOffsets: pauseOffsets
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

    /// Resolve the dominant diarization source from accumulated chunk classifications.
    /// Uses sample-count-weighted voting so longer chunks have proportional influence.
    private func resolveDominantSource() -> DiarizationSource {
        guard !sourceAccumulator.isEmpty else { return .unknown }

        var weights: [DiarizationSource: Int] = [:]
        for entry in sourceAccumulator {
            weights[entry.source, default: 0] += entry.sampleCount
        }

        return weights.max(by: { $0.value < $1.value })?.key ?? .unknown
    }

    // MARK: - Pause Detection

    /// Detect silence gaps >= 500ms in a chunk that indicate potential speaker changes.
    /// Returns offsets (relative to chunk start, in seconds) at the midpoint of each detected pause.
    func detectPauses(
        in samples: [Float],
        minPauseDuration: TimeInterval = 0.5,
        silenceThreshold: Float = 0.005
    ) -> [TimeInterval] {
        let windowSize = Int(0.05 * sampleRate)  // 50ms analysis windows
        guard samples.count >= windowSize else { return [] }

        var pauseOffsets: [TimeInterval] = []
        var silenceStartIndex: Int? = nil

        var windowIndex = 0
        while windowIndex + windowSize <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + windowIndex, 1, &rms, vDSP_Length(windowSize))
            }

            if rms < silenceThreshold {
                if silenceStartIndex == nil {
                    silenceStartIndex = windowIndex
                }
            } else {
                if let startIdx = silenceStartIndex {
                    let pauseSamples = windowIndex - startIdx
                    let pauseDuration = Double(pauseSamples) / sampleRate
                    if pauseDuration >= minPauseDuration {
                        let midSample = startIdx + pauseSamples / 2
                        let midOffset = Double(midSample) / sampleRate
                        pauseOffsets.append(midOffset)
                    }
                    silenceStartIndex = nil
                }
            }

            windowIndex += windowSize
        }

        // Handle trailing silence
        if let startIdx = silenceStartIndex {
            let pauseSamples = samples.count - startIdx
            let pauseDuration = Double(pauseSamples) / sampleRate
            if pauseDuration >= minPauseDuration {
                let midSample = startIdx + pauseSamples / 2
                let midOffset = Double(midSample) / sampleRate
                pauseOffsets.append(midOffset)
            }
        }

        return pauseOffsets
    }

    // MARK: - Segment Deduplication

    /// Remove text from the start of `newText` that overlaps with the end of the previous segment.
    /// Finds the longest suffix of the previous segment that matches a prefix of the new text.
    func deduplicateAgainstPrevious(_ newText: String) -> String {
        guard let lastText = segments.last?.text else { return newText }

        let lastWords = lastText.split(separator: " ").map { $0.lowercased() }
        let newWords = newText.split(separator: " ")
        guard !lastWords.isEmpty, !newWords.isEmpty else { return newText }

        let newWordsLower = newWords.map { $0.lowercased() }

        // Check up to 15 words of overlap
        let maxCheck = min(lastWords.count, newWords.count, 15)
        var bestOverlap = 0
        for len in 1...maxCheck {
            if lastWords.suffix(len).elementsEqual(newWordsLower.prefix(len)) {
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
        timeOffset = 0
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
