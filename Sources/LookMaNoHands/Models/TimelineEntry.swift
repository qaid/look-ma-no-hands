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
        var entries: [(TimelineEntry, Int)] = []
        entries.reserveCapacity(segments.count + notes.count)

        var order = 0
        for (index, segment) in segments.enumerated() {
            entries.append((.segment(segment, index: index), order))
            order += 1
        }
        for note in notes {
            entries.append((.note(note), order))
            order += 1
        }

        return entries
            .sorted {
                if $0.0.timestamp == $1.0.timestamp {
                    return $0.1 < $1.1
                }
                return $0.0.timestamp < $1.0.timestamp
            }
            .map { $0.0 }
    }
}
