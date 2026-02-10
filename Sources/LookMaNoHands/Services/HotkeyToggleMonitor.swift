import Foundation
import AppKit

/// Monitors for a global keyboard shortcut to toggle hotkey enabled/disabled state
/// Uses NSEvent local monitor for key combinations (e.g., Cmd+Shift+D)
class HotkeyToggleMonitor {

    // MARK: - Properties

    private var eventMonitor: Any?
    private var onToggle: (() -> Void)?
    private var isMonitoring = false

    // MARK: - Public Methods

    /// Start monitoring for the toggle shortcut
    /// - Parameter onToggle: Callback invoked when the toggle shortcut is pressed
    func startMonitoring(onToggle: @escaping () -> Void) {
        guard !isMonitoring else {
            NSLog("⚠️ HotkeyToggleMonitor: Already monitoring")
            return
        }

        self.onToggle = onToggle
        setupEventMonitor()
        isMonitoring = true

        // Listen for toggle shortcut changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleShortcutChanged),
            name: .toggleShortcutChanged,
            object: nil
        )

        if let shortcut = Settings.shared.toggleHotkeyShortcut {
            NSLog("⌨️ HotkeyToggleMonitor: Started monitoring for %@", shortcut.displayString)
        }
    }

    /// Stop monitoring for the toggle shortcut
    func stopMonitoring() {
        guard isMonitoring else { return }

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        NotificationCenter.default.removeObserver(self)
        onToggle = nil
        isMonitoring = false

        NSLog("⌨️ HotkeyToggleMonitor: Stopped monitoring")
    }

    // MARK: - Private Methods

    /// Set up or recreate the event monitor
    private func setupEventMonitor() {
        // Remove existing monitor if any
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Create new monitor for keyDown events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard let toggleShortcut = Settings.shared.toggleHotkeyShortcut else { return event }

            // Check if this event matches the toggle shortcut
            if self.matchesToggleShortcut(event: event, hotkey: toggleShortcut) {
                NSLog("🔔 HotkeyToggleMonitor: Toggle shortcut detected - consuming event")

                // Trigger the callback on main queue
                DispatchQueue.main.async {
                    self.onToggle?()
                }

                // Consume the event (prevent propagation)
                return nil
            }

            // Pass through non-matching events
            return event
        }
    }

    /// Check if the event matches the toggle shortcut
    /// - Parameters:
    ///   - event: The keyboard event to check
    ///   - hotkey: The hotkey configuration to match against
    /// - Returns: True if the event matches the hotkey
    private func matchesToggleShortcut(event: NSEvent, hotkey: Hotkey) -> Bool {
        // Check key code
        guard event.keyCode == hotkey.keyCode else { return false }

        // Check modifiers
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let expectedModifiers = convertToNSEventModifiers(hotkey.modifiers)

        return eventModifiers == expectedModifiers
    }

    /// Convert Hotkey.ModifierFlags to NSEvent.ModifierFlags
    private func convertToNSEventModifiers(_ modifiers: Hotkey.ModifierFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.command { flags.insert(.command) }
        if modifiers.shift { flags.insert(.shift) }
        if modifiers.option { flags.insert(.option) }
        if modifiers.control { flags.insert(.control) }
        return flags
    }

    /// Handle notification when toggle shortcut changes
    @objc private func toggleShortcutChanged() {
        NSLog("📢 HotkeyToggleMonitor: Toggle shortcut changed notification received")

        // Recreate the event monitor with the new shortcut
        setupEventMonitor()

        if let shortcut = Settings.shared.toggleHotkeyShortcut {
            NSLog("🔄 HotkeyToggleMonitor: Now monitoring for %@", shortcut.displayString)
        }
    }

    // MARK: - Cleanup

    deinit {
        stopMonitoring()
    }
}
