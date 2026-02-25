import Foundation

/// Display-only union of transcript segments and user notes, sorted by time
enum TimelineEntry: Identifiable {
    case segment(TranscriptSegment, index: Int)
    case note(UserNote)

    var id: String {
        switch self {
        case .segment(_, let index): return "seg-\(index)"
        case .note(let note): return "note-\(note.id.uuidString)"
        }
    }

    var timestamp: TimeInterval {
        switch self {
        case .segment(let seg, _): return seg.startTime
        case .note(let note): return note.timestamp
        }
    }

    /// Merge transcript segments and user notes into a time-sorted timeline
    static func merge(segments: [TranscriptSegment], notes: [UserNote]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        entries.reserveCapacity(segments.count + notes.count)

        for (index, segment) in segments.enumerated() {
            entries.append(.segment(segment, index: index))
        }
        for note in notes {
            entries.append(.note(note))
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }
}
