import Foundation
import Observation

enum MeetingImportError: LocalizedError, Sendable {
    case emptyTranscript
    var errorDescription: String? { "The transcript text is empty." }
}

/// Manages persistent storage of meeting records
/// Storage: ~/Library/Application Support/LookMaNoHands/Meetings/{uuid}/
///   - metadata.json   — MeetingRecord
///   - transcript.txt  — plain text
///   - notes.md        — optional, written after LLM processing
///   - audio.{ext}     — optional imported audio copy
@available(macOS 13.0, *)
@Observable
class MeetingStore: @unchecked Sendable {

    // MARK: - State

    private(set) var meetings: [MeetingRecord] = []  // newest first
    var isRecording = false        // set by MeetingRecordTab
    var isImportingAudio = false   // set during audio import

    // MARK: - Storage Root

    private static func defaultMeetingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("LookMaNoHands")
            .appendingPathComponent("Meetings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let rootDirectory: URL

    private func meetingDirectory(for record: MeetingRecord) -> URL {
        rootDirectory.appendingPathComponent(record.id.uuidString)
    }

    // MARK: - Initialization

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? Self.defaultMeetingsDirectory()
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        loadAllMeetings()
        pruneOrphans()
        applyRetentionPolicy()
    }

    // MARK: - Public API

    /// Save a freshly recorded meeting to disk and insert into the list
    func saveRecordedMeeting(
        segments: [TranscriptSegment],
        userNotes: [UserNote] = [],
        duration: TimeInterval,
        type: MeetingType
    ) async throws -> MeetingRecord {
        let id = UUID()
        let title = "\(type.displayName) - \(Self.titleDateFormatter.string(from: Date()))"

        let hasNotes = !userNotes.isEmpty

        let record = MeetingRecord(
            id: id,
            title: title,
            duration: duration,
            meetingType: type,
            source: .recorded,
            userNotesFilename: hasNotes ? Self.userNotesFilename : nil,
            segmentCount: segments.count
        )

        let transcript = Self.buildMergedTranscript(segments: segments, userNotes: userNotes)
        try await writeRecord(record, transcript: transcript)

        // Write user-notes.json alongside transcript when notes exist
        if hasNotes {
            let dir = meetingDirectory(for: record)
            let notesData = try JSONEncoder().encode(userNotes)
            try notesData.write(to: dir.appendingPathComponent(Self.userNotesFilename), options: .atomic)
        }

        await MainActor.run {
            meetings.insert(record, at: 0)
        }
        applyRetentionPolicy()
        return record
    }

