import XCTest
@testable import LookMaNoHands

final class AutoUpdateServiceTests: XCTestCase {

    // MARK: - Version Comparison

    func testNewerVersion() {
        XCTAssertTrue(UpdateService.isVersion("1.5.0", newerThan: "1.4.7"))
        XCTAssertTrue(UpdateService.isVersion("2.0.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateService.isVersion("1.5.1", newerThan: "1.5.0"))
    }

    func testSameVersion() {
        XCTAssertFalse(UpdateService.isVersion("1.5.0", newerThan: "1.5.0"))
        XCTAssertFalse(UpdateService.isVersion("0.0.0", newerThan: "0.0.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(UpdateService.isVersion("1.4.7", newerThan: "1.5.0"))
        XCTAssertFalse(UpdateService.isVersion("1.5.0", newerThan: "2.0.0"))
        XCTAssertFalse(UpdateService.isVersion("0.9.0", newerThan: "1.0.0"))
    }

    func testVersionWithDifferentComponentCounts() {
        XCTAssertTrue(UpdateService.isVersion("1.5.1", newerThan: "1.5"))
        XCTAssertFalse(UpdateService.isVersion("1.5", newerThan: "1.5.1"))
        XCTAssertFalse(UpdateService.isVersion("1.5", newerThan: "1.5.0"))
    }

    // MARK: - Checksum Parsing

    func testParseChecksumFindsCorrectHash() {
        let checksumText = """
        abc123def456  LookMaNoHands-1.5.0.zip
        deadbeef0123  Look.Ma.No.Hands.1.5.0.dmg
        fedcba987654  sbom.cyclonedx.json
        """

        let result = AutoUpdateService.parseChecksum(from: checksumText, forFile: "Look.Ma.No.Hands.1.5.0.dmg")
        XCTAssertEqual(result, "deadbeef0123")
    }

    func testParseChecksumReturnsNilForMissingFile() {
        let checksumText = """
        abc123def456  LookMaNoHands-1.5.0.zip
        deadbeef0123  Look.Ma.No.Hands.1.5.0.dmg
        """

        let result = AutoUpdateService.parseChecksum(from: checksumText, forFile: "nonexistent.dmg")
        XCTAssertNil(result)
    }

    func testParseChecksumHandlesEmptyText() {
        let result = AutoUpdateService.parseChecksum(from: "", forFile: "some.dmg")
        XCTAssertNil(result)
    }

    func testParseChecksumHandlesExtraWhitespace() {
        let checksumText = "  abc123  Look.Ma.No.Hands.1.5.0.dmg  "

        let result = AutoUpdateService.parseChecksum(from: checksumText, forFile: "Look.Ma.No.Hands.1.5.0.dmg")
        XCTAssertEqual(result, "abc123")
    }

    // MARK: - SHA256

    func testSHA256OfKnownContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("sha256-test-\(UUID().uuidString).txt")
        let content = "Hello, World!\n"
        try content.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let hash = try AutoUpdateService.sha256(ofFile: testFile)
        // SHA256 of "Hello, World!\n"
        XCTAssertEqual(hash, "c98c24b677eff44860afea6f493bbaec5bb1c4cbb209c6fc2bbb47f66ff2ad31")
    }

    // MARK: - Update State

    func testInitialStateIsIdle() {
        let service = AutoUpdateService.shared
        XCTAssertEqual(service.state, .idle)
    }
}
