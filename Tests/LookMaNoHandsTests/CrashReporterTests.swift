import XCTest
@testable import LookMaNoHands

final class CrashReporterTests: XCTestCase {
    func testCrashReportRedactsLastTranscription() throws {
        let reporter = CrashReporter.shared
        reporter.deleteAllCrashReports()

        reporter.updateTranscriptionState(segmentsCount: 2, lastTranscription: "secret words")
        reporter.writeCrashReport(signal: nil, exception: nil)

        guard let report = reporter.getLastCrashReport() else {
            return XCTFail("Expected crash report to be written")
        }

        XCTAssertTrue(report.content.contains("Last Transcription: [REDACTED]"))
        XCTAssertFalse(report.content.contains("secret words"))

        reporter.deleteAllCrashReports()
    }

    func testSavedStateRoundTrip() throws {
        let reporter = CrashReporter.shared
        reporter.updateRecordingState(isRecording: true, bufferSamples: 123)
        reporter.updateTranscriptionState(segmentsCount: 3, lastTranscription: "hello")
        reporter.updateMemoryUsage(456)

        guard let state = reporter.loadSavedState() else {
            return XCTFail("Expected saved state to load")
        }

        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.audioBufferSamples, 123)
        XCTAssertEqual(state.transcriptionSegmentsCount, 3)
        XCTAssertEqual(state.lastTranscription, "hello")
        // Memory usage is not persisted to disk (saveStateToDisk isn't called for memory updates)
        XCTAssertEqual(state.memoryUsageMB, 0)

        let stateFile = reporter.crashDirectoryURL.appendingPathComponent("app-state.json")
        try? FileManager.default.removeItem(at: stateFile)
    }
}
