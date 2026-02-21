import Foundation

/// Service for analyzing meeting transcripts and generating structured notes
/// Uses Ollama LLM to extract key information from raw transcripts
class MeetingAnalyzer {

    // MARK: - Properties

    private let ollamaService: OllamaService

    // MARK: - Initialization

    init(ollamaService: OllamaService = OllamaService()) {
        self.ollamaService = ollamaService
    }

    // MARK: - Analysis

    /// Analyze a meeting transcript and generate structured notes
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - customPrompt: Optional custom prompt (defaults to Settings.meetingPrompt)
    /// - Returns: Structured meeting notes in markdown format
    func analyzeMeeting(transcript: String, customPrompt: String? = nil) async throws -> String {
        guard !transcript.isEmpty else {
            throw AnalysisError.emptyTranscript
        }

        // Get prompt (custom or default)
        let prompt = customPrompt ?? Settings.shared.meetingPrompt

        // Build the full prompt with transcript
        let fullPrompt = """
\(prompt)

# Transcript

\(transcript)
"""

        // Set the model name first
        ollamaService.modelName = Settings.shared.ollamaModel

        print("MeetingAnalyzer: Starting analysis with \(ollamaService.modelName) model...")

        // Check if Ollama is available
        let isAvailable = await ollamaService.isAvailable()
        guard isAvailable else {
            throw AnalysisError.ollamaUnavailable
        }

        // Process with Ollama
        let structuredNotes = try await ollamaService.generate(prompt: fullPrompt)

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
    ///   - onProgress: Callback invoked with (character count, chunk text) for each chunk
    /// - Returns: Structured meeting notes in markdown format
    func analyzeMeetingStreaming(
        transcript: String,
        customPrompt: String? = nil,
        onProgress: @escaping (Int, String) async -> Void
    ) async throws -> String {
        guard !transcript.isEmpty else {
            throw AnalysisError.emptyTranscript
        }

        // Get prompt (custom or default)
        let prompt = customPrompt ?? Settings.shared.meetingPrompt

        // Build the full prompt with transcript
        let fullPrompt = """
\(prompt)

# Transcript

\(transcript)
"""

        // Set the model name first
        ollamaService.modelName = Settings.shared.ollamaModel

        print("MeetingAnalyzer: Starting streaming analysis with \(ollamaService.modelName) model...")

        // Check if Ollama is available
        let isAvailable = await ollamaService.isAvailable()
        guard isAvailable else {
            throw AnalysisError.ollamaUnavailable
        }

        var totalChars = 0

        // Process with Ollama streaming
        let structuredNotes = try await ollamaService.generateStreaming(prompt: fullPrompt) { chunk in
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
