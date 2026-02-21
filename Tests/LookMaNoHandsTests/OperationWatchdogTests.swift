import XCTest
@testable import LookMaNoHands

final class OperationWatchdogTests: XCTestCase {
    override func tearDown() {
        OperationWatchdog.shared.cancelAllWatchdogs()
        super.tearDown()
    }

    func testStartAndCompleteWatchdog() {
        let watchdog = OperationWatchdog.shared
        let id = "unit-test-watchdog"

        watchdog.startWatchdog(id: id, timeout: 0.5, operation: "Unit Test") {}
        XCTAssertTrue(watchdog.hasActiveWatchdog(id: id))

        watchdog.completeOperation(id: id)
        XCTAssertFalse(watchdog.hasActiveWatchdog(id: id))
    }

    func testWatchdogTimeoutFires() {
        let watchdog = OperationWatchdog.shared
        let id = "unit-test-timeout"

        let expectation = expectation(description: "timeout fired")
        watchdog.startWatchdog(id: id, timeout: 0.05, operation: "Unit Test Timeout") {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertFalse(watchdog.hasActiveWatchdog(id: id))
    }

    func testWithTimeoutThrows() async {
        let watchdog = OperationWatchdog.shared
        do {
            _ = try await watchdog.withTimeout(0.05, operation: "sleep") {
                try await Task.sleep(nanoseconds: 200_000_000)
                return true
            }
            XCTFail("Expected timeout")
        } catch let error as TimeoutError {
            XCTAssertEqual(error.operation, "sleep")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWithTimeoutReturnsResult() async throws {
        let watchdog = OperationWatchdog.shared
        let value = try await watchdog.withTimeout(1.0, operation: "fast") {
            return "ok"
        }
        XCTAssertEqual(value, "ok")
    }
}
