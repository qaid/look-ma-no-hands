import XCTest
import CoreGraphics
@testable import LookMaNoHands

final class HotkeyTests: XCTestCase {
    func testModifierFlagsDisplayStringAndFlags() {
        let modifiers = Hotkey.ModifierFlags(command: true, shift: true, option: false, control: true)
        XCTAssertEqual(modifiers.displayString, "⌃⇧⌘")
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskCommand))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskShift))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskControl))
        XCTAssertFalse(modifiers.cgEventFlags.contains(.maskAlternate))
    }

    func testDisplayStrings() {
        let hotkey = Hotkey(keyCode: 2, modifiers: .init(command: true, shift: true))
        XCTAssertEqual(hotkey.displayString, "⇧⌘D")
        XCTAssertEqual(hotkey.verboseDisplayString, "Shift+Cmd+D")
    }

    func testSingleModifierKeysAndReserved() {
        XCTAssertTrue(Hotkey.capsLock.isSingleModifierKey)
        XCTAssertTrue(Hotkey.fn.isSingleModifierKey)
        XCTAssertTrue(Hotkey.rightOption.isSingleModifierKey)

        let reserved = Hotkey(keyCode: 12, modifiers: .init(command: true)) // ⌘Q
        XCTAssertTrue(reserved.isReserved)

        let nonReserved = Hotkey(keyCode: 12, modifiers: .init(command: true, shift: true)) // ⌘⇧Q
        XCTAssertFalse(nonReserved.isReserved)
    }

    func testIsPredefinedTrigger() {
        XCTAssertTrue(Hotkey.capsLock.isPredefinedTrigger)
        XCTAssertTrue(Hotkey.rightOption.isPredefinedTrigger)
        XCTAssertTrue(Hotkey.fn.isPredefinedTrigger)

        let custom = Hotkey(keyCode: 2, modifiers: .init(command: true))
        XCTAssertFalse(custom.isPredefinedTrigger)
    }
}
