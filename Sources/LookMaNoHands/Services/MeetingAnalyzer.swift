import Foundation

/// Service for analyzing meeting transcripts and generating structured notes
/// Uses Ollama LLM to extract key information from raw transcripts
@available(macOS 13.0, *)
class MeetingAnalyzer {

    // MARK: - Properties

    private let ollamaService: OllamaService
    private let diarizationService: SpeakerDiarizationService

    // MARK: - Initialization

    init(ollamaService: OllamaService = OllamaService()) {
        self.ollamaService = ollamaService
        self.diarizationService = SpeakerDiarizationService(ollamaService: ollamaService)
    }

    // MARK: - Analysis

    /// Analyze a meeting from transcript segments and generate structured notes
    /// - Parameters:
    ///   - segments: Array of transcript segments with timing and audio source
    ///   - customPrompt: Optional custom prompt (defaults to Settings.meetingPrompt)
    ///   - performDiarization: Whether to identify speakers (default: true)
    /// - Returns: Structured meeting notes in markdown format
    func analyzeMeeting(
        segments: [TranscriptSegment],
        customPrompt: String? = nil,
        performDiarization: Bool = true
    ) async throws -> String {
        guard !segments.isEmpty else {
            throw AnalysisError.emptyTranscript
        }

        // Set the model name first
        ollamaService.modelName = Settings.shared.ollamaModel

        // Optionally perform speaker diarization
        var diarizedSegments = segments
        if performDiarization {
            print("MeetingAnalyzer: Performing speaker diarization...")
            do {
                let result = try await diarizationService.diarizeSegments(segments)
                diarizedSegments = result.segments
                print("MeetingAnalyzer: Diarization complete - \(result.speakers.count) speakers, confidence: \(result.confidence.description)")
            } catch {
                print("MeetingAnalyzer: Diarization failed - \(error), proceeding without speaker labels")
            }
        }

        // Build transcript with speaker labels
        let transcript = buildTranscriptWithSpeakers(diarizedSegments)

        // Get prompt (custom or default)
        let prompt = customPrompt ?? Settings.shared.meetingPrompt

        // Build the full prompt with transcript
        let fullPrompt = """
\(prompt)

# Transcript

\(transcript)
"""

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

    /// Build a formatted transcript with speaker labels and timestamps
    private func buildTranscriptWithSpeakers(_ segments: [TranscriptSegment]) -> String {
        return segments.map { segment in
            let timestamp = formatTimestamp(segment.startTime)
            if let speaker = segment.speakerLabel {
                return "[\(timestamp)] \(speaker): \(segment.text)"
            } else {
                return "[\(timestamp)] \(segment.text)"
            }
        }.joined(separator: "\n")
    }

    /// Format a timestamp for display (MM:SS)
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
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
