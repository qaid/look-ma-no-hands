import Foundation
import CoreGraphics
import AppKit

/// Monitors keyboard events system-wide to detect the configured trigger hotkey
/// Requires Accessibility permissions to function
class KeyboardMonitor {

    // MARK: - Types

    /// Callback type for when trigger key is pressed
    typealias TriggerCallback = () -> Void

    /// Callback type for when ESC key is pressed (to cancel recording)
    typealias CancellationCallback = () -> Void

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onTrigger: TriggerCallback?
    private var onCancel: CancellationCallback?

    /// The hotkey configuration to listen for
    private var hotkey: Hotkey = .capsLock

    /// Lock for thread-safe hotkey access
    private let hotkeyLock = NSLock()

    /// Whether the monitor is currently active
    private(set) var isMonitoring = false

    /// Whether the event tap is enabled (can be toggled without teardown)
    private var isEnabled = true

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

    /// Set the cancellation callback (called when ESC key is pressed during recording)
    func setCancellationCallback(_ callback: @escaping CancellationCallback) {
        self.onCancel = callback
    }

    /// Start monitoring for the trigger key
    /// - Parameters:
    ///   - hotkey: The hotkey to monitor for (defaults to Caps Lock)
    ///   - callback: Called when the trigger key is pressed
    ///   - showPrompt: Whether to show the system permission prompt if not granted (defaults to false)
    /// - Returns: True if monitoring started successfully
    @discardableResult
    func startMonitoring(hotkey: Hotkey = .capsLock, showPrompt: Bool = false, onTrigger callback: @escaping TriggerCallback) -> Bool {
        guard !isMonitoring else { return true }

        // Check accessibility permission (optionally prompting)
        let trusted: Bool
        if showPrompt {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        guard trusted else {
            print("KeyboardMonitor: Accessibility permission not granted\(showPrompt ? " - prompt shown" : "")")
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
            let shouldConsume = monitor.handleEvent(type: type, event: event)

            // If handleEvent returned true, consume the event (return nil) to prevent system handling
            // This fixes the issue where Caps Lock would trigger Music app and other system shortcuts
            if shouldConsume {
                return nil // Consume event - prevent propagation
            }

            return Unmanaged.passUnretained(event) // Pass through event
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
        isEnabled = Settings.shared.hotkeyEnabled
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

    /// Enable or disable the event tap without teardown (efficient toggle)
    func setEnabled(_ enabled: Bool) {
        hotkeyLock.lock()
        defer { hotkeyLock.unlock() }

        guard isMonitoring else {
            NSLog("⚠️ KeyboardMonitor: Cannot enable/disable - not monitoring")
            return
        }

        guard isEnabled != enabled else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
            isEnabled = enabled
            NSLog("🔄 KeyboardMonitor: %@ for %@",
                  enabled ? "Enabled" : "Disabled",
                  getHotkey().displayString)
        }
    }

    /// Get current enabled state
    func getIsEnabled() -> Bool {
        hotkeyLock.lock()
        defer { hotkeyLock.unlock() }
        return isEnabled
    }

    // MARK: - Private Methods

    /// Handle keyboard event and return whether it was consumed (should be blocked from propagating)
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        // Early return if hotkey monitoring is disabled
        guard isEnabled else { return false }

        // Check for ESC key (keyCode 53) to cancel recording
        // ESC is handled as a keyDown event
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // ESC key
                NSLog("⎋ KeyboardMonitor: ESC key detected - triggering cancellation")
                DispatchQueue.main.async { [weak self] in
                    self?.onCancel?()
                }
                return false // Don't consume ESC - let it propagate
            }
        }

        let currentHotkey = getHotkey()

        if currentHotkey.isSingleModifierKey {
            // Handle single modifier keys (Caps Lock, Right Option, Fn, etc.)
            guard type == .flagsChanged else { return false }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let eventFlags = event.flags

            // Only trigger if this is the correct key
            guard keyCode == Int64(currentHotkey.keyCode) else { return false }

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
                return false
            }

            // Check if the modifier state changed
            let isPressed = eventFlags.contains(relevantFlag)
            let wasPressed = lastModifierFlags.contains(relevantFlag)

            // Update state
            lastModifierFlags = eventFlags

            // For Caps Lock (a toggle key), trigger on BOTH press and release
            // For other modifier keys, only trigger on press
            let shouldTrigger: Bool
            if currentHotkey.keyCode == 57 { // Caps Lock
                // Trigger on any state change (toggle)
                shouldTrigger = isPressed != wasPressed
            } else {
                // Trigger only on press (not release)
                shouldTrigger = isPressed && !wasPressed
            }

            if shouldTrigger {
                NSLog("🔔 KeyboardMonitor: %@ detected (toggle/press) - consuming event", currentHotkey.displayString)
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
                return true // Consume the event to prevent system handling (e.g., Music app)
            }

            // For Caps Lock, always consume the key event to prevent system interference
            // even during state transitions (e.g., toggle off after recording)
            // This prevents Music app launch and other system shortcuts from triggering
            if currentHotkey.keyCode == 57 { // Caps Lock
                return true
            }

            // For other modifier keys, only consume when we trigger
            return false
        } else {
            // Handle key+modifier combinations
            // Only process keyDown events for key+modifier combinations
            guard type == .keyDown else { return false }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Check if keycode matches
            guard keyCode == Int64(currentHotkey.keyCode) else { return false }

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
                NSLog("🔔 KeyboardMonitor: %@ detected - MATCH! Consuming event", currentHotkey.displayString)
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
                return true // Consume the event to prevent system handling
            } else {
                NSLog("❌ Modifier mismatch - expected 0x%lx, got 0x%lx", expectedFlags.rawValue, eventModifiers.rawValue)
                return false // Don't consume non-matching events
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        stopMonitoring()
    }
}
