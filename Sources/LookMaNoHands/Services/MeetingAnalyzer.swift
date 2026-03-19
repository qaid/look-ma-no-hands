import Foundation

/// Thread-safe counter for tracking streamed character counts
final class CharCounter: @unchecked Sendable {
    private(set) var total = 0
    func add(_ count: Int) { total += count }
}

/// Service for analyzing meeting transcripts and generating structured notes
/// Uses Ollama LLM to extract key information from raw transcripts
class MeetingAnalyzer: @unchecked Sendable {

    /// Holds the split system/user parts of an LLM prompt
    struct SplitPrompt {
        let system: String
        let prompt: String
    }

    // MARK: - Properties

    /// Context window size for Ollama requests (16K tokens handles most meeting transcripts)
    private static let defaultContextSize = 16384

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

    /// Instruction suffix appended when transcript contains speaker diarization markers
    static let diarizationInstructionSuffix = """

SPEAKER DIARIZATION RULES: The transcript uses the following markers for speaker attribution:
- [Me] — spoken by the local user (the person who recorded this meeting)
- [Mac OS] (or [Remote] in older recordings) — spoken by one or more remote participants
- [SPEAKER_CHANGE] — a likely turn change among remote participants (a pause was detected)

When attributing speech:
1. [Me] always refers to the local user recording the meeting.
2. [SPEAKER_CHANGE] inside a [Mac OS] block suggests a new speaker may have started — but not every change means a new person; use context to decide.
3. Infer speaker names from greetings, introductions, or context clues in the transcript when possible.
4. Assign consistent labels throughout (e.g., if "Sarah" is introduced, use "Sarah" not "Remote Speaker 1" afterwards).
5. Fall back to "Remote Speaker 1", "Remote Speaker 2", etc. when names are not identifiable.
6. Do not manufacture content — only attribute what is clearly in the transcript.
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

        // Append diarization instructions when speaker markers are present
        let hasDiarization = transcript.contains("[Me]") || transcript.contains("[Mac OS]") || transcript.contains("[Remote]")
        if hasDiarization {
            system += diarizationInstructionSuffix
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

    /// Validate transcript, configure model, build split prompt, and check Ollama availability.
    /// Shared preamble for both streaming and non-streaming analysis paths.
    private func prepareAnalysis(
        transcript: String,
        customPrompt: String?,
        model: String?,
        label: String
    ) async throws -> SplitPrompt {
        guard !transcript.isEmpty else {
            throw AnalysisError.emptyTranscript
        }

        ollamaService.modelName = model ?? Settings.shared.ollamaModel

        let prompt = customPrompt ?? Settings.shared.meetingPrompt
        let splitPrompt = Self.buildSplitPrompt(prompt: prompt, transcript: transcript, modelName: ollamaService.modelName)

        print("MeetingAnalyzer: Starting \(label) analysis with \(ollamaService.modelName) model...")

        guard await ollamaService.isAvailable() else {
            throw AnalysisError.ollamaUnavailable
        }

        return splitPrompt
    }

    /// Analyze a meeting transcript and generate structured notes
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - customPrompt: Optional custom prompt (defaults to Settings.meetingPrompt)
    ///   - model: Optional Ollama model name (defaults to Settings.shared.ollamaModel)
    /// - Returns: Structured meeting notes in markdown format
    func analyzeMeeting(transcript: String, customPrompt: String? = nil, model: String? = nil) async throws -> String {
        let splitPrompt = try await prepareAnalysis(transcript: transcript, customPrompt: customPrompt, model: model, label: "")

        let structuredNotes = try await ollamaService.generate(prompt: splitPrompt.prompt, system: splitPrompt.system, numCtx: Self.defaultContextSize)

        print("MeetingAnalyzer: Analysis complete, generated \(structuredNotes.count) characters")
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
        onProgress: @Sendable @escaping (Int, String) async -> Void
    ) async throws -> String {
        let splitPrompt = try await prepareAnalysis(transcript: transcript, customPrompt: customPrompt, model: model, label: "streaming")

        let charCounter = CharCounter()
        let structuredNotes = try await ollamaService.generateStreaming(prompt: splitPrompt.prompt, system: splitPrompt.system, numCtx: Self.defaultContextSize) { chunk in
            charCounter.add(chunk.count)
            await onProgress(charCounter.total, chunk)
        }

        print("MeetingAnalyzer: Streaming analysis complete, generated \(structuredNotes.count) characters")
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
