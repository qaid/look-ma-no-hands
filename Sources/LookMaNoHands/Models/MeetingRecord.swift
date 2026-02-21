import Foundation

/// How a meeting record was created
enum MeetingSource: String, Codable {
    case recorded = "recorded"
    case importedTranscript = "importedTranscript"
    case importedAudio = "importedAudio"
}

/// Persisted meeting metadata
/// All filename fields are relative to the meeting's folder in Application Support
struct MeetingRecord: Identifiable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var meetingType: MeetingType
    var source: MeetingSource
    var transcriptFilename: String    // always "transcript.txt"
    var notesFilename: String?        // "notes.md" — nil until LLM run
    var audioFilename: String?        // for imported audio copy
    var segmentCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        meetingType: MeetingType,
        source: MeetingSource,
        transcriptFilename: String = "transcript.txt",
        notesFilename: String? = nil,
        audioFilename: String? = nil,
        segmentCount: Int
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.meetingType = meetingType
        self.source = source
        self.transcriptFilename = transcriptFilename
        self.notesFilename = notesFilename
        self.audioFilename = audioFilename
        self.segmentCount = segmentCount
    }
}
