import Cocoa

/// Controls system media playback using macOS MediaRemote framework.
/// Used to auto-pause media when dictation starts and resume when it ends.
///
/// Before sending any command, checks whether media is actually playing.
/// Without this guard, sending commands when no app owns the "Now Playing"
/// session (e.g. on a clean install) causes macOS to launch Apple Music
/// as the default media handler. (#128)
class MediaControlService {

    /// Whether we paused media (so we only resume what we paused)
    private var didPauseMedia = false

    /// Cached function pointer for MRMediaRemoteSendCommand
    private var sendCommandFunc: MRMediaRemoteSendCommandFunc?

    /// Cached function pointer for MRMediaRemoteGetNowPlayingApplicationIsPlaying
    private var getNowPlayingIsPlayingFunc: MRMediaRemoteGetNowPlayingIsPlayingFunc?

    /// Whether MediaRemote framework loaded successfully
    private var mediaRemoteAvailable = false

    // MediaRemote function types
    private typealias MRMediaRemoteSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias MRMediaRemoteGetNowPlayingIsPlayingFunc = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    // MediaRemote command constants
    private static let kMRPlay: UInt32 = 0
    private static let kMRPause: UInt32 = 1

    init() {
        loadMediaRemote()
    }

    /// Pause system media playback before dictation recording begins.
    /// Only sends the pause command if something is actually playing,
    /// preventing Apple Music from launching on a clean install. (#128)
    func pauseMedia() {
        guard mediaRemoteAvailable, let sendCommand = sendCommandFunc else {
            NSLog("⏸️ MediaControlService: MediaRemote unavailable, skipping pause")
            return
        }

        // Check if anything is actually playing before sending pause.
        // Sending commands when nothing is playing causes macOS to launch
        // Apple Music as the default media handler on clean installs.
        guard isNowPlayingActive() else {
            NSLog("⏸️ MediaControlService: nothing currently playing, skipping pause to avoid launching Music")
            return
        }

        NSLog("⏸️ MediaControlService: sending pause command via MediaRemote")
        _ = sendCommand(Self.kMRPause, nil)
        didPauseMedia = true
    }

    /// Resume system media playback after dictation ends, but only if we paused it.
    func resumeMedia() {
        guard didPauseMedia else { return }

        if mediaRemoteAvailable, let sendCommand = sendCommandFunc {
            NSLog("▶️ MediaControlService: sending play command via MediaRemote")
            _ = sendCommand(Self.kMRPlay, nil)
        } else {
            NSLog("▶️ MediaControlService: MediaRemote unavailable, cannot resume")
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

        guard let sendPtr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
            NSLog("⚠️ MediaControlService: Could not find MRMediaRemoteSendCommand")
            return
        }

        sendCommandFunc = unsafeBitCast(sendPtr, to: MRMediaRemoteSendCommandFunc.self)
        mediaRemoteAvailable = true

        // Also load the "is playing" check to gate commands
        if let isPlayingPtr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            getNowPlayingIsPlayingFunc = unsafeBitCast(isPlayingPtr, to: MRMediaRemoteGetNowPlayingIsPlayingFunc.self)
            NSLog("✅ MediaControlService: MediaRemote framework loaded (with Now Playing check)")
        } else {
            NSLog("✅ MediaControlService: MediaRemote framework loaded (without Now Playing check, using app-list fallback)")
        }
    }

    /// Check if any media is currently playing before sending commands.
    /// Returns false on a clean install (no Now Playing source), which
    /// prevents the pause command from inadvertently launching Music.
    private func isNowPlayingActive() -> Bool {
        // Primary: use MediaRemote async API to check actual playback state
        if let getNowPlayingIsPlaying = getNowPlayingIsPlayingFunc {
            let semaphore = DispatchSemaphore(value: 0)
            var isPlaying = false

            getNowPlayingIsPlaying(DispatchQueue.global(qos: .userInteractive)) { playing in
                isPlaying = playing
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + 0.5)
            if result == .success {
                NSLog("📊 MediaControlService: Now Playing check result: \(isPlaying)")
                return isPlaying
            }
            NSLog("⚠️ MediaControlService: Now Playing check timed out after 0.5s, falling back to app check")
        }

        // Fallback: check if any known media app is running
        return isAnyMediaAppRunning()
    }

    /// Fallback heuristic: check if any common dedicated media app is running.
    /// On a clean install none of these will be running, correctly returning false.
    private func isAnyMediaAppRunning() -> Bool {
        let mediaAppBundleIDs: Set<String> = [
            "com.apple.Music",
            "com.apple.TV",
            "com.spotify.client",
            "org.videolan.vlc",
            "com.coppertino.Vox",
            "com.plexapp.plexamp",
            // Browsers that commonly play media
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.apple.Safari",
            "com.brave.Browser",
            "com.microsoft.edgemac",
        ]

        let hasMediaApp = NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return mediaAppBundleIDs.contains(bundleID)
        }

        if hasMediaApp {
            NSLog("📊 MediaControlService: Found running media app")
        } else {
            NSLog("📊 MediaControlService: No media apps detected")
        }

        return hasMediaApp
    }
}
