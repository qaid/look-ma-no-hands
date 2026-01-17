import Foundation
import CoreGraphics
import AppKit

/// Monitors keyboard events system-wide to detect the configured trigger hotkey
/// Requires Accessibility permissions to function
class KeyboardMonitor {

    // MARK: - Types

    /// Callback type for when trigger key is pressed
    typealias TriggerCallback = () -> Void

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onTrigger: TriggerCallback?

    /// The hotkey configuration to listen for
    private var hotkey: Hotkey = .capsLock

    /// Lock for thread-safe hotkey access
    private let hotkeyLock = NSLock()

    /// Whether the monitor is currently active
    private(set) var isMonitoring = false

    /// Track modifier key state to avoid double-triggering
    private var lastModifierFlags: CGEventFlags = []

    // MARK: - Public Methods

    /// Update the hotkey configuration (can be called while monitoring)
    func setHotkey(_ newHotkey: Hotkey) {
        hotkeyLock.lock()
        defer { hotkeyLock.unlock() }
        hotkey = newHotkey
        lastModifierFlags = [] // Reset state when hotkey changes
        NSLog("⌨️ KeyboardMonitor: Hotkey updated to %@", newHotkey.displayString)
    }

    /// Get the current hotkey
    func getHotkey() -> Hotkey {
        hotkeyLock.lock()
        defer { hotkeyLock.unlock() }
        return hotkey
    }

    /// Start monitoring for the trigger key
    /// - Parameters:
    ///   - hotkey: The hotkey to monitor for (defaults to Caps Lock)
    ///   - callback: Called when the trigger key is pressed
    /// - Returns: True if monitoring started successfully
    @discardableResult
    func startMonitoring(hotkey: Hotkey = .capsLock, onTrigger callback: @escaping TriggerCallback) -> Bool {
        guard !isMonitoring else { return true }

        // Check accessibility permission and prompt if needed
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)

        guard trusted else {
            print("KeyboardMonitor: Accessibility permission not granted - prompt shown")
            return false
        }

        self.hotkey = hotkey
        self.onTrigger = callback

        // Determine which events to monitor
        // For single modifier keys (Caps Lock, etc.), monitor flagsChanged
        // For key+modifier combinations, monitor keyDown
        // Monitor both to support dynamic switching
        var eventMask: CGEventMask = 0
        eventMask |= (1 << CGEventType.flagsChanged.rawValue)
        eventMask |= (1 << CGEventType.keyDown.rawValue)

        // The event tap callback
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleEvent(type: type, event: event)

            return Unmanaged.passUnretained(event)
        }

        // Create the event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("KeyboardMonitor: Failed to create event tap")
            return false
        }

        self.eventTap = tap

        // Create run loop source and add to current run loop
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isMonitoring = true
        NSLog("⌨️ KeyboardMonitor: Started monitoring for %@", hotkey.displayString)

        return true
    }

    /// Stop monitoring for keyboard events
    func stopMonitoring() {
        guard isMonitoring else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        onTrigger = nil
        isMonitoring = false

        print("KeyboardMonitor: Stopped monitoring")
    }

    // MARK: - Private Methods

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let currentHotkey = getHotkey()

        if currentHotkey.isSingleModifierKey {
            // Handle single modifier keys (Caps Lock, Right Option, Fn, etc.)
            guard type == .flagsChanged else { return }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let eventFlags = event.flags

            // Only trigger if this is the correct key
            guard keyCode == Int64(currentHotkey.keyCode) else { return }

            // Determine the relevant flag for this modifier key
            let relevantFlag: CGEventFlags
            switch currentHotkey.keyCode {
            case 57: // Caps Lock
                relevantFlag = .maskAlphaShift
            case 61: // Right Option
                relevantFlag = .maskAlternate
            case 63: // Fn
                relevantFlag = .maskSecondaryFn
            default:
                return
            }

            // Check if the modifier is being pressed (not released)
            let isPressed = eventFlags.contains(relevantFlag)
            let wasPressed = lastModifierFlags.contains(relevantFlag)

            // Update state
            lastModifierFlags = eventFlags

            // Only trigger on press (not release)
            if isPressed && !wasPressed {
                NSLog("🔔 KeyboardMonitor: %@ detected (press)", currentHotkey.displayString)
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
            }
        } else {
            // Handle key+modifier combinations
            // Only process keyDown events for key+modifier combinations
            guard type == .keyDown else { return }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Check if keycode matches
            guard keyCode == Int64(currentHotkey.keyCode) else { return }

            // Key matches! Now check modifiers
            let eventFlags = event.flags

            // Extract only the modifier flags we care about
            let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let eventModifiers = eventFlags.intersection(relevantMask)
            let expectedFlags = currentHotkey.modifiers.cgEventFlags

            NSLog("🔍 Hotkey candidate: key=%@ (code=%d), eventMods=0x%lx, expectedMods=0x%lx",
                  Hotkey.keyCodeToString(UInt16(keyCode)),
                  keyCode,
                  eventModifiers.rawValue,
                  expectedFlags.rawValue)

            // Check if modifiers match exactly
            if eventModifiers == expectedFlags {
                NSLog("🔔 KeyboardMonitor: %@ detected - MATCH!", currentHotkey.displayString)
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
            } else {
                NSLog("❌ Modifier mismatch - expected 0x%lx, got 0x%lx", expectedFlags.rawValue, eventModifiers.rawValue)
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        stopMonitoring()
    }
}
