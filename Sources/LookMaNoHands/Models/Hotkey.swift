import Foundation
import CoreGraphics

/// Represents a keyboard shortcut (key + modifiers)
struct Hotkey: Codable, Equatable, Hashable {
    /// The virtual key code (CGKeyCode)
    let keyCode: UInt16

    /// Modifier flags (Cmd, Shift, Option, Control)
    let modifiers: ModifierFlags

    /// Modifier flags as a Codable struct
    struct ModifierFlags: Codable, Equatable, Hashable {
        var command: Bool = false
        var shift: Bool = false
        var option: Bool = false
        var control: Bool = false

        /// Convert to CGEventFlags for event matching
        var cgEventFlags: CGEventFlags {
            var flags: CGEventFlags = []
            if command { flags.insert(.maskCommand) }
            if shift { flags.insert(.maskShift) }
            if option { flags.insert(.maskAlternate) }
            if control { flags.insert(.maskControl) }
            return flags
        }

        /// Initialize from CGEventFlags
        init(from cgFlags: CGEventFlags) {
            command = cgFlags.contains(.maskCommand)
            shift = cgFlags.contains(.maskShift)
            option = cgFlags.contains(.maskAlternate)
            control = cgFlags.contains(.maskControl)
        }

        init(command: Bool = false, shift: Bool = false,
             option: Bool = false, control: Bool = false) {
            self.command = command
            self.shift = shift
            self.option = option
            self.control = control
        }

        /// Check if any modifiers are set
        var hasModifiers: Bool {
            command || shift || option || control
        }

        /// Display string for modifiers (e.g., "⌘⇧")
        var displayString: String {
            var parts: [String] = []
            if control { parts.append("⌃") }
            if option { parts.append("⌥") }
            if shift { parts.append("⇧") }
            if command { parts.append("⌘") }
            return parts.joined()
        }
    }

    /// Human-readable display string (e.g., "⌘⇧R")
    var displayString: String {
        let modifierStr = modifiers.displayString
        let keyStr = Hotkey.keyCodeToString(keyCode)
        if modifierStr.isEmpty {
            return keyStr
        }
        return modifierStr + keyStr
    }

    /// Display string with full modifier names (e.g., "Cmd+Shift+R")
    var verboseDisplayString: String {
        var parts: [String] = []
        if modifiers.control { parts.append("Ctrl") }
        if modifiers.option { parts.append("Opt") }
        if modifiers.shift { parts.append("Shift") }
        if modifiers.command { parts.append("Cmd") }
        parts.append(Hotkey.keyCodeToString(keyCode))
        return parts.joined(separator: "+")
    }

    /// Check if this hotkey is a single modifier key (Caps Lock, Fn, etc.)
    var isSingleModifierKey: Bool {
        !modifiers.hasModifiers && Hotkey.isModifierKeyCode(keyCode)
    }

    /// Predefined hotkeys for common trigger keys
    static let capsLock = Hotkey(keyCode: 57, modifiers: .init())
    static let rightOption = Hotkey(keyCode: 61, modifiers: .init())
    static let fn = Hotkey(keyCode: 63, modifiers: .init())

    /// Check if this is one of the predefined single-key triggers
    /// These are exempt from the 2-3 keypress validation rule
    var isPredefinedTrigger: Bool {
        self == .capsLock || self == .rightOption || self == .fn
    }

    // MARK: - Key Code Utilities

    /// Map key codes to human-readable strings
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            // Letters
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            50: "`", 51: "⌫", 53: "⎋",
            // Modifier keys
            54: "⌘R", 55: "⌘L", 56: "⇧L", 57: "⇪", 58: "⌥L", 59: "⌃L",
            60: "⇧R", 61: "⌥R", 62: "⌃R", 63: "fn",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
            // Arrow keys
            123: "←", 124: "→", 125: "↓", 126: "↑",
            // Other
            114: "Help", 115: "Home", 116: "⇞", 117: "⌦", 119: "End", 121: "⇟",
            71: "Clear", 76: "⌅", 65: ".",
            // Numpad
            67: "*", 69: "+", 75: "/", 78: "-", 81: "=",
            82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
            87: "5", 88: "6", 89: "7", 91: "8", 92: "9"
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }

    /// Check if a key code is a modifier key
    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        // Caps Lock (57), Shift L/R (56, 60), Control L/R (59, 62),
        // Option L/R (58, 61), Command L/R (55, 54), Fn (63)
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    /// System-reserved hotkeys that should not be used
    static let reservedHotkeys: Set<String> = [
        "⌘Q", "⌘W", "⌘H", "⌘M", "⌘⇥", "⌘Space",
        "⌃←", "⌃→", "⌃↑", "⌃↓",
        "⌘⌥⎋" // Force quit
    ]

    /// Check if this hotkey is reserved by the system
    var isReserved: Bool {
        Hotkey.reservedHotkeys.contains(displayString)
    }
}
