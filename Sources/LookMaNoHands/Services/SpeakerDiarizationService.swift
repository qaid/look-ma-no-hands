import Foundation

/// Service for identifying different speakers in meeting transcripts
/// Uses LLM-based analysis to distinguish speakers based on linguistic patterns
@available(macOS 13.0, *)
class SpeakerDiarizationService {

    // MARK: - Properties

    private let ollamaService: OllamaService

    // MARK: - Initialization

    init(ollamaService: OllamaService) {
        self.ollamaService = ollamaService
    }

    // MARK: - Public Methods

    /// Analyze transcript segments and assign speaker labels
    /// - Parameter segments: Array of transcript segments to analyze
    /// - Returns: Diarization result with speaker-labeled segments
    func diarizeSegments(_ segments: [TranscriptSegment]) async throws -> DiarizationResult {
        guard !segments.isEmpty else {
            print("SpeakerDiarizationService: No segments to diarize")
            return DiarizationResult(
                segments: segments,
                speakers: [],
                confidence: .low
            )
        }

        // Skip diarization for very short meetings (< 1 minute)
        let totalDuration = segments.last?.endTime ?? 0
        if totalDuration < 60 {
            print("SpeakerDiarizationService: Meeting too short (\(totalDuration)s), using fallback")
            return fallbackDiarization(segments: segments)
        }

        // Check if Ollama is available
        let ollamaAvailable = await ollamaService.isAvailable()
        if !ollamaAvailable {
            print("SpeakerDiarizationService: Ollama unavailable, using fallback")
            return fallbackDiarization(segments: segments)
        }

        do {
            // Build the diarization prompt
            let prompt = buildDiarizationPrompt(segments: segments)

            // Get LLM analysis
            print("SpeakerDiarizationService: Requesting speaker analysis from LLM...")
            let response = try await ollamaService.generate(prompt: prompt)

            // Parse the response
            let result = parseResponse(response, segments: segments)

            print("SpeakerDiarizationService: Diarization complete - \(result.speakers.count) speakers identified")
            return result

        } catch {
            print("SpeakerDiarizationService: LLM analysis failed - \(error), using fallback")
            return fallbackDiarization(segments: segments)
        }
    }

    // MARK: - Prompt Building

    /// Build the prompt for LLM-based speaker diarization
    private func buildDiarizationPrompt(segments: [TranscriptSegment]) -> String {
        // Format segments with indices, timing, and audio source markers
        let segmentList = segments.enumerated().map { index, segment in
            let source = segment.audioSource == .microphone ? "[MIC]" : "[SYSTEM]"
            let timestamp = formatTimestamp(segment.startTime)
            return "[\(index)] \(timestamp) \(source) \(segment.text)"
        }.joined(separator: "\n")

        return """
        /no_think

        Role: You are an expert at speaker diarization - identifying who is speaking when in a multi-speaker transcript.

        Task: Analyze the transcript segments below and identify distinct speakers. The transcript includes timing information and audio source indicators.

        ## Rules

        1. **Local Speaker (Microphone)**: Any segment marked [MIC] is the local user. Always label these as "You".

        2. **Remote Speakers (System Audio)**: Segments marked [SYSTEM] are from remote participants (e.g., in a video call). Identify distinct speakers based on:
           - Turn-taking patterns (who responds to whom)
           - Topic ownership (who drives certain discussions)
           - Linguistic style differences (formal vs casual, technical vs non-technical)
           - Timing gaps (longer pauses often indicate speaker changes)
           - Contextual cues (greetings, sign-offs, introductions)

        3. **Speaker Labels**:
           - Local user: "You"
           - First remote speaker identified: "Speaker 1"
           - Second remote speaker: "Speaker 2"
           - Continue sequentially

        4. **Consistency**: Once you assign a speaker to a pattern, maintain that assignment throughout.

        5. **Ambiguity**: If you cannot confidently distinguish between speakers, it's okay to keep them as the same speaker. Better to under-split than over-split.

        6. **No Names**: Do NOT attempt to guess real names. Use only "You", "Speaker 1", "Speaker 2", etc.

        ## Output Format

        Return a JSON array where each entry maps a segment index to a speaker label:

        [
          {"segment": 0, "speaker": "You"},
          {"segment": 1, "speaker": "Speaker 1"},
          {"segment": 2, "speaker": "Speaker 1"},
          {"segment": 3, "speaker": "You"},
          {"segment": 4, "speaker": "Speaker 2"}
        ]

        ## Transcript Segments

        \(segmentList)

        ## Analysis

        Analyze the segments and return ONLY the JSON mapping. Do not include any other text.
        """
    }

