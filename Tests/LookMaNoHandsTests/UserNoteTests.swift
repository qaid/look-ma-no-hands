import XCTest
@testable import LookMaNoHands

final class UserNoteTests: XCTestCase {

    // MARK: - UserNote Codable

    func testUserNoteEncodeDecodeRoundtrip() throws {
        let note = UserNote(
            id: UUID(),
            text: "Ask Sarah about the revised timeline",
            timestamp: 585.0,
            createdAt: Date()
        )

        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(UserNote.self, from: data)

        XCTAssertEqual(note, decoded)
    }

    // MARK: - TimelineEntry.merge

    func testMergeInterleavesCorrectly() {
        let seg1 = TranscriptSegment(text: "First segment", startTime: 10, endTime: 15, timestamp: Date())
        let seg2 = TranscriptSegment(text: "Second segment", startTime: 30, endTime: 35, timestamp: Date())
        let note1 = UserNote(text: "My note", timestamp: 20)
        let note2 = UserNote(text: "Later note", timestamp: 25)

        let entries = TimelineEntry.merge(segments: [seg1, seg2], notes: [note1, note2])

        XCTAssertEqual(entries.count, 4)

        // Verify order: seg1(10), note1(20), note2(25), seg2(30)
        XCTAssertEqual(entries[0].timestamp, 10, accuracy: 0.01)
        XCTAssertEqual(entries[1].timestamp, 20, accuracy: 0.01)
        XCTAssertEqual(entries[2].timestamp, 25, accuracy: 0.01)
        XCTAssertEqual(entries[3].timestamp, 30, accuracy: 0.01)

        // Verify types
        if case .segment(let seg, let idx) = entries[0] {
            XCTAssertEqual(seg.text, "First segment")
            XCTAssertEqual(idx, 0)
        } else { XCTFail("Expected segment") }

        if case .note(let n) = entries[1] {
            XCTAssertEqual(n.text, "My note")
        } else { XCTFail("Expected note") }
    }

    func testMergeWithEmptyNotes() {
        let seg = TranscriptSegment(text: "Only segment", startTime: 5, endTime: 10, timestamp: Date())

        let entries = TimelineEntry.merge(segments: [seg], notes: [])
        XCTAssertEqual(entries.count, 1)
        if case .segment(let s, _) = entries[0] {
            XCTAssertEqual(s.text, "Only segment")
        } else { XCTFail("Expected segment") }
    }

    func testMergeWithEmptySegments() {
        let note = UserNote(text: "Standalone note", timestamp: 100)

        let entries = TimelineEntry.merge(segments: [], notes: [note])
        XCTAssertEqual(entries.count, 1)
        if case .note(let n) = entries[0] {
            XCTAssertEqual(n.text, "Standalone note")
        } else { XCTFail("Expected note") }
    }

    func testMergeWithBothEmpty() {
        let entries = TimelineEntry.merge(segments: [], notes: [])
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - buildMergedTranscript

    @available(macOS 13.0, *)
    func testBuildMergedTranscriptWithNotes() {
        let segments = [
            TranscriptSegment(text: "Hello everyone", startTime: 10, endTime: 15, timestamp: Date()),
            TranscriptSegment(text: "Let's discuss the timeline", startTime: 30, endTime: 40, timestamp: Date())
        ]
        let notes = [
            UserNote(text: "Ask about deadline", timestamp: 20)
        ]

        let result = MeetingStore.buildMergedTranscript(segments: segments, userNotes: notes)

        XCTAssertTrue(result.contains("Hello everyone"))
        XCTAssertTrue(result.contains("[USER NOTE @ 00:20] Ask about deadline"))
        XCTAssertTrue(result.contains("Let's discuss the timeline"))

        // Verify order: segment text, then note, then second segment
        let helloRange = result.range(of: "Hello everyone")!
        let noteRange = result.range(of: "[USER NOTE @ 00:20]")!
        let timelineRange = result.range(of: "Let's discuss the timeline")!
        XCTAssertTrue(helloRange.lowerBound < noteRange.lowerBound)
        XCTAssertTrue(noteRange.lowerBound < timelineRange.lowerBound)
    }

    @available(macOS 13.0, *)
    func testBuildMergedTranscriptWithoutNotes() {
        let segments = [
            TranscriptSegment(text: "First", startTime: 0, endTime: 5, timestamp: Date()),
            TranscriptSegment(text: "Second", startTime: 10, endTime: 15, timestamp: Date())
        ]

        let result = MeetingStore.buildMergedTranscript(segments: segments, userNotes: [])

        XCTAssertEqual(result, "First\n\nSecond")
        XCTAssertFalse(result.contains("[USER NOTE"))
    }
}
