import XCTest
import SwiftUI
@testable import LookMaNoHands

@available(macOS 13.0, *)
@MainActor
final class MeetingAnalyzeTabTests: XCTestCase {
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

    private func makeStore() -> MeetingStore {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return MeetingStore(rootDirectory: tempDir)
    }

    private func makeMeeting() -> MeetingRecord {
        MeetingRecord(
            title: "Standup - Test",
            duration: 120,
            meetingType: .standup,
            source: .recorded,
            segmentCount: 1
        )
    }

    func testModelPickerRendersTextFieldWhenNoModels() {
        let store = makeStore()
        var selected: MeetingRecord? = makeMeeting()
        let binding = Binding<MeetingRecord?>(
            get: { selected },
            set: { selected = $0 }
        )

        let view = MeetingAnalyzeTab(
            store: store,
            selectedMeeting: binding,
            initialSelectedModel: "model-a",
            initialAvailableModels: []
        )

        _ = view.body
    }

    func testModelPickerRendersPickerWhenModelsAvailable() {
        let store = makeStore()
        var selected: MeetingRecord? = makeMeeting()
        let binding = Binding<MeetingRecord?>(
            get: { selected },
            set: { selected = $0 }
        )

        let view = MeetingAnalyzeTab(
            store: store,
            selectedMeeting: binding,
            initialSelectedModel: "model-a",
            initialAvailableModels: ["model-a", "model-b"]
        )

        _ = view.body
    }

    func testResolveModelSelectionUsesFirstWhenDefaultMissing() {
        let resolved = MeetingAnalyzeTab.resolveModelSelection(
            models: ["model-a"],
            defaultModel: "missing-model"
        )

        XCTAssertEqual(resolved.available, ["model-a"])
        XCTAssertEqual(resolved.selected, "model-a")
    }

    func testResolveRenamedMeetingReturnsUpdatedSelection() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let meeting = makeMeeting()
        try writeRecord(meeting, transcript: "test transcript", to: root)
        let store = MeetingStore(rootDirectory: root)

        let updated = MeetingAnalyzeTab.resolveRenamedMeeting(
            store: store,
            meeting: meeting,
            newTitle: "Renamed Title"
        )

        XCTAssertEqual(updated?.id, meeting.id)
        XCTAssertEqual(updated?.title, "Renamed Title")
        XCTAssertEqual(store.meetings.first?.title, "Renamed Title")
    }
}
