import Foundation

/// Build information injected by deploy.sh at build time.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "85b2097c8b39dc0f1e43c829e4cd0410dc1a1b6f"
    static let commitShortSHA = "85b2097"
    static let buildDate = "2026-03-04 10:00:50 UTC"
    static let branch = "fix/meeting-one-to-one-transcript-quality"
}
