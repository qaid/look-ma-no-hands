import Cocoa

/// Controls system media playback by simulating the hardware play/pause key.
/// Used to auto-pause media when dictation starts and resume when it ends.
/// Uses the same mechanism as external keyboard media keys.
class MediaControlService {

    /// Whether we paused media (so we only resume what we paused)
    private var didPauseMedia = false

    /// Pause system media playback before dictation recording begins.
    /// Sends pause command multiple times to ensure it sticks (especially for browsers).
    func pauseMedia() {
        NSLog("⏸️ MediaControlService: pausing media")

        // Send pause event multiple times to ensure browsers and other media players receive it
        // Some apps (especially browsers) may need the event sent multiple times
        for i in 0..<3 {
            sendMediaKey(down: true)
            sendMediaKey(down: false)

            // Small delay between attempts (50ms)
            if i < 2 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        didPauseMedia = true
    }

    /// Resume system media playback after dictation ends, but only if we paused it.
    func resumeMedia() {
        guard didPauseMedia else { return }
        NSLog("▶️ MediaControlService: resuming media")
        sendMediaKey(down: true)
        sendMediaKey(down: false)
        didPauseMedia = false
    }

    // MARK: - Private

    /// Simulate a hardware play/pause media key press via CGEvent.
    /// This is the same event that macOS receives from external keyboard media keys.
    private func sendMediaKey(down: Bool) {
        // NX_KEYTYPE_PLAY = 16, NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8
        let keyType: UInt32 = 16
        let flags: UInt32 = down ? 0xA : 0xB
        let data1 = Int((keyType << 16) | (flags << 8))

        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )

        if let cgEvent = event?.cgEvent {
            cgEvent.post(tap: .cghidEventTap)
        } else {
            NSLog("⚠️ MediaControlService: failed to create CGEvent for media key")
        }
    }
}
