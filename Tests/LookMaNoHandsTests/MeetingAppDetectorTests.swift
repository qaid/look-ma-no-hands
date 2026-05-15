import XCTest
@testable import LookMaNoHands

// MARK: - Bundle ID matching

final class MeetingAppBundleIDTests: XCTestCase {

    func testZoomBundleIDMatches() {
        XCTAssertEqual(MeetingAppDetector.matchBundleID("us.zoom.xos"), .zoom)
    }

    func testTeamsBundleIDMatches() {
        XCTAssertEqual(MeetingAppDetector.matchBundleID("com.microsoft.teams2"), .teams)
    }

    func testClassicTeamsBundleIDMatches() {
        XCTAssertEqual(MeetingAppDetector.matchBundleID("com.microsoft.teams"), .teams)
    }

    func testUnknownBundleIDReturnsNil() {
        XCTAssertNil(MeetingAppDetector.matchBundleID("com.apple.Safari"))
    }

    func testEmptyBundleIDReturnsNil() {
        XCTAssertNil(MeetingAppDetector.matchBundleID(""))
    }

    func testBrowserBundleIDAloneDoesNotMatch() {
        // Browser bundle IDs should not match any native meeting app
        XCTAssertNil(MeetingAppDetector.matchBundleID("com.google.Chrome"))
        XCTAssertNil(MeetingAppDetector.matchBundleID("com.brave.Browser"))
        XCTAssertNil(MeetingAppDetector.matchBundleID("company.thebrowser.Browser"))
    }
}

// MARK: - Google Meet window title detection

final class GoogleMeetTitleTests: XCTestCase {

    func testMeetURLInTitle() {
        XCTAssertTrue(MeetingAppDetector.isGoogleMeetTitle("meet.google.com/abc-defg-hij - Google Chrome"))
    }

    func testGoogleMeetNameInTitle() {
        XCTAssertTrue(MeetingAppDetector.isGoogleMeetTitle("Team Standup - Google Meet"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(MeetingAppDetector.isGoogleMeetTitle("MEET.GOOGLE.COM/xyz"))
    }

    func testNonMeetTitle() {
        XCTAssertFalse(MeetingAppDetector.isGoogleMeetTitle("Gmail - Google Chrome"))
    }

    func testEmptyTitle() {
        XCTAssertFalse(MeetingAppDetector.isGoogleMeetTitle(""))
    }

    func testGoogleDocsNotMeet() {
        XCTAssertFalse(MeetingAppDetector.isGoogleMeetTitle("Untitled Document - Google Docs"))
    }
}

// MARK: - Zoom meeting title detection

final class ZoomMeetingTitleTests: XCTestCase {

    func testZoomMeetingTitle() {
        XCTAssertTrue(MeetingAppDetector.isZoomMeetingTitle("Zoom Meeting"))
    }

    func testZoomWebinarTitle() {
        XCTAssertTrue(MeetingAppDetector.isZoomMeetingTitle("Zoom Webinar"))
    }

    func testZoomMainWindow() {
        XCTAssertTrue(MeetingAppDetector.isZoomMeetingTitle("Zoom"))
    }

    func testNonMeetingZoomTitle() {
        XCTAssertFalse(MeetingAppDetector.isZoomMeetingTitle("Settings"))
    }

    func testEmptyZoomTitle() {
        XCTAssertFalse(MeetingAppDetector.isZoomMeetingTitle(""))
    }
}

// MARK: - Teams meeting title detection

final class TeamsMeetingTitleTests: XCTestCase {

    func testTeamsMeetingWithTitle() {
        XCTAssertTrue(MeetingAppDetector.isTeamsMeetingTitle("Meeting with John | Microsoft Teams"))
    }

    func testTeamsCallWithTitle() {
        XCTAssertTrue(MeetingAppDetector.isTeamsMeetingTitle("Call with Engineering"))
    }

    func testTeamsNonMeetingTitle() {
        XCTAssertFalse(MeetingAppDetector.isTeamsMeetingTitle("Chat - Microsoft Teams"))
    }

    func testEmptyTeamsTitle() {
        XCTAssertFalse(MeetingAppDetector.isTeamsMeetingTitle(""))
    }
}

// MARK: - MeetingApp model

final class MeetingAppModelTests: XCTestCase {

    func testAllCasesHaveDisplayNames() {
        for app in MeetingApp.allCases {
            XCTAssertFalse(app.displayName.isEmpty, "\(app) has empty displayName")
        }
    }

    func testAllCasesHaveIcons() {
        for app in MeetingApp.allCases {
            XCTAssertFalse(app.icon.isEmpty, "\(app) has empty icon")
        }
    }

    func testCodableRoundTrip() throws {
        for app in MeetingApp.allCases {
            let data = try JSONEncoder().encode(app)
            let decoded = try JSONDecoder().decode(MeetingApp.self, from: data)
            XCTAssertEqual(decoded, app)
        }
    }

    func testZoomHasNativeBundleIDs() {
        XCTAssertFalse(MeetingApp.zoom.bundleIDs.isEmpty)
        XCTAssertTrue(MeetingApp.zoom.bundleIDs.contains("us.zoom.xos"))
    }

    func testTeamsHasNativeBundleIDs() {
        XCTAssertFalse(MeetingApp.teams.bundleIDs.isEmpty)
        XCTAssertTrue(MeetingApp.teams.bundleIDs.contains("com.microsoft.teams2"))
    }

    func testGoogleMeetHasNoBundleIDs() {
        XCTAssertTrue(MeetingApp.googleMeet.bundleIDs.isEmpty)
    }

    func testBrowserBundleIDsNotEmpty() {
        XCTAssertFalse(MeetingApp.browserBundleIDs.isEmpty)
        XCTAssertTrue(MeetingApp.browserBundleIDs.contains("com.google.Chrome"))
    }

    func testAllNativeBundleIDsAggregation() {
        let allIDs = MeetingApp.allNativeBundleIDs
        XCTAssertTrue(allIDs.contains("us.zoom.xos"))
        XCTAssertTrue(allIDs.contains("com.microsoft.teams"))
        XCTAssertTrue(allIDs.contains("com.microsoft.teams2"))
        // Browser IDs should not be in native bundle IDs
        XCTAssertFalse(allIDs.contains("com.google.Chrome"))
    }
}
