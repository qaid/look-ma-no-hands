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
}
