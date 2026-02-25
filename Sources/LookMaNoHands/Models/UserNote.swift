import Foundation

/// A user-authored note captured during live meeting recording
struct UserNote: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    /// Seconds from session start (matches TranscriptSegment.startTime scale)
    let timestamp: TimeInterval
    let createdAt: Date

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}
