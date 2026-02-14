import Foundation

/// Build information injected by deploy.sh at build time.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "development"
    static let commitShortSHA = "dev"
    static let buildDate = ""
    static let branch = "unknown"
}
