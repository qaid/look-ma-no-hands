import XCTest
@testable import LookMaNoHands

@available(macOS 13.0, *)
final class MeetingStoreTests: XCTestCase {

    private func makeTempRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LookMaNoHandsTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeRecord(_ record: MeetingRecord, transcript: String, to root: URL) throws {
        let dir = root.appendingPathComponent(record.id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try transcript.write(to: dir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        let data = try JSONEncoder().encode(record)
        try data.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)
    }

    func testLoadAllMeetingsSortsNewestFirstAndReadsTranscript() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let older = MeetingRecord(
            id: UUID(),
            title: "Older",
            createdAt: Date().addingTimeInterval(-3600),
            duration: 60,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )
        let newer = MeetingRecord(
            id: UUID(),
            title: "Newer",
            createdAt: Date(),
            duration: 120,
            meetingType: .standup,
            source: .recorded,
            segmentCount: 2
        )

        try writeRecord(older, transcript: "older transcript", to: root)
        try writeRecord(newer, transcript: "newer transcript", to: root)

        let store = MeetingStore(rootDirectory: root)
        XCTAssertEqual(store.meetings.count, 2)
        XCTAssertEqual(store.meetings.first?.id, newer.id)
        XCTAssertEqual(try store.transcriptText(for: newer), "newer transcript")
    }

    func testRetentionPolicyRemovesOldAndExcessMeetings() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldMeeting = MeetingRecord(
            id: UUID(),
            title: "Old",
            createdAt: Date().addingTimeInterval(-5 * 86400),
            duration: 10,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )
        let midMeeting = MeetingRecord(
            id: UUID(),
            title: "Mid",
            createdAt: Date().addingTimeInterval(-2 * 86400),
            duration: 10,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )
        let newMeeting = MeetingRecord(
            id: UUID(),
            title: "New",
            createdAt: Date(),
            duration: 10,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )

        try writeRecord(oldMeeting, transcript: "old", to: root)
        try writeRecord(midMeeting, transcript: "mid", to: root)
        try writeRecord(newMeeting, transcript: "new", to: root)

        let settings = Settings.shared
        let originalDays = settings.meetingRetentionDays
        let originalCount = settings.meetingRetentionCount
        defer {
            settings.meetingRetentionDays = originalDays
            settings.meetingRetentionCount = originalCount
        }

        settings.meetingRetentionDays = 3
        settings.meetingRetentionCount = 2

