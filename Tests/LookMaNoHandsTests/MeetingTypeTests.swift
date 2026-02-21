import XCTest
@testable import LookMaNoHands

final class MeetingTypeTests: XCTestCase {
    func testDisplayNamesAndIcons() {
        XCTAssertEqual(MeetingType.standup.displayName, "Standup")
        XCTAssertEqual(MeetingType.oneOnOne.displayName, "1:1")
        XCTAssertEqual(MeetingType.allHands.displayName, "All-Hands")
        XCTAssertEqual(MeetingType.customerCall.displayName, "Customer Call")
        XCTAssertEqual(MeetingType.general.displayName, "General")
        XCTAssertEqual(MeetingType.custom.displayName, "Custom")

        XCTAssertEqual(MeetingType.standup.icon, "figure.stand")
        XCTAssertEqual(MeetingType.oneOnOne.icon, "person.2")
        XCTAssertEqual(MeetingType.allHands.icon, "person.3")
        XCTAssertEqual(MeetingType.customerCall.icon, "phone")
        XCTAssertEqual(MeetingType.general.icon, "doc.text")
        XCTAssertEqual(MeetingType.custom.icon, "slider.horizontal.3")
    }

    func testDefaultPromptBehavior() {
        XCTAssertTrue(MeetingType.standup.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.oneOnOne.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.allHands.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.customerCall.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))

        XCTAssertEqual(MeetingType.general.defaultPrompt, Settings.defaultMeetingPrompt)
        XCTAssertEqual(MeetingType.custom.defaultPrompt, "")
    }
}
