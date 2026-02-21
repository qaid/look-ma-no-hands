import XCTest
@testable import LookMaNoHands

final class SettingsTests: XCTestCase {
    func testTriggerKeyToHotkey() {
        let custom = Hotkey(keyCode: 2, modifiers: .init(command: true))
        XCTAssertEqual(TriggerKey.capsLock.toHotkey(customHotkey: nil), .capsLock)
        XCTAssertEqual(TriggerKey.rightOption.toHotkey(customHotkey: nil), .rightOption)
        XCTAssertEqual(TriggerKey.fn.toHotkey(customHotkey: nil), .fn)
        XCTAssertEqual(TriggerKey.custom.toHotkey(customHotkey: custom), custom)
    }

    func testWhisperModelDisplayNameIsNonEmpty() {
        for model in WhisperModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty)
        }
    }

    func testResetToDefaultsRestoresExpectedValues() {
        let settings = Settings.shared
        settings.triggerKey = .custom
        settings.whisperModel = .small
        settings.showIndicator = false
        settings.pauseMediaDuringDictation = false

        settings.resetToDefaults()

        XCTAssertEqual(settings.triggerKey, .capsLock)
        XCTAssertEqual(settings.whisperModel, .base)
        XCTAssertTrue(settings.showIndicator)
        XCTAssertTrue(settings.pauseMediaDuringDictation)
    }
}
