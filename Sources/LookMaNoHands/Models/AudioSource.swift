import Foundation

/// Identifies which audio source a chunk or transcript segment originated from,
/// used for channel-separation diarization
enum DiarizationSource: String, Codable, Equatable {
    case local    // Microphone — the user ("Me")
    case remote   // System audio — other participants
    case mixed    // Neither clearly dominant
    case unknown  // Pre-diarization / backward compat
}

/// Audio samples paired with their classified diarization source
struct AudioChunkWithSource {
    let samples: [Float]
    let source: DiarizationSource
}
