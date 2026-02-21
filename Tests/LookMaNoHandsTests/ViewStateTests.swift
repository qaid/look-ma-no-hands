import XCTest
@testable import LookMaNoHands

final class ViewStateTests: XCTestCase {
    func testLaunchSplashPausedAccessibilityStrings() {
        let status = LaunchSplashView.statusAccessibility(hotkeyEnabled: false)
        let hint = LaunchSplashView.hintAccessibility(
            hotkeyEnabled: false,
            hotkeyDisplay: "Caps Lock"
        )

        XCTAssertEqual(status, "Hotkey paused")
        XCTAssertEqual(hint, "Dictation hotkey is paused. Use Command Shift D to re-enable")
    }

    func testLaunchSplashReadyAccessibilityStrings() {
        let status = LaunchSplashView.statusAccessibility(hotkeyEnabled: true)
        let hint = LaunchSplashView.hintAccessibility(
            hotkeyEnabled: true,
            hotkeyDisplay: "Caps Lock"
        )

        XCTAssertEqual(status, "App ready")
        XCTAssertEqual(hint, "Press Caps Lock to start recording")
    }

    func testOllamaPickerIncludesCurrentModelWhenMissing() {
        let models = SettingsView.ollamaPickerModels(
            currentModel: "custom:model",
            availableModels: ["qwen2.5:3b", "llama3"]
        )

        XCTAssertEqual(models.first, "custom:model")
        XCTAssertTrue(models.contains("qwen2.5:3b"))
        XCTAssertTrue(models.contains("llama3"))
    }

    func testOllamaPickerDoesNotDuplicateCurrentModel() {
        let models = SettingsView.ollamaPickerModels(
            currentModel: "qwen2.5:3b",
            availableModels: ["qwen2.5:3b", "llama3"]
        )

        XCTAssertEqual(models, ["qwen2.5:3b", "llama3"])
    }
}
