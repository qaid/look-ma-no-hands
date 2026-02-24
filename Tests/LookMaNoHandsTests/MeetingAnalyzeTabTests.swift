import XCTest
import SwiftUI
@testable import LookMaNoHands

@available(macOS 13.0, *)
@MainActor
final class MeetingAnalyzeTabTests: XCTestCase {
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
}
