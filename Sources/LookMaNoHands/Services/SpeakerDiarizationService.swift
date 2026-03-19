import Foundation
import SpeakerKit

/// Post-recording speaker diarization using SpeakerKit (Pyannote).
/// Runs on accumulated system audio to identify individual remote speakers.
@available(macOS 13.0, *)
class SpeakerDiarizationService: @unchecked Sendable {

    /// Minimum audio duration (seconds) worth diarizing
    private static let minimumAudioDuration: Double = 2.0

    /// Lazily initialized SpeakerKit instance
    private var speakerKit: SpeakerKit?

    /// Number of speakers detected in the last run
    private(set) var lastSpeakerCount: Int = 0

    // MARK: - Public API

    /// Diarize system audio and assign speaker labels to remote transcript segments.
    ///
    /// For each remote/mixed segment, finds overlapping SpeakerKit segments by time range
    /// and assigns the dominant speaker's label. Returns new segments with `speakerLabel` set.
    ///
    /// - Parameters:
    ///   - systemAudio: Raw system audio samples at 16kHz mono
    ///   - remoteSegments: Transcript segments classified as .remote or .mixed
    ///   - onProgress: Optional status callback for UI updates
    /// - Returns: Segments with `speakerLabel` populated
    func diarize(
        systemAudio: [Float],
        remoteSegments: [TranscriptSegment],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        let audioDuration = Double(systemAudio.count) / 16000.0
        guard audioDuration >= Self.minimumAudioDuration else {
            Logger.shared.info("SpeakerKit: Audio too short (\(String(format: "%.1f", audioDuration))s), skipping diarization", category: .transcription)
            return remoteSegments
        }

        guard !remoteSegments.isEmpty else { return remoteSegments }

        onProgress?("Loading speaker models...")
        let kit = try await getOrCreateSpeakerKit()

        onProgress?("Identifying speakers...")
        Logger.shared.info("SpeakerKit: Diarizing \(String(format: "%.1f", audioDuration))s of system audio", category: .transcription)

        let result = try await kit.diarize(audioArray: systemAudio)
        lastSpeakerCount = result.speakerCount

        Logger.shared.info("SpeakerKit: Detected \(result.speakerCount) speaker(s) in \(result.segments.count) segments", category: .transcription)

        // Map SpeakerKit results onto transcript segments
        let labeled = mapSpeakerLabels(
            speakerSegments: result.segments,
            transcriptSegments: remoteSegments
        )

        // Free model memory and clear the reference so a subsequent diarize()
        // call creates a fresh SpeakerKit instance instead of reusing the unloaded one.
        await kit.unloadModels()
        speakerKit = nil

        onProgress?("Speaker identification complete")
        return labeled
    }

    // MARK: - Private

    private func getOrCreateSpeakerKit() async throws -> SpeakerKit {
        if let existing = speakerKit { return existing }
        let kit = try await SpeakerKit(PyannoteConfig())
        speakerKit = kit
        return kit
    }

    /// Map SpeakerKit speaker segments onto transcript segments by temporal overlap.
    /// For each transcript segment, find the SpeakerKit segment(s) that overlap with its
    /// time range and pick the dominant speaker.
    private func mapSpeakerLabels(
        speakerSegments: [SpeakerSegment],
        transcriptSegments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        return transcriptSegments.map { seg in
            let label = dominantSpeakerLabel(
                for: seg.startTime, end: seg.endTime,
                speakerSegments: speakerSegments
            )
            return TranscriptSegment(
                text: seg.text,
                startTime: seg.startTime,
                endTime: seg.endTime,
                timestamp: seg.timestamp,
                source: seg.source,
                speakerChangeOffsets: seg.speakerChangeOffsets,
                speakerLabel: label
            )
        }
    }

    /// Find the dominant speaker for a given time range by computing overlap duration
    /// with each SpeakerKit segment.
    private func dominantSpeakerLabel(
        for start: TimeInterval, end: TimeInterval,
        speakerSegments: [SpeakerSegment]
    ) -> String? {
        var speakerOverlap: [Int: Double] = [:]

        for seg in speakerSegments {
            let segStart = TimeInterval(seg.startTime)
            let segEnd = TimeInterval(seg.endTime)
            let overlapStart = max(start, segStart)
            let overlapEnd = min(end, segEnd)
            let overlap = overlapEnd - overlapStart

            guard overlap > 0 else { continue }

            for id in seg.speaker.speakerIds {
                speakerOverlap[id, default: 0] += overlap
            }
        }

        guard let (dominantId, _) = speakerOverlap.max(by: { $0.value < $1.value }) else {
            return nil
        }

        return Self.labelForSpeakerId(dominantId)
    }

    /// Convert a numeric speaker ID to a letter-based label: 0 → "Speaker A", 1 → "Speaker B", etc.
    static func labelForSpeakerId(_ id: Int) -> String {
        guard id >= 0 else { return "Speaker \(abs(id))" }
        let letter = id < 26
            ? String(UnicodeScalar(UInt8(65 + id)))  // A-Z
            : "\(id + 1)"
        return "Speaker \(letter)"
    }

    /// Convert a SpeakerInfo to a human-readable label.
    static func labelForSpeakerInfo(_ info: SpeakerInfo) -> String {
        switch info {
        case .speakerId(let id):
            return labelForSpeakerId(id)
        case .multiple(let ids):
            let labels = ids.sorted().map { labelForSpeakerId($0) }
            return labels.joined(separator: " & ")
        case .noMatch:
            return "Remote"
        @unknown default:
            return "Remote"
        }
    }
}