    /// Update an existing meeting record with new transcript data (used when continuing a recording)
    func updateRecordedMeeting(
        id: UUID,
        segments: [TranscriptSegment],
        userNotes: [UserNote],
        duration: TimeInterval
    ) async throws -> MeetingRecord {
        guard let existing = await MainActor.run(body: {
            meetings.first(where: { $0.id == id })
        }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var updated = existing
        updated.duration = duration
        updated.segmentCount = segments.count
        updated.userNotesFilename = userNotes.isEmpty ? nil : Self.userNotesFilename

        let transcript = Self.buildMergedTranscript(segments: segments, userNotes: userNotes)
        try await writeRecord(updated, transcript: transcript)

        let dir = meetingDirectory(for: updated)
        let notesURL = dir.appendingPathComponent(Self.userNotesFilename)
        if !userNotes.isEmpty {
            let notesData = try JSONEncoder().encode(userNotes)
            try notesData.write(to: notesURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: notesURL.path) {
            try? FileManager.default.removeItem(at: notesURL)
        }

        let finalRecord = updated
        await MainActor.run {
            // Re-lookup by ID — the index may have shifted during async writeRecord
            if let idx = meetings.firstIndex(where: { $0.id == finalRecord.id }) {
                meetings[idx] = finalRecord
            }
        }
        return finalRecord
    }

    /// Build a merged transcript that interleaves user notes at their timestamp positions
    /// and prefixes segments with speaker labels when source information is available
    static func buildMergedTranscript(segments: [TranscriptSegment], userNotes: [UserNote]) -> String {
        let hasDiarization = segments.contains { $0.source != .unknown }

        guard !userNotes.isEmpty || hasDiarization else {
            return segments.map { $0.text }.joined(separator: "\n\n")
        }

        let entries = TimelineEntry.merge(segments: segments, notes: userNotes)
        var lines: [String] = []
        for entry in entries {
            switch entry {
            case .segment(let seg, _):
                let labeledText: String
                switch seg.source {
                case .local:
                    labeledText = "[Me] \(seg.text)"
                case .remote, .mixed:
                    let duration = seg.endTime - seg.startTime
                    let withChanges = insertSpeakerChangeMarkers(
                        text: seg.text,
                        changes: seg.speakerChangeOffsets,
                        segmentDuration: duration > 0 ? duration : 1
                    )
                    labeledText = "[Mac OS] \(withChanges)"
                case .unknown:
                    labeledText = seg.text
                }
                lines.append(labeledText)
            case .note(let note):
                let mm = Int(note.timestamp) / 60
                let ss = Int(note.timestamp) % 60
                lines.append("[USER NOTE @ \(String(format: "%02d:%02d", mm, ss))] \(note.text)")
            }
        }
        return lines.joined(separator: "\n\n")
    }

    /// Insert [SPEAKER_CHANGE] markers into text at positions proportional to pause offsets
    static func insertSpeakerChangeMarkers(
        text: String,
        changes: [TimeInterval],
        segmentDuration: TimeInterval
    ) -> String {
        guard !changes.isEmpty, !text.isEmpty, segmentDuration > 0 else { return text }

        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard words.count > 1 else { return text }

        // Calculate word insertion positions from time offsets
        var insertPositions = Set<Int>()
        for offset in changes {
            let ratio = min(max(offset / segmentDuration, 0), 1)
            let wordIndex = min(max(1, Int((ratio * Double(words.count)).rounded())), words.count - 1)
            insertPositions.insert(wordIndex)
        }

        var result: [String] = []
        for (index, word) in words.enumerated() {
            if insertPositions.contains(index) {
                result.append("[SPEAKER_CHANGE]")
            }
            result.append(word)
        }

        return result.joined(separator: " ")
    }

    /// Read user notes for a meeting (nil if no inline notes were captured)
    func userNotes(for record: MeetingRecord) throws -> [UserNote]? {
        guard let filename = record.userNotesFilename else { return nil }
        let url = meetingDirectory(for: record).appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([UserNote].self, from: data)
    }

    /// Import a plain text / markdown / SRT transcript file
    func importTranscript(from url: URL, type: MeetingType) async throws -> MeetingRecord {
        var rawText = try String(contentsOf: url, encoding: .utf8)

        // Strip SRT format if needed
        if url.pathExtension.lowercased() == "srt" {
            rawText = stripSRT(rawText)
        }

        let title = "\(type.displayName) - \(Self.titleDateFormatter.string(from: Date()))"

        let record = MeetingRecord(
            id: UUID(),
            title: title,
            duration: 0,
            meetingType: type,
            source: .importedTranscript,
            segmentCount: rawText.components(separatedBy: "\n\n").filter { !$0.isEmpty }.count
        )

        try await writeRecord(record, transcript: rawText)

        await MainActor.run {
            meetings.insert(record, at: 0)
        }
        applyRetentionPolicy()
        return record
    }

    /// Import a transcript from a plain string (e.g. pasted from clipboard)
    func importTranscriptFromText(_ text: String, type: MeetingType) async throws -> MeetingRecord {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeetingImportError.emptyTranscript
        }

        let title = "\(type.displayName) - \(Self.titleDateFormatter.string(from: Date()))"

        let record = MeetingRecord(
            id: UUID(),
            title: title,
            duration: 0,
            meetingType: type,
            source: .importedTranscript,
            segmentCount: trimmed.components(separatedBy: "\n\n").filter { !$0.isEmpty }.count
        )

        try await writeRecord(record, transcript: trimmed)

        await MainActor.run {
            meetings.insert(record, at: 0)
        }
        applyRetentionPolicy()
        return record
    }

    /// Import and transcribe an audio file via WhisperService
    func importAudio(
        from url: URL,
        type: MeetingType,
        whisperService: WhisperService,
        onProgress: @Sendable @escaping (Double, String) async -> Void
    ) async throws -> MeetingRecord {
        isImportingAudio = true
        defer { isImportingAudio = false }

        let importer = AudioFileImporter()
        let segments = try await importer.transcribe(
            url: url,
            whisperService: whisperService,
            onProgress: onProgress
        )

        // Copy audio file into meeting folder after transcription
        let id = UUID()
        let ext = url.pathExtension
        let audioFilename = "audio.\(ext)"

        let title = "\(type.displayName) - \(Self.titleDateFormatter.string(from: Date()))"

        let record = MeetingRecord(
            id: id,
            title: title,
            duration: segments.last?.endTime ?? 0,
            meetingType: type,
            source: .importedAudio,
            audioFilename: audioFilename,
            segmentCount: segments.count
        )

        let transcript = segments.map { $0.text }.joined(separator: "\n\n")
        let dir = meetingDirectory(for: record)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write transcript
        try transcript.write(to: dir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        // Copy audio
        let audioDest = dir.appendingPathComponent(audioFilename)
        try? FileManager.default.copyItem(at: url, to: audioDest)

        // Write metadata last (crash-safe order)
        let metaData = try JSONEncoder().encode(record)
        try metaData.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)

        await MainActor.run {
            meetings.insert(record, at: 0)
        }
        applyRetentionPolicy()
        return record
    }

    /// Persist LLM-generated notes for a meeting and update the record's notesFilename
    func saveNotes(_ notes: String, for record: MeetingRecord) async throws {
        var updated = record
        updated.notesFilename = "notes.md"

        let dir = meetingDirectory(for: record)
        try notes.write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        // Update metadata
        let metaData = try JSONEncoder().encode(updated)
        try metaData.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)

        let snapshot = updated
        await MainActor.run {
            if let idx = meetings.firstIndex(where: { $0.id == record.id }) {
                meetings[idx] = snapshot
            }
        }
    }

