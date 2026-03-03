import Foundation

/// Service for analyzing meeting transcripts and generating structured notes
/// Uses Ollama LLM to extract key information from raw transcripts
class MeetingAnalyzer {

    /// Holds the split system/user parts of an LLM prompt
    struct SplitPrompt {
        let system: String
        let prompt: String
    }

    // MARK: - Properties

    private let ollamaService: OllamaService

    // MARK: - Initialization

    init(ollamaService: OllamaService = OllamaService()) {
        self.ollamaService = ollamaService
    }

    // MARK: - Prompt Building

    /// Instruction suffix appended when transcript contains user notes
    static let noteInstructionSuffix = """

IMPORTANT: The transcript contains lines marked with [USER NOTE @ MM:SS]. These are the user's own observations, questions, and action items captured during the meeting. In your output, include a dedicated "## My Notes" section that lists each user note with its timestamp, preserving the user's original wording. Do not mix user notes into the main analysis prose.
"""

    /// Split the prompt into a system role and a user prompt.
    ///
    /// When the prompt template contains `[TRANSCRIPTION_PLACEHOLDER]`:
    ///   - Everything before the marker becomes the `system` instruction.
    ///   - The transcript (plus any text after the marker) becomes the user `prompt`.
    /// When there is no placeholder, the entire prompt becomes `system` and the
    /// transcript alone is sent as the user `prompt`.
    ///
    /// `/no_think` is stripped from the system prompt for models that don't
    /// understand it (i.e. anything that isn't DeepSeek or Qwen).
    static func buildSplitPrompt(prompt: String, transcript: String, modelName: String) -> SplitPrompt {
        let placeholder = "[TRANSCRIPTION_PLACEHOLDER]"
        var system: String
        let userPrompt: String

        if let range = prompt.range(of: placeholder) {
            let before = String(prompt[prompt.startIndex..<range.lowerBound])
            let after = String(prompt[range.upperBound...])
            system = before.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = after.trimmingCharacters(in: .whitespacesAndNewlines)
            userPrompt = suffix.isEmpty ? transcript : "\(transcript)\n\n\(suffix)"
        } else {
            system = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            userPrompt = transcript
        }

        // Append note instructions to system so the LLM always sees them as
        // system-level guidance, regardless of whether a placeholder was used.
        let hasNotes = transcript.contains("[USER NOTE @")
        if hasNotes {
            system += noteInstructionSuffix
        }

        return SplitPrompt(
            system: stripNoThinkIfNeeded(system, modelName: modelName),
            prompt: userPrompt
        )
    }

    /// Strip the `/no_think` prefix from a prompt unless the model name contains DeepSeek or Qwen.
    static func stripNoThinkIfNeeded(_ text: String, modelName: String) -> String {
        let lower = modelName.lowercased()
        let isThinkingModel = lower.contains("deepseek") || lower.contains("qwen")
        guard !isThinkingModel else { return text }
        var result = text
        if result.hasPrefix("/no_think") {
            result = String(result.dropFirst("/no_think".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    // MARK: - Analysis

    /// Analyze a meeting transcript and generate structured notes
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - customPrompt: Optional custom prompt (defaults to Settings.meetingPrompt)
    ///   - model: Optional Ollama model name (defaults to Settings.shared.ollamaModel)
    /// - Returns: Structured meeting notes in markdown format
    func analyzeMeeting(transcript: String, customPrompt: String? = nil, model: String? = nil) async throws -> String {
        guard !transcript.isEmpty else {
            throw AnalysisError.emptyTranscript
        }

        // Set the model name first so buildSplitPrompt can use it for /no_think stripping
        ollamaService.modelName = model ?? Settings.shared.ollamaModel

        let prompt = customPrompt ?? Settings.shared.meetingPrompt
        let splitPrompt = Self.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: ollamaService.modelName)

        print("MeetingAnalyzer: Starting analysis with \(ollamaService.modelName) model...")

        // Check if Ollama is available
        let isAvailable = await ollamaService.isAvailable()
        guard isAvailable else {
            throw AnalysisError.ollamaUnavailable
        }

        // Process with Ollama
        let structuredNotes = try await ollamaService.generate(prompt: splitPrompt.prompt, system: splitPrompt.system, numCtx: 16384)

        print("MeetingAnalyzer: Analysis complete, generated \(structuredNotes.count) characters")

        // Free the model from memory — meeting analysis is a one-shot operation and the
        // model (often 5 GB+) should not stay resident after completion.
        await ollamaService.unloadModel()

        return structuredNotes
    }

    /// Analyze a meeting transcript with streaming progress updates
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - customPrompt: Optional custom prompt (defaults to Settings.meetingPrompt)
    ///   - model: Optional Ollama model name (defaults to Settings.shared.ollamaModel)
    ///   - onProgress: Callback invoked with (character count, chunk text) for each chunk
    /// - Returns: Structured meeting notes in markdown format
    func analyzeMeetingStreaming(
        transcript: String,
        customPrompt: String? = nil,
        model: String? = nil,
        onProgress: @escaping (Int, String) async -> Void
    ) async throws -> String {
        guard !transcript.isEmpty else {
            throw AnalysisError.emptyTranscript
        }

        // Set the model name first so buildSplitPrompt can use it for /no_think stripping
        ollamaService.modelName = model ?? Settings.shared.ollamaModel

        let prompt = customPrompt ?? Settings.shared.meetingPrompt
        let splitPrompt = Self.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: ollamaService.modelName)

        print("MeetingAnalyzer: Starting streaming analysis with \(ollamaService.modelName) model...")

        // Check if Ollama is available
        let isAvailable = await ollamaService.isAvailable()
        guard isAvailable else {
            throw AnalysisError.ollamaUnavailable
        }

        var totalChars = 0

        // Process with Ollama streaming
        let structuredNotes = try await ollamaService.generateStreaming(prompt: splitPrompt.prompt, system: splitPrompt.system, numCtx: 16384) { chunk in
            totalChars += chunk.count
            await onProgress(totalChars, chunk)
        }

        print("MeetingAnalyzer: Streaming analysis complete, generated \(structuredNotes.count) characters")

        // Free the model from memory — meeting analysis is a one-shot operation and the
        // model (often 5 GB+) should not stay resident after completion.
        await ollamaService.unloadModel()

        return structuredNotes
    }

    /// Check if Ollama is available for analysis
    func isAvailable() async -> Bool {
        return await ollamaService.isAvailable()
    }
}

// MARK: - Errors

enum AnalysisError: LocalizedError {
    case emptyTranscript
    case ollamaUnavailable
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Cannot analyze empty transcript"
        case .ollamaUnavailable:
            return "Ollama is not running. Please start Ollama to generate structured notes."
        case .analysisFailed(let message):
            return "Analysis failed: \(message)"
        }
    }
}
