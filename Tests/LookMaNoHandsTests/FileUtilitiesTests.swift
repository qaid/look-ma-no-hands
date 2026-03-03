import XCTest
@testable import LookMaNoHands

final class FileUtilitiesTests: XCTestCase {

    func testSanitizeFilenameReplacesIllegalCharacters() {
        XCTAssertEqual(sanitizeFilename("Meeting: Q1/Q2"), "Meeting- Q1-Q2")
        XCTAssertEqual(sanitizeFilename("notes<draft>"), "notes-draft-")
        XCTAssertEqual(sanitizeFilename("file*name?.md"), "file-name-.md")
    }

    func testSanitizeFilenamePreservesLegalCharacters() {
        let legal = "Team Standup - Mar 3, 2026 10.30 AM"
        XCTAssertEqual(sanitizeFilename(legal), legal)
    }

    func testSanitizeFilenameHandlesEmptyString() {
        XCTAssertEqual(sanitizeFilename(""), "")
    }
}