    /// Auto-export notes to the user-configured folder when auto-save is enabled.
    /// Returns the destination URL on success, nil when auto-save is disabled.
    func autoExportNotes(_ notes: String, for record: MeetingRecord) async throws -> URL? {
        guard Settings.shared.autoSaveNotes else { return nil }

        let folderPath = Settings.shared.autoSaveFolder
        let folderURL = URL(fileURLWithPath: folderPath)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let dest = folderURL.appendingPathComponent(autoExportFilename(for: record))
        try notes.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    /// Returns the URL of the notes file to open — prefers the auto-exported copy,
    /// falls back to the internal notes.md in Application Support.
    func notesFileURL(for record: MeetingRecord) -> URL? {
        guard record.notesFilename != nil else { return nil }

        // Prefer auto-exported file in user's configured folder
        if Settings.shared.autoSaveNotes {
            let folderURL = URL(fileURLWithPath: Settings.shared.autoSaveFolder)
            let dest = folderURL.appendingPathComponent(autoExportFilename(for: record))
            if FileManager.default.fileExists(atPath: dest.path) {
                return dest
            }
        }

        // Fall back to internal notes.md
        let internalURL = meetingDirectory(for: record).appendingPathComponent("notes.md")
        return FileManager.default.fileExists(atPath: internalURL.path) ? internalURL : nil
    }

    /// Rename a meeting's title and persist to disk
    func renameMeeting(_ record: MeetingRecord, to newTitle: String) throws {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = record
        updated.title = trimmed
        let dir = meetingDirectory(for: record)
        let metaData = try JSONEncoder().encode(updated)
        try metaData.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)
        if let idx = meetings.firstIndex(where: { $0.id == record.id }) {
            meetings[idx] = updated
        }
    }

