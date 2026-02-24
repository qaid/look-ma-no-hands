import XCTest
@testable import LookMaNoHands

final class MeetingAnalyzerTests: XCTestCase {
    final class MockOllamaService: OllamaService {
        var lastPrompt: String?
        var unloadCalled = false

        override func isAvailable() async -> Bool {
            true
        }

        override func generate(prompt: String) async throws -> String {
            lastPrompt = prompt
            return "notes"
        }

        override func generateStreaming(prompt: String, onChunk: @escaping (String) async -> Void) async throws -> String {
            lastPrompt = prompt
            await onChunk("notes")
            return "notes"
        }

        override func unloadModel() async {
            unloadCalled = true
        }
    }

    func testAnalyzeMeetingUsesCustomModel() async throws {
        let mockService = MockOllamaService(modelName: "default")
        let analyzer = MeetingAnalyzer(ollamaService: mockService)

        _ = try await analyzer.analyzeMeeting(
            transcript: "Hello team",
            customPrompt: "Custom prompt",
            model: "custom:1"
        )

        XCTAssertEqual(mockService.modelName, "custom:1")
        XCTAssertTrue(mockService.unloadCalled)
        XCTAssertNotNil(mockService.lastPrompt)
    }

    func testAnalyzeMeetingStreamingUsesDefaultModelWhenNil() async throws {
        let mockService = MockOllamaService(modelName: "default")
        let analyzer = MeetingAnalyzer(ollamaService: mockService)

        let settings = Settings.shared
        let originalModel = settings.ollamaModel
        settings.ollamaModel = "fallback:2"
        defer { settings.ollamaModel = originalModel }

        var progressCalls = 0
        _ = try await analyzer.analyzeMeetingStreaming(
            transcript: "Hello team",
            customPrompt: "Custom prompt",
            model: nil
        ) { _, _ in
            progressCalls += 1
        }

        XCTAssertEqual(mockService.modelName, "fallback:2")
        XCTAssertTrue(mockService.unloadCalled)
        XCTAssertGreaterThanOrEqual(progressCalls, 1)
    }
}
