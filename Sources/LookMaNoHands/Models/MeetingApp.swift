import Foundation

/// Identifies a supported video conferencing application for meeting app integration
enum MeetingApp: String, Sendable, CaseIterable, Codable {
    case zoom
    case teams
    case googleMeet

    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .googleMeet: return "Google Meet"
        }
    }

    var icon: String {
        switch self {
        case .zoom: return "video.fill"
        case .teams: return "person.3.fill"
        case .googleMeet: return "globe"
        }
    }

    /// Bundle IDs that identify this native app
    var bundleIDs: Set<String> {
        switch self {
        case .zoom: return ["us.zoom.xos"]
        case .teams: return ["com.microsoft.teams", "com.microsoft.teams2"]
        case .googleMeet: return []  // Browser-based, detected via window title
        }
    }

    /// Bundle IDs for browsers that may host Google Meet
    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",  // Arc
    ]

    /// All native meeting app bundle IDs across all cases
    static let allNativeBundleIDs: Set<String> = {
        var ids = Set<String>()
        for app in MeetingApp.allCases {
            ids.formUnion(app.bundleIDs)
        }
        return ids
    }()
}
