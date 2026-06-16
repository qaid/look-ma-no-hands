import Foundation
import AppKit
import ApplicationServices

/// Detects active video conferencing apps and extracts participant names
/// from their accessibility trees during meeting recordings.
@MainActor
class MeetingAppDetector {

    struct DetectionResult: Sendable {
        let app: MeetingApp
        let pid: pid_t
        let windowTitle: String?
        let participants: [String]
    }

    private var pollingTimer: Timer?

    // MARK: - Pure Functions (Testable, nonisolated)

    /// Match a bundle ID to a MeetingApp. Pure function for testability.
    nonisolated static func matchBundleID(_ bundleID: String) -> MeetingApp? {
        for app in MeetingApp.allCases {
            if app.bundleIDs.contains(bundleID) {
                return app
            }
        }
        return nil
    }

    /// Check if a window title indicates a Google Meet session.
    nonisolated static func isGoogleMeetTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered.contains("meet.google.com") || lowered.contains("google meet")
    }

    /// Check if a window title suggests an active Zoom meeting.
    nonisolated static func isZoomMeetingTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered.contains("zoom meeting")
            || lowered.contains("zoom webinar")
            || lowered.hasPrefix("zoom")  // Zoom's main meeting window is titled "Zoom"
    }

    /// Check if a window title suggests an active Teams meeting/call.
    nonisolated static func isTeamsMeetingTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered.contains("meeting with")
            || lowered.contains("| microsoft teams")
            || lowered.contains("call with")
    }

    // MARK: - App Detection

    /// One-shot scan: which meeting app is currently in an active meeting?
    /// Checks native apps first (requiring meeting-active window titles), then browsers for Google Meet.
    static func detectActiveMeetingApp() -> DetectionResult? {
        let runningApps = NSWorkspace.shared.runningApplications

        // Check native apps first (Zoom, Teams) -- require a meeting-active window title
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if let meetingApp = matchBundleID(bundleID) {
                let titles = windowTitles(for: app.processIdentifier)
                let activeMeetingTitle = titles.first { title in
                    switch meetingApp {
                    case .zoom: return isZoomMeetingTitle(title)
                    case .teams: return isTeamsMeetingTitle(title)
                    case .googleMeet: return false
                    }
                }
                if let title = activeMeetingTitle {
                    return DetectionResult(
                        app: meetingApp,
                        pid: app.processIdentifier,
                        windowTitle: title,
                        participants: []
                    )
                }
            }
        }

        // Check browsers for Google Meet -- scan all windows, not just the first
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  MeetingApp.browserBundleIDs.contains(bundleID) else { continue }

            let titles = windowTitles(for: app.processIdentifier)
            if let meetTitle = titles.first(where: { isGoogleMeetTitle($0) }) {
                return DetectionResult(
                    app: .googleMeet,
                    pid: app.processIdentifier,
                    windowTitle: meetTitle,
                    participants: []
                )
            }
        }

        return nil
    }

    // MARK: - Participant Extraction

    /// Extract participant names from the meeting app's accessibility tree.
    /// Returns an empty array if extraction fails (graceful fallback).
    func extractParticipants(for app: MeetingApp, pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)

        switch app {
        case .zoom:
            return extractZoomParticipants(appElement: appElement)
        case .teams:
            return extractTeamsParticipants(appElement: appElement)
        case .googleMeet:
            return extractGoogleMeetParticipants(appElement: appElement)
        }
    }

    // MARK: - Polling

    /// Start periodic polling for participant updates during recording.
    func startPolling(interval: TimeInterval = 15, onChange: @escaping @MainActor (DetectionResult) -> Void) {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard let result = Self.detectActiveMeetingApp() else { return }
                let participants = self.extractParticipants(for: result.app, pid: result.pid)
                let updated = DetectionResult(
                    app: result.app,
                    pid: result.pid,
                    windowTitle: result.windowTitle,
                    participants: participants
                )
                onChange(updated)
            }
        }
    }

    /// Stop polling.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Accessibility Helpers

    /// Get the titles of all windows for a given process.
    private static func windowTitles(for pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        var titles: [String] = []
        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               !title.isEmpty {
                titles.append(title)
            }
        }
        return titles
    }

    /// Recursively collect all AXStaticText values from an element's subtree,
    /// up to a maximum depth to avoid runaway traversal.
    private func collectStaticTextValues(
        from element: AXUIElement,
        maxDepth: Int = 6,
        currentDepth: Int = 0
    ) -> [String] {
        guard currentDepth < maxDepth else { return [] }

        var results: [String] = []

        // Check if this element is a static text with a value
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXStaticText" || role == kAXStaticTextRole as String {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let value = valueRef as? String,
               !value.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(value.trimmingCharacters(in: .whitespaces))
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return results
        }

        for child in children {
            results.append(contentsOf: collectStaticTextValues(
                from: child,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1
            ))
        }

        return results
    }

    /// Find a child element matching a given role.
    private func findChildWithRole(_ role: String, in element: AXUIElement) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let childRole = roleRef as? String,
               childRole == role {
                return child
            }
        }
        return nil
    }

    /// Find all child elements matching a given role.
    private func findChildrenWithRole(_ role: String, in element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }

        return children.filter { child in
            var roleRef: CFTypeRef?
            return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success
                && (roleRef as? String) == role
        }
    }

    // MARK: - App-Specific Extraction

    /// Extract participant names from Zoom's participant panel.
    /// Zoom's participant list uses AXList > AXGroup > AXStaticText hierarchy.
    private func extractZoomParticipants(appElement: AXUIElement) -> [String] {
        // Get all windows and look for the participants panel
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        var names: [String] = []
        for window in windows {
            // Look for AXList elements (participant list panels)
            let lists = findChildrenWithRole("AXList", in: window)
            for list in lists {
                let texts = collectStaticTextValues(from: list, maxDepth: 4)
                names.append(contentsOf: texts)
            }

            // Also check AXGroup > AXList pattern (Zoom sometimes nests differently)
            let groups = findChildrenWithRole("AXGroup", in: window)
            for group in groups {
                let lists = findChildrenWithRole("AXList", in: group)
                for list in lists {
                    let texts = collectStaticTextValues(from: list, maxDepth: 4)
                    names.append(contentsOf: texts)
                }
            }
        }

        return filterParticipantNames(names)
    }

    /// Extract participant names from Microsoft Teams' roster panel.
    private func extractTeamsParticipants(appElement: AXUIElement) -> [String] {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        var names: [String] = []
        for window in windows {
            // Teams uses AXList for its people/roster panel
            let lists = findChildrenWithRole("AXList", in: window)
            for list in lists {
                let texts = collectStaticTextValues(from: list, maxDepth: 5)
                names.append(contentsOf: texts)
            }
        }

        return filterParticipantNames(names)
    }

    /// Extract participant names from Google Meet in a browser.
    /// Looks for participant sidebar in the browser's accessibility tree.
    private func extractGoogleMeetParticipants(appElement: AXUIElement) -> [String] {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        var names: [String] = []
        for window in windows {
            // Check window title to find the Meet tab
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               Self.isGoogleMeetTitle(title) {
                // Walk into the web content area looking for participant list
                let texts = collectStaticTextValues(from: window, maxDepth: 8)
                names.append(contentsOf: texts)
            }
        }

        return filterParticipantNames(names)
    }

    // MARK: - Name Filtering

    /// Filter extracted text values to likely participant names.
    /// Removes UI labels, status text, duplicates, and very short/long strings.
    private func filterParticipantNames(_ rawNames: [String]) -> [String] {
        let uiLabels: Set<String> = [
            "Mute", "Unmute", "mute", "unmute",
            "Participants", "participants",
            "Chat", "chat",
            "More", "more",
            "Leave", "leave",
            "Host", "host", "Co-host", "co-host",
            "Raise Hand", "Lower Hand",
            "In this meeting", "In the meeting",
            "People", "You",
            "Share Screen", "Record",
            "Reactions", "View",
        ]

        var seen = Set<String>()
        var filtered: [String] = []

        for name in rawNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty, too short, or too long
            guard trimmed.count >= 2, trimmed.count <= 60 else { continue }

            // Skip known UI labels
            guard !uiLabels.contains(trimmed) else { continue }

            // Skip strings that look like timestamps, numbers, or status text
            if trimmed.allSatisfy({ $0.isNumber || $0 == ":" || $0 == " " }) { continue }

            // Skip duplicates (case-insensitive)
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            filtered.append(trimmed)
        }

        return filtered
    }
}