    /// Format a timestamp for display (MM:SS)
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Response Parsing

    /// Parse LLM response into speaker assignments
    private func parseResponse(_ response: String, segments: [TranscriptSegment]) -> DiarizationResult {
        // Extract JSON from response (LLM might include extra text)
        guard let jsonRange = extractJSONRange(from: response) else {
            print("SpeakerDiarizationService: No valid JSON found in response, using fallback")
            return fallbackDiarization(segments: segments)
        }

        let jsonString = String(response[jsonRange])

        do {
            // Parse JSON
            struct SegmentSpeaker: Codable {
                let segment: Int
                let speaker: String
            }

            let data = jsonString.data(using: .utf8) ?? Data()
            let assignments = try JSONDecoder().decode([SegmentSpeaker].self, from: data)

            // Apply speaker labels to segments
            var labeledSegments = segments
            var speakerMap: [String: SpeakerIdentity] = [:]

            for assignment in assignments {
                guard assignment.segment < labeledSegments.count else { continue }

                labeledSegments[assignment.segment].speakerLabel = assignment.speaker

                // Track speaker identities
                let isLocal = assignment.speaker == "You"
                if speakerMap[assignment.speaker] == nil {
                    speakerMap[assignment.speaker] = SpeakerIdentity(
                        label: assignment.speaker,
                        isLocalSpeaker: isLocal,
                        segmentIndices: [],
                        characteristicPhrases: []
                    )
                }
                speakerMap[assignment.speaker]?.segmentIndices.append(assignment.segment)

                // Store sample phrases (first 3 per speaker)
                if speakerMap[assignment.speaker]!.characteristicPhrases.count < 3 {
                    speakerMap[assignment.speaker]?.characteristicPhrases.append(
                        labeledSegments[assignment.segment].text
                    )
                }
            }

            let speakers = Array(speakerMap.values).sorted { $0.label < $1.label }
            let confidence: DiarizationConfidence = speakers.count > 2 ? .high : .medium

            return DiarizationResult(
                segments: labeledSegments,
                speakers: speakers,
                confidence: confidence
            )

        } catch {
            print("SpeakerDiarizationService: JSON parsing failed - \(error), using fallback")
            return fallbackDiarization(segments: segments)
        }
    }

    /// Extract JSON array range from LLM response
    private func extractJSONRange(from text: String) -> Range<String.Index>? {
        guard let startIndex = text.firstIndex(of: "["),
              let endIndex = text.lastIndex(of: "]") else {
            return nil
        }

        // Ensure start comes before end
        guard startIndex < endIndex else {
            return nil
        }

        // Convert closed range to half-open range
        let nextIndex = text.index(after: endIndex)
        return startIndex..<nextIndex
    }

    // MARK: - Fallback Diarization

    /// Simple heuristic-based diarization when LLM is unavailable
    private func fallbackDiarization(segments: [TranscriptSegment]) -> DiarizationResult {
        var labeledSegments = segments
        var speakerMap: [String: SpeakerIdentity] = [:]

        for (index, segment) in labeledSegments.enumerated() {
            let label = segment.audioSource == .microphone ? "You" : "Speaker 1"
            labeledSegments[index].speakerLabel = label

            // Track speaker identities
            let isLocal = segment.audioSource == .microphone
            if speakerMap[label] == nil {
                speakerMap[label] = SpeakerIdentity(
                    label: label,
                    isLocalSpeaker: isLocal,
                    segmentIndices: [],
                    characteristicPhrases: []
                )
            }
            speakerMap[label]?.segmentIndices.append(index)

            // Store sample phrases
            if speakerMap[label]!.characteristicPhrases.count < 3 {
                speakerMap[label]?.characteristicPhrases.append(segment.text)
            }
        }

        let speakers = Array(speakerMap.values).sorted { $0.label < $1.label }

        return DiarizationResult(
            segments: labeledSegments,
            speakers: speakers,
            confidence: .low
        )
    }
}
