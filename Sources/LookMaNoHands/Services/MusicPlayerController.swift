import Foundation
import AppKit

/// Manages pause/resume of music players using AppleScript
/// This is the macOS-specific approach to prevent media from resuming when recording starts
final class MusicPlayerController {

    // MARK: - Singleton

    static let shared = MusicPlayerController()

    // MARK: - Properties

    /// Track which players were playing before we paused them
    private var wasSpotifyPlaying = false
    private var wasMusicPlaying = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Pause/Resume Control

    /// Pause all supported music players and remember their state
    /// Call this BEFORE starting AVAudioEngine to prevent media from resuming
    func pauseAllPlayers() {
        // Check and pause Spotify
        wasSpotifyPlaying = isPlayerPlaying("Spotify")
        if wasSpotifyPlaying {
            pausePlayer("Spotify")
            Logger.shared.info("Paused Spotify for dictation", category: .audio)
        }

        // Check and pause Apple Music
        wasMusicPlaying = isPlayerPlaying("Music")
        if wasMusicPlaying {
            pausePlayer("Music")
            Logger.shared.info("Paused Apple Music for dictation", category: .audio)
        }

        // Small delay to ensure AppleScript commands complete
        Thread.sleep(forTimeInterval: 0.1)
    }

    /// Resume players that were playing before pauseAllPlayers() was called
    /// Call this AFTER stopping AVAudioEngine if you want to resume playback
    func resumePreviouslyPlayingPlayers() {
        if wasSpotifyPlaying {
            resumePlayer("Spotify")
            Logger.shared.info("Resumed Spotify after dictation", category: .audio)
        }

        if wasMusicPlaying {
            resumePlayer("Music")
            Logger.shared.info("Resumed Apple Music after dictation", category: .audio)
        }

        // Reset state
        wasSpotifyPlaying = false
        wasMusicPlaying = false
    }

    // MARK: - Private Methods

    /// Check if a player is currently playing
    private func isPlayerPlaying(_ appName: String) -> Bool {
        // First check if app is actually running using NSWorkspace (no permission dialog)
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.localizedName == appName || $0.bundleIdentifier?.contains(appName.lowercased()) == true }

        guard isRunning else {
            // App not running, no need to check - this avoids permission dialogs
            return false
        }

        let script = """
        try
            if application "\(appName)" is running then
                tell application "\(appName)"
                    return player state is playing
                end tell
            else
                return false
            end if
        on error
            return false
        end try
        """

        if let scriptObject = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            let result = scriptObject.executeAndReturnError(&errorDict)

            if let error = errorDict {
                Logger.shared.debug("AppleScript error checking \(appName) state: \(error)", category: .audio)
                return false
            }

            return result.booleanValue
        }

        return false
    }

    /// Pause a specific player using AppleScript
    private func pausePlayer(_ appName: String) {
        let script = """
        try
            if application "\(appName)" is running then
                tell application "\(appName)"
                    if player state is playing then
                        pause
                    end if
                end tell
            end if
        on error errMsg
            -- Silently fail if player doesn't support pause command
        end try
        """

        executeAppleScript(script, description: "pause \(appName)")
    }

    /// Resume a specific player using AppleScript
    private func resumePlayer(_ appName: String) {
        let script = """
        try
            if application "\(appName)" is running then
                tell application "\(appName)"
                    if player state is paused then
                        play
                    end if
                end tell
            end if
        on error errMsg
            -- Silently fail if player doesn't support play command
        end try
        """

        executeAppleScript(script, description: "resume \(appName)")
    }

    /// Execute an AppleScript and log errors
    private func executeAppleScript(_ script: String, description: String) {
        if let scriptObject = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            scriptObject.executeAndReturnError(&errorDict)

            if let error = errorDict {
                Logger.shared.debug("AppleScript error (\(description)): \(error)", category: .audio)
            }
        }
    }
}
