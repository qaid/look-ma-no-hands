import Cocoa

/// Controls system media playback using macOS MediaRemote framework.
/// Used to auto-pause media when dictation starts and resume when it ends.
///
/// Uses MRMediaRemoteSendCommand to send explicit pause/play commands instead
/// of hardware play/pause toggle events (NX_KEYTYPE_PLAY), which would launch
/// Apple Music if no media app is currently the "Now Playing" source. (#128)
class MediaControlService {

    /// Whether we paused media (so we only resume what we paused)
    private var didPauseMedia = false

    /// Cached function pointer for MRMediaRemoteSendCommand
    private var sendCommandFunc: MRMediaRemoteSendCommandFunc?

    /// Whether MediaRemote framework loaded successfully
    private var mediaRemoteAvailable = false

    // MediaRemote function type: MRMediaRemoteSendCommand(command, options) -> Bool
    private typealias MRMediaRemoteSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> Bool

    // MediaRemote command constants
    private static let kMRPlay: UInt32 = 0
    private static let kMRPause: UInt32 = 1
    private static let kMRTogglePlayPause: UInt32 = 2

    init() {
        loadMediaRemote()
    }

    /// Pause system media playback before dictation recording begins.
    /// Sends an explicit pause command (not a toggle) so it won't start playback
    /// if nothing is currently playing.
    func pauseMedia() {
        if mediaRemoteAvailable, let sendCommand = sendCommandFunc {
            NSLog("⏸️ MediaControlService: sending pause command via MediaRemote")
            _ = sendCommand(Self.kMRPause, nil)
            didPauseMedia = true
        } else {
            // Fallback: use hardware media key event if MediaRemote unavailable
            NSLog("⏸️ MediaControlService: MediaRemote unavailable, using hardware key fallback")
            sendMediaKey(down: true)
            sendMediaKey(down: false)
            didPauseMedia = true
        }
    }

    /// Resume system media playback after dictation ends, but only if we paused it.
    func resumeMedia() {
        guard didPauseMedia else { return }

        if mediaRemoteAvailable, let sendCommand = sendCommandFunc {
            NSLog("▶️ MediaControlService: sending play command via MediaRemote")
            _ = sendCommand(Self.kMRPlay, nil)
        } else {
            NSLog("▶️ MediaControlService: MediaRemote unavailable, using hardware key fallback")
            sendMediaKey(down: true)
            sendMediaKey(down: false)
        }

        didPauseMedia = false
    }

    // MARK: - Private

    /// Dynamically load the MediaRemote private framework
    private func loadMediaRemote() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: frameworkPath)) else {
            NSLog("⚠️ MediaControlService: Could not load MediaRemote framework")
            return
        }

        guard let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
            NSLog("⚠️ MediaControlService: Could not find MRMediaRemoteSendCommand")
            return
        }

        sendCommandFunc = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunc.self)
        mediaRemoteAvailable = true
        NSLog("✅ MediaControlService: MediaRemote framework loaded successfully")
    }

    /// Fallback: Simulate a hardware play/pause media key press via CGEvent.
    /// Only used if MediaRemote framework is unavailable.
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
