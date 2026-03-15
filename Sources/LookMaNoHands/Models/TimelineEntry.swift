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

    /// The grouping key for consecutive-speaker grouping
    var groupKey: TimelineGroupKey {
        switch self {
        case .segment(let seg, _):
            return .speaker(seg.source)
        case .note:
            return .note
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

    /// Group consecutive same-source entries into speaker blocks
    static func grouped(_ entries: [TimelineEntry]) -> [TimelineGroup] {
        guard !entries.isEmpty else { return [] }

        var groups: [TimelineGroup] = []
        var currentEntries: [TimelineEntry] = [entries[0]]
        var currentKey = entries[0].groupKey

        for entry in entries.dropFirst() {
            let key = entry.groupKey
            if key == currentKey {
                currentEntries.append(entry)
            } else {
                groups.append(TimelineGroup(key: currentKey, entries: currentEntries))
                currentEntries = [entry]
                currentKey = key
            }
        }
        groups.append(TimelineGroup(key: currentKey, entries: currentEntries))
        return groups
    }
}

/// Key used to decide whether consecutive timeline entries belong to the same group
enum TimelineGroupKey: Equatable {
    case speaker(DiarizationSource)
    case note
}

/// A run of consecutive timeline entries from the same source
struct TimelineGroup: Identifiable {
    let id = UUID()
    let key: TimelineGroupKey
    let entries: [TimelineEntry]

    var startTimestamp: TimeInterval {
        entries.first?.timestamp ?? 0
    }

    var endTimestamp: TimeInterval {
        entries.last?.timestamp ?? startTimestamp
    }
}
