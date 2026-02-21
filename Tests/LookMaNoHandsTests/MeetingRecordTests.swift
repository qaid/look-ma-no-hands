import XCTest
@testable import LookMaNoHands

final class MeetingRecordTests: XCTestCase {
    func testMeetingRecordEncodesAndDecodes() throws {
        let record = MeetingRecord(
            id: UUID(),
            title: "Weekly Sync",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 123,
            meetingType: .standup,
            source: .importedTranscript,
            transcriptFilename: "transcript.txt",
            notesFilename: "notes.md",
            audioFilename: "audio.m4a",
            segmentCount: 4
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MeetingRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.title, record.title)
        XCTAssertEqual(decoded.createdAt, record.createdAt)
        XCTAssertEqual(decoded.duration, record.duration)
        XCTAssertEqual(decoded.meetingType, record.meetingType)
        XCTAssertEqual(decoded.source, record.source)
        XCTAssertEqual(decoded.transcriptFilename, record.transcriptFilename)
        XCTAssertEqual(decoded.notesFilename, record.notesFilename)
        XCTAssertEqual(decoded.audioFilename, record.audioFilename)
        XCTAssertEqual(decoded.segmentCount, record.segmentCount)
    }

    func testMeetingRecordDefaults() {
        let record = MeetingRecord(
            title: "Default",
            duration: 0,
            meetingType: .general,
            source: .recorded,
            segmentCount: 0
        )

        XCTAssertEqual(record.transcriptFilename, "transcript.txt")
        XCTAssertNil(record.notesFilename)
        XCTAssertNil(record.audioFilename)
    }
}