    /// Delete a meeting record and its folder from disk
    func delete(_ record: MeetingRecord) throws {
        let dir = meetingDirectory(for: record)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        meetings.removeAll { $0.id == record.id }
    }

    /// Read the transcript text for a meeting
    func transcriptText(for record: MeetingRecord) throws -> String {
        let url = meetingDirectory(for: record).appendingPathComponent(record.transcriptFilename)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Read the notes text for a meeting (nil if no notes generated yet)
    func notesText(for record: MeetingRecord) throws -> String? {
        guard let filename = record.notesFilename else { return nil }
        let url = meetingDirectory(for: record).appendingPathComponent(filename)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Apply retention policy — call after saves or on init
    func applyRetentionPolicy() {
        let retentionDays = Settings.shared.meetingRetentionDays
        let retentionCount = Settings.shared.meetingRetentionCount

        var toDelete: [MeetingRecord] = []

        // Count-based: keep newest N
        if retentionCount > 0 && meetings.count > retentionCount {
            let excess = meetings.dropFirst(retentionCount)
            toDelete.append(contentsOf: excess)
        }

        // Days-based: remove older than N days
        if retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
            for record in meetings {
                if record.createdAt < cutoff && !toDelete.contains(where: { $0.id == record.id }) {
                    toDelete.append(record)
                }
            }
        }

        for record in toDelete {
            try? delete(record)
        }
    }

    // MARK: - Private Helpers

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter
    }()

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Filename for user-captured inline notes stored alongside transcripts
    static let userNotesFilename = "user-notes.json"

    /// Canonical auto-export filename for a meeting's notes.
    private func autoExportFilename(for record: MeetingRecord) -> String {
        let dateStr = Self.exportDateFormatter.string(from: record.createdAt)
        return sanitizeFilename(record.title) + "-\(dateStr)-notes.md"
    }

    private func writeRecord(_ record: MeetingRecord, transcript: String) async throws {
        let dir = meetingDirectory(for: record)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write transcript first (crash-safe order)
        try transcript.write(to: dir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        // Write metadata last
        let metaData = try JSONEncoder().encode(record)
        try metaData.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func loadAllMeetings() {
        let root = rootDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }

        var loaded: [MeetingRecord] = []
        for dir in contents where dir.hasDirectoryPath {
            let metaURL = dir.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metaURL.path),
                  let data = try? Data(contentsOf: metaURL),
                  let record = try? JSONDecoder().decode(MeetingRecord.self, from: data) else {
                continue
            }
            loaded.append(record)
        }

        meetings = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    /// Remove meeting folders that have no metadata.json (partial writes / crashes)
    private func pruneOrphans() {
        let root = rootDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }

        for dir in contents where dir.hasDirectoryPath {
            let metaURL = dir.appendingPathComponent("metadata.json")
            if !FileManager.default.fileExists(atPath: metaURL.path) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    /// Minimal SRT strip: keep only text lines (skip index lines and timestamp lines)
    private func stripSRT(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip pure digit lines (sequence numbers)
            if trimmed.allSatisfy({ $0.isNumber }) { continue }
            // Skip SRT timestamp lines containing " --> "
            if trimmed.contains(" --> ") { continue }
            result.append(trimmed)
        }
        // Collapse consecutive blank lines
        var collapsed: [String] = []
        var prevWasBlank = false
        for line in result {
            let isBlank = line.isEmpty
            if isBlank && prevWasBlank { continue }
            collapsed.append(line)
            prevWasBlank = isBlank
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