        let store = MeetingStore(rootDirectory: root)
        XCTAssertEqual(store.meetings.count, 2)
        XCTAssertFalse(store.meetings.contains { $0.id == oldMeeting.id })
        XCTAssertTrue(store.meetings.contains { $0.id == midMeeting.id })
        XCTAssertTrue(store.meetings.contains { $0.id == newMeeting.id })
    }

    func testLoadAllMeetingsSkipsInvalidMetadata() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let valid = MeetingRecord(
            id: UUID(),
            title: "Valid",
            createdAt: Date(),
            duration: 10,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )

        // Valid record
        try writeRecord(valid, transcript: "ok", to: root)

        // Invalid metadata directory
        let invalidDir = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        try "not json".write(to: invalidDir.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)

        let store = MeetingStore(rootDirectory: root)
        XCTAssertEqual(store.meetings.count, 1)
        XCTAssertEqual(store.meetings.first?.id, valid.id)
    }

    func testPruneOrphansRemovesDirectoryWithoutMetadata() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let orphanDir = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try "orphan transcript".write(to: orphanDir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        _ = MeetingStore(rootDirectory: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDir.path))
    }

    func testTranscriptTextThrowsWhenMissing() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = MeetingRecord(
            id: UUID(),
            title: "No Transcript",
            createdAt: Date(),
            duration: 10,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )

        let dir = root.appendingPathComponent(record.id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)

        let store = MeetingStore(rootDirectory: root)
        XCTAssertThrowsError(try store.transcriptText(for: record))
    }

    func testNotesTextReturnsNilWhenMissing() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = MeetingRecord(
            id: UUID(),
            title: "No Notes",
            createdAt: Date(),
            duration: 10,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )

        try writeRecord(record, transcript: "ok", to: root)
        let store = MeetingStore(rootDirectory: root)
        XCTAssertNil(try store.notesText(for: record))
    }

    func testSaveRecordedMeetingWithUserNotes() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MeetingStore(rootDirectory: root)
        let segments = [
            TranscriptSegment(text: "Hello team", startTime: 10, endTime: 15, timestamp: Date()),
            TranscriptSegment(text: "Let's begin", startTime: 30, endTime: 35, timestamp: Date())
        ]
        let notes = [
            UserNote(text: "Ask about deadline", timestamp: 20)
        ]

        let record = try await store.saveRecordedMeeting(
            segments: segments,
            userNotes: notes,
            duration: 60,
            type: .general
        )

        // Verify transcript contains note markers
        let transcript = try store.transcriptText(for: record)
        XCTAssertTrue(transcript.contains("[USER NOTE @ 00:20] Ask about deadline"))
        XCTAssertTrue(transcript.contains("Hello team"))
        XCTAssertTrue(transcript.contains("Let's begin"))

        // Verify user-notes.json exists and is valid
        XCTAssertEqual(record.userNotesFilename, "user-notes.json")
        let loadedNotes = try store.userNotes(for: record)
        XCTAssertNotNil(loadedNotes)
        XCTAssertEqual(loadedNotes?.count, 1)
        XCTAssertEqual(loadedNotes?.first?.text, "Ask about deadline")
    }

    func testImportTranscriptFromText() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MeetingStore(rootDirectory: root)
        let record = try await store.importTranscriptFromText("Sample transcript text", type: .general)

        XCTAssertEqual(store.meetings.count, 1)
        XCTAssertEqual(store.meetings.first?.id, record.id)
        XCTAssertEqual(record.source, .importedTranscript)
        XCTAssertEqual(try store.transcriptText(for: record), "Sample transcript text")
    }

    func testImportTranscriptFromTextThrowsOnEmpty() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MeetingStore(rootDirectory: root)
        do {
            _ = try await store.importTranscriptFromText("   \n  ", type: .general)
            XCTFail("Expected throw for empty text")
        } catch MeetingImportError.emptyTranscript {
            // expected
        }
        XCTAssertTrue(store.meetings.isEmpty)
    }

    // MARK: - Auto-Export Tests

    func testAutoExportNotesWritesFileWhenEnabled() async throws {
        let root = try makeTempRoot()
        let exportDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LookMaNoHandsTests")
            .appendingPathComponent("export-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportDir)
        }

        let record = MeetingRecord(
            id: UUID(),
            title: "Test Meeting",
            createdAt: Date(),
            duration: 60,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )
        try writeRecord(record, transcript: "test", to: root)

        let settings = Settings.shared
        let originalAutoSave = settings.autoSaveNotes
        let originalFolder = settings.autoSaveFolder
        defer {
            settings.autoSaveNotes = originalAutoSave
            settings.autoSaveFolder = originalFolder
        }

        settings.autoSaveNotes = true
        settings.autoSaveFolder = exportDir.path

        let store = MeetingStore(rootDirectory: root)
        let result = try await store.autoExportNotes("# Meeting Notes", for: record)

        XCTAssertNotNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result!.path))
        let content = try String(contentsOf: result!, encoding: .utf8)
        XCTAssertEqual(content, "# Meeting Notes")

        // Filename should include date component for uniqueness
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expectedDate = formatter.string(from: record.createdAt)
        XCTAssertTrue(result!.lastPathComponent.contains(expectedDate))
        XCTAssertTrue(result!.lastPathComponent.hasSuffix("-notes.md"))
    }

    func testAutoExportNotesReturnsNilWhenDisabled() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = MeetingRecord(
            id: UUID(),
            title: "Test Meeting",
            createdAt: Date(),
            duration: 60,
            meetingType: .general,
            source: .recorded,
            segmentCount: 1
        )
        try writeRecord(record, transcript: "test", to: root)

        let settings = Settings.shared
        let originalAutoSave = settings.autoSaveNotes
        defer { settings.autoSaveNotes = originalAutoSave }

        settings.autoSaveNotes = false

        let store = MeetingStore(rootDirectory: root)
        let result = try await store.autoExportNotes("# Meeting Notes", for: record)

        XCTAssertNil(result)
    }

    func testSaveRecordedMeetingWithoutNotes() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MeetingStore(rootDirectory: root)
        let segments = [
            TranscriptSegment(text: "Hello team", startTime: 0, endTime: 5, timestamp: Date())
        ]

        let record = try await store.saveRecordedMeeting(
            segments: segments,
            duration: 30,
            type: .general
        )

        // Verify no user notes file
        XCTAssertNil(record.userNotesFilename)
        XCTAssertNil(try store.userNotes(for: record))

        // Verify transcript is plain (no note markers)
        let transcript = try store.transcriptText(for: record)
        XCTAssertFalse(transcript.contains("[USER NOTE"))
        XCTAssertEqual(transcript, "Hello team")
    }
}
