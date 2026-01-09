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
