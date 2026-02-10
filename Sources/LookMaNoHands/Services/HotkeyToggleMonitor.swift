import Foundation
import AppKit

/// Monitors for a global keyboard shortcut to toggle hotkey enabled/disabled state
/// Uses both local and global NSEvent monitors to work from any app
class HotkeyToggleMonitor {

    // MARK: - Properties

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
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

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        NotificationCenter.default.removeObserver(self)
        onToggle = nil
        isMonitoring = false

        NSLog("⌨️ HotkeyToggleMonitor: Stopped monitoring")
    }

    // MARK: - Private Methods

    /// Set up or recreate the event monitors (both local and global)
    private func setupEventMonitor() {
        // Remove existing monitors if any
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        // Create local monitor for keyDown events when app is in focus
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard let toggleShortcut = Settings.shared.toggleHotkeyShortcut else { return event }

            // Check if this event matches the toggle shortcut
            if self.matchesToggleShortcut(event: event, hotkey: toggleShortcut) {
                NSLog("🔔 HotkeyToggleMonitor (local): Toggle shortcut detected")

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

        // Create global monitor for keyDown events when other apps are in focus
        // Note: Global monitors can only observe events, not modify/consume them
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            guard let toggleShortcut = Settings.shared.toggleHotkeyShortcut else { return }

            // Check if this event matches the toggle shortcut
            if self.matchesToggleShortcut(event: event, hotkey: toggleShortcut) {
                NSLog("🔔 HotkeyToggleMonitor (global): Toggle shortcut detected from other app")

                // Trigger the callback on main queue
                DispatchQueue.main.async {
                    self.onToggle?()
                }
            }
        }

        NSLog("⌨️ HotkeyToggleMonitor: Set up local + global event monitors")
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
