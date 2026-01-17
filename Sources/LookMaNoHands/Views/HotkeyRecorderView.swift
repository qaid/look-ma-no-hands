import SwiftUI
import AppKit

/// State for the hotkey recording process
enum HotkeyRecordingState: Equatable {
    case idle
    case recording
    case invalid(String)
}

/// Raycast-style hotkey recorder view
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey?
    @State private var recordingState: HotkeyRecordingState = .idle
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            // Hotkey display box
            Button(action: toggleRecording) {
                HStack(spacing: 4) {
                    if case .recording = recordingState {
                        Text("Press hotkey...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    } else if case .invalid(let message) = recordingState {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                    } else if let hk = hotkey {
                        HotkeyDisplay(hotkey: hk)
                    } else {
                        Text("Click to record")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 120)
                .background(recordingBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recordingBorderColor, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            // Clear button
            if hotkey != nil && recordingState == .idle {
                Button(action: clearHotkey) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Clear hotkey")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var recordingBackground: Color {
        switch recordingState {
        case .recording:
            return Color.accentColor.opacity(0.1)
        case .invalid:
            return Color.red.opacity(0.1)
        case .idle:
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private var recordingBorderColor: Color {
        switch recordingState {
        case .recording:
            return .accentColor
        case .invalid:
            return .red
        case .idle:
            return Color(NSColor.separatorColor)
        }
    }

    private func toggleRecording() {
        if case .recording = recordingState {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard recordingState == .idle else { return }
        recordingState = .recording

        // Install local event monitor for key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            self.handleKeyEvent(event)
            return nil // Consume the event
        }

        // Also monitor for clicks outside to cancel
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            self.cancelRecording()
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if case .recording = recordingState {
            recordingState = .idle
        }
    }

    private func cancelRecording() {
        stopRecording()
        recordingState = .idle
    }

    private func clearHotkey() {
        hotkey = nil
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Handle Escape to cancel
        if event.keyCode == 53 { // Escape
            cancelRecording()
            return
        }

        let keyCode = UInt16(event.keyCode)

        // Ignore flagsChanged events (modifier key presses alone)
        // We only capture when a regular key is pressed with modifiers
        if event.type == .flagsChanged {
            return
        }

        // Regular key pressed - build the hotkey with modifiers
        let modifiers = Hotkey.ModifierFlags(
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )

        let newHotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)

        // Validate the hotkey
        if let error = validateHotkey(newHotkey) {
            showError(error)
            return
        }

        acceptHotkey(newHotkey)
    }

    private func validateHotkey(_ hotkey: Hotkey) -> String? {
        // Check for reserved system hotkeys
        if hotkey.isReserved {
            return "Reserved by system"
        }

        // Predefined triggers (Caps Lock, Fn, Right Option) are always valid
        // These are special system keys that work with single keypress
        if hotkey.isPredefinedTrigger {
            return nil
        }

        // For custom hotkeys: enforce 2-3 keypress rule
        // Count keypresses: each modifier + the main key
        let modifierCount = [
            hotkey.modifiers.command,
            hotkey.modifiers.shift,
            hotkey.modifiers.option,
            hotkey.modifiers.control
        ].filter { $0 }.count

        // Single modifier keys = 1 keypress (too few for custom hotkeys)
        if hotkey.isSingleModifierKey {
            return "Use preset or add key"
        }

        // Regular keys without modifiers = 1 keypress (too few)
        if modifierCount == 0 {
            return "Add a modifier key"
        }

        // More than 2 modifiers + 1 key = 4+ keypresses (too many)
        if modifierCount > 2 {
            return "Max 2 modifier keys"
        }

        return nil
    }

    private func showError(_ message: String) {
        recordingState = .invalid(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if case .invalid = self.recordingState {
                self.recordingState = .recording
            }
        }
    }

    private func acceptHotkey(_ newHotkey: Hotkey) {
        hotkey = newHotkey
        stopRecording()
        recordingState = .idle
    }
}

/// Display a hotkey with styled key caps
struct HotkeyDisplay: View {
    let hotkey: Hotkey

    var body: some View {
        HStack(spacing: 2) {
            // Modifiers first
            if hotkey.modifiers.control {
                KeyCapView(text: "⌃")
            }
            if hotkey.modifiers.option {
                KeyCapView(text: "⌥")
            }
            if hotkey.modifiers.shift {
                KeyCapView(text: "⇧")
            }
            if hotkey.modifiers.command {
                KeyCapView(text: "⌘")
            }
            // Then the key
            KeyCapView(text: Hotkey.keyCodeToString(hotkey.keyCode))
        }
    }
}

/// Styled key cap appearance
struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 0.5, x: 0, y: 0.5)
    }
}

// Preview removed for SPM compatibility - use Xcode previews if needed
