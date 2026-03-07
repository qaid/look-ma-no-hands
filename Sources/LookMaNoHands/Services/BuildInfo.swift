import Foundation

/// Build information injected by deploy.sh at build time.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "fd1e4e53b9a0a23188e741c074515bc72b65247f"
    static let commitShortSHA = "fd1e4e5"
    static let buildDate = "2026-03-07 08:57:32 UTC"
    static let branch = "issue/settings-window-sizing"
}
