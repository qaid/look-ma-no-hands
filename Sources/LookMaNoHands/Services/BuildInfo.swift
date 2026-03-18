import Foundation

/// Build information injected at build time by inject-build-info.sh.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "e2e279d9a225a585947a24e68686c053b16612d2"
    static let commitShortSHA = "e2e279d"
    static let buildDate = "2026-03-18 00:55:20 UTC"
    static let branch = "meeting-window-design-bug"
}
