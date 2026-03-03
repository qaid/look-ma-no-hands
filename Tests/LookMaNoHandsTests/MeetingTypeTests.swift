import XCTest
@testable import LookMaNoHands

final class MeetingTypeTests: XCTestCase {
    func testDisplayNamesAndIcons() {
        XCTAssertEqual(MeetingType.standup.displayName, "Standup")
        XCTAssertEqual(MeetingType.oneOnOne.displayName, "1:1")
        XCTAssertEqual(MeetingType.allHands.displayName, "All-Hands")
        XCTAssertEqual(MeetingType.customerCall.displayName, "Customer Call")
        XCTAssertEqual(MeetingType.videoEssay.displayName, "Video Essay")
        XCTAssertEqual(MeetingType.general.displayName, "General")
        XCTAssertEqual(MeetingType.custom.displayName, "Custom")

        XCTAssertEqual(MeetingType.standup.icon, "figure.stand")
        XCTAssertEqual(MeetingType.oneOnOne.icon, "person.2")
        XCTAssertEqual(MeetingType.allHands.icon, "person.3")
        XCTAssertEqual(MeetingType.customerCall.icon, "phone")
        XCTAssertEqual(MeetingType.videoEssay.icon, "play.rectangle")
        XCTAssertEqual(MeetingType.general.icon, "doc.text")
        XCTAssertEqual(MeetingType.custom.icon, "slider.horizontal.3")
    }

    func testVideoEssayPromptSections() {
        let prompt = MeetingType.videoEssay.defaultPrompt
        // Verify all required output sections exist
        XCTAssertTrue(prompt.contains("Thesis / Central Argument"), "Missing Thesis section")
        XCTAssertTrue(prompt.contains("Argument Breakdown"), "Missing Argument Breakdown section")
        XCTAssertTrue(prompt.contains("Key Concepts & Definitions"), "Missing Key Concepts section")
        XCTAssertTrue(prompt.contains("Referenced Works & Sources"), "Missing Referenced Works section")
        XCTAssertTrue(prompt.contains("Counterarguments & Nuances"), "Missing Counterarguments section")
        XCTAssertTrue(prompt.contains("Notable Quotes"), "Missing Notable Quotes section")
        XCTAssertTrue(prompt.contains("Conclusions & Takeaways"), "Missing Conclusions section")
        // Verify quality guards
        XCTAssertTrue(prompt.contains("Never Invent"), "Missing 'Never Invent' quality guard")
        XCTAssertTrue(prompt.contains("[Unclear]"), "Missing [Unclear] marker instruction")
        XCTAssertTrue(prompt.contains("Complete All Sections"), "Missing 'Complete All Sections' quality guard")
    }

    func testDefaultPromptBehavior() {
        XCTAssertTrue(MeetingType.standup.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.oneOnOne.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.allHands.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.customerCall.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertTrue(MeetingType.videoEssay.defaultPrompt.contains("[TRANSCRIPTION_PLACEHOLDER]"))

        XCTAssertEqual(MeetingType.general.defaultPrompt, Settings.defaultMeetingPrompt)
        XCTAssertEqual(MeetingType.custom.defaultPrompt, "")
    }
}
