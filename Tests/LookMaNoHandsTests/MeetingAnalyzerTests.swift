import XCTest
@testable import LookMaNoHands

final class MeetingAnalyzerTests: XCTestCase {
    final class MockOllamaService: OllamaService {
        var lastPrompt: String?
        var lastSystem: String?
        var unloadCalled = false

        override func isAvailable() async -> Bool {
            true
        }

        override func generate(prompt: String, system: String? = nil, numCtx: Int? = nil) async throws -> String {
            lastPrompt = prompt
            lastSystem = system
            return "notes"
        }

        override func generateStreaming(prompt: String, system: String? = nil, numCtx: Int? = nil, onChunk: @escaping (String) async -> Void) async throws -> String {
            lastPrompt = prompt
            lastSystem = system
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

    // MARK: - buildSplitPrompt

    func testBuildSplitPromptSplitsAtPlaceholder() {
        let prompt = "You are an assistant.\n\n## Transcript\n[TRANSCRIPTION_PLACEHOLDER]\n\nNow produce notes."
        let transcript = "Hello team"

        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: "llama3.1:8b")

        XCTAssertTrue(split.system.contains("You are an assistant."))
        XCTAssertFalse(split.system.contains("[TRANSCRIPTION_PLACEHOLDER]"))
        XCTAssertFalse(split.system.contains("Hello team"))
        XCTAssertTrue(split.prompt.contains("Hello team"))
        XCTAssertTrue(split.prompt.contains("Now produce notes."))
    }

    func testBuildSplitPromptFallbackWhenNoPlaceholder() {
        let prompt = "Summarize this"
        let transcript = "Hello team"

        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: "llama3.1:8b")

        XCTAssertEqual(split.system, "Summarize this")
        XCTAssertEqual(split.prompt, transcript)
    }

    func testBuildSplitPromptIncludesNoteInstructionWhenMarkersPresent() {
        let transcript = "Hello team\n\n[USER NOTE @ 01:30] Check timeline\n\nLet's continue"
        let prompt = "Analyze this meeting"

        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: "llama3.1:8b")

        XCTAssertTrue(split.system.contains("## My Notes"))
        XCTAssertTrue(split.prompt.contains("[USER NOTE @"))
        XCTAssertTrue(split.system.contains("Analyze this meeting"))
    }

    func testBuildSplitPromptIncludesNoteInstructionInSystemWithPlaceholder() {
        let transcript = "Hello team\n\n[USER NOTE @ 01:30] Check timeline\n\nLet's continue"
        let prompt = "You are an assistant.\n\n## Transcript\n[TRANSCRIPTION_PLACEHOLDER]\n\nNow produce notes."

        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: "llama3.1:8b")

        // Note instruction should land in system, not user prompt
        XCTAssertTrue(split.system.contains("## My Notes"))
        XCTAssertTrue(split.system.contains("You are an assistant."))
        XCTAssertTrue(split.prompt.contains("[USER NOTE @"))
        XCTAssertTrue(split.prompt.contains("Now produce notes."))
    }

    func testBuildSplitPromptOmitsNoteInstructionWhenNoMarkers() {
        let transcript = "Hello team\n\nLet's continue"
        let prompt = "Analyze this meeting"

        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: "llama3.1:8b")

        XCTAssertFalse(split.system.contains("## My Notes"))
        XCTAssertTrue(split.system.contains("Analyze this meeting"))
        XCTAssertTrue(split.prompt.contains(transcript))
    }

    // MARK: - /no_think stripping

    func testNoThinkStrippedForLlama() {
        let prompt = "/no_think\n\nYou are an assistant."
        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: "t", modelName: "llama3.1:8b")
        XCTAssertFalse(split.system.hasPrefix("/no_think"))
        XCTAssertTrue(split.system.contains("You are an assistant."))
    }

    func testNoThinkKeptForQwen() {
        let prompt = "/no_think\n\nYou are an assistant."
        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: "t", modelName: "qwen2.5:3b")
        XCTAssertTrue(split.system.hasPrefix("/no_think"))
    }

    func testNoThinkKeptForDeepSeek() {
        let prompt = "/no_think\n\nYou are an assistant."
        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: "t", modelName: "deepseek-r1:8b")
        XCTAssertTrue(split.system.hasPrefix("/no_think"))
    }

    func testNoThinkKeptForNamespacedDeepSeek() {
        let prompt = "/no_think\n\nYou are an assistant."
        let split = MeetingAnalyzer.buildSplitPrompt(prompt: prompt, transcript: "t", modelName: "huggingface/deepseek-r1:8b")
        XCTAssertTrue(split.system.hasPrefix("/no_think"))
    }

    // MARK: - system parameter passed to Ollama

    func testSystemParameterPassedToOllamaGenerate() async throws {
        let mockService = MockOllamaService(modelName: "llama3.1:8b")
        let analyzer = MeetingAnalyzer(ollamaService: mockService)

        _ = try await analyzer.analyzeMeeting(
            transcript: "Discussion\n\n[USER NOTE @ 02:00] Important point",
            customPrompt: "Summarize",
            model: "llama3.1:8b"
        )

        XCTAssertNotNil(mockService.lastSystem)
        XCTAssertTrue(mockService.lastSystem!.contains("Summarize"))
        XCTAssertTrue(mockService.lastSystem!.contains("## My Notes"))
        XCTAssertTrue(mockService.lastPrompt!.contains("[USER NOTE @ 02:00] Important point"))
    }

    func testSystemParameterPassedToOllamaStreaming() async throws {
        let mockService = MockOllamaService(modelName: "llama3.1:8b")
        let analyzer = MeetingAnalyzer(ollamaService: mockService)

        _ = try await analyzer.analyzeMeetingStreaming(
            transcript: "Discussion",
            customPrompt: "Summarize",
            model: "llama3.1:8b"
        ) { _, _ in }

        XCTAssertNotNil(mockService.lastSystem)
        XCTAssertTrue(mockService.lastSystem!.contains("Summarize"))
    }
}
