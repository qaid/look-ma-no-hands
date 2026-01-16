import Foundation

/// Represents an identified speaker in a meeting transcript
struct SpeakerIdentity {
    /// Speaker label (e.g., "You", "Speaker 1", "Speaker 2")
    let label: String

    /// Whether this is the local speaker (microphone audio)
    let isLocalSpeaker: Bool

    /// Indices of segments belonging to this speaker
    var segmentIndices: [Int]

    /// Sample phrases characteristic of this speaker (for context)
    var characteristicPhrases: [String]
}

/// Result of speaker diarization analysis
struct DiarizationResult {
    /// Transcript segments with speaker labels assigned
    let segments: [TranscriptSegment]

    /// All identified speakers in the conversation
    let speakers: [SpeakerIdentity]

    /// Confidence level of the diarization
    let confidence: DiarizationConfidence
}

/// Confidence level for speaker diarization
enum DiarizationConfidence {
    case high       // Clear patterns, distinct speakers
    case medium     // Some ambiguity in speaker identification
    case low        // Difficult to distinguish, using fallback heuristics

    var description: String {
        switch self {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence"
        case .low:
            return "Low confidence (basic labels)"
        }
    }
}
