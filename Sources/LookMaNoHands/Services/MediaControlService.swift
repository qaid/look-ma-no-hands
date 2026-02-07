import Cocoa

/// Controls system media playback by simulating the hardware play/pause key.
/// Used to auto-pause media when dictation starts and resume when it ends.
class MediaControlService {

    /// Whether we paused media (so we only resume what we paused)
    private var didPauseMedia = false

    /// Guards against a race where resumeMedia() is called before the async
    /// playback-state check completes. If set to false, the pending pause is cancelled.
    private var shouldPause = false

    /// Function pointer for checking if media is playing (loaded from MediaRemote.framework)
    private let isPlayingFunc: ((DispatchQueue, @escaping (Bool) -> Void) -> Void)?

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        if let handle = dlopen(path, RTLD_NOW),
           let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            typealias IsPlayingFunc = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
            isPlayingFunc = unsafeBitCast(sym, to: IsPlayingFunc.self)
        } else {
            isPlayingFunc = nil
        }
    }

    /// Pause system media playback before dictation recording begins.
    /// Only sends the toggle if media is actually playing, avoiding the problem
    /// where toggling with nothing playing would *start* playback.
    func pauseMedia() {
        shouldPause = true

        guard let isPlayingFunc else { return }

        isPlayingFunc(DispatchQueue.main) { [weak self] isPlaying in
            guard let self, self.shouldPause, isPlaying else { return }
            self.sendPlayPauseKey()
            self.didPauseMedia = true
        }
    }

    /// Resume system media playback after dictation ends, but only if we paused it.
    func resumeMedia() {
        shouldPause = false
        guard didPauseMedia else { return }
        sendPlayPauseKey()
        didPauseMedia = false
    }

    // MARK: - Private

    /// Simulate a press of the hardware play/pause media key via CGEvent.
    /// The system routes this to whichever app owns the current "Now Playing" session.
    private func sendPlayPauseKey() {
        let NX_KEYTYPE_PLAY: Int32 = 16
        let NX_SUBTYPE_AUX_CONTROL_BUTTONS: Int16 = 8

        // Key down
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: NX_SUBTYPE_AUX_CONTROL_BUTTONS,
            data1: Int((NX_KEYTYPE_PLAY << 16) | (0xA << 8)),
            data2: -1
        )
        keyDown?.cgEvent?.post(tap: .cghidEventTap)

        // Key up
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: NX_SUBTYPE_AUX_CONTROL_BUTTONS,
            data1: Int((NX_KEYTYPE_PLAY << 16) | (0xB << 8)),
            data2: -1
        )
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }
}
