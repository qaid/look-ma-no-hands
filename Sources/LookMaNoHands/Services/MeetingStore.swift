import Foundation
import Observation

/// Manages persistent storage of meeting records
/// Storage: ~/Library/Application Support/LookMaNoHands/Meetings/{uuid}/
///   - metadata.json   — MeetingRecord
///   - transcript.txt  — plain text
///   - notes.md        — optional, written after LLM processing
///   - audio.{ext}     — optional imported audio copy
@available(macOS 13.0, *)
@Observable
class MeetingStore {

    // MARK: - State

    private(set) var meetings: [MeetingRecord] = []  // newest first
    var isRecording = false        // set by MeetingRecordTab
    var isImportingAudio = false   // set during audio import

    // MARK: - Storage Root

    private static var meetingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("LookMaNoHands")
            .appendingPathComponent("Meetings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func meetingDirectory(for record: MeetingRecord) -> URL {
        Self.meetingsDirectory.appendingPathComponent(record.id.uuidString)
    }

    // MARK: - Initialization

    init() {
        loadAllMeetings()
        pruneOrphans()
        applyRetentionPolicy()
    }

    // MARK: - Public API

    /// Save a freshly recorded meeting to disk and insert into the list
    func saveRecordedMeeting(
        segments: [TranscriptSegment],
        duration: TimeInterval,
        type: MeetingType
    ) async throws -> MeetingRecord {
        let id = UUID()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        let title = "\(type.displayName) - \(formatter.string(from: Date()))"

        let record = MeetingRecord(
            id: id,
            title: title,
            duration: duration,
            meetingType: type,
            source: .recorded,
            segmentCount: segments.count
        )

        let transcript = segments.map { $0.text }.joined(separator: "\n\n")
        try await writeRecord(record, transcript: transcript)

        await MainActor.run {
            meetings.insert(record, at: 0)
        }
        applyRetentionPolicy()
        return record
    }

    /// Import a plain text / markdown / SRT transcript file
    func importTranscript(from url: URL, type: MeetingType) async throws -> MeetingRecord {
        var rawText = try String(contentsOf: url, encoding: .utf8)

        // Strip SRT format if needed
        if url.pathExtension.lowercased() == "srt" {
            rawText = stripSRT(rawText)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        let title = "\(type.displayName) - \(formatter.string(from: Date()))"

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

    /// Import and transcribe an audio file via WhisperService
    func importAudio(
        from url: URL,
        type: MeetingType,
        whisperService: WhisperService,
        onProgress: @escaping (Double, String) async -> Void
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

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        let title = "\(type.displayName) - \(formatter.string(from: Date()))"

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
        let root = Self.meetingsDirectory
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
        let root = Self.meetingsDirectory
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
