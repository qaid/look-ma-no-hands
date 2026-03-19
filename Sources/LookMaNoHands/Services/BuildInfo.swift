import Foundation

/// Build information injected at build time by inject-build-info.sh.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "f0739ea6c241d527ffd323707b78358f3f210c8d"
    static let commitShortSHA = "f0739ea"
    static let buildDate = "2026-03-19 07:40:21 UTC"
    static let branch = "review-whisperkit-bump"
}
