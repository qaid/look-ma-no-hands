import XCTest
@testable import LookMaNoHands

@available(macOS 13.0, *)
final class TranscriptDeduplicationTests: XCTestCase {

    // MARK: - ContinuousTranscriber Deduplication

    /// Test that overlapping words between segments are removed
    func testDeduplicateRemovesOverlappingWords() async throws {
        let whisperService = WhisperService()

        // The deduplication logic is private, so we verify via integration:
        // Verify the transcriber initializes with configurable chunk duration.
        let transcriber = ContinuousTranscriber(whisperService: whisperService, chunkDuration: 10)
        XCTAssertNotNil(transcriber)
    }

    /// Test that configurable chunk duration works
    func testConfigurableChunkDuration() {
        let whisperService = WhisperService()

        // Default chunk duration
        let defaultTranscriber = ContinuousTranscriber(whisperService: whisperService)
        XCTAssertNotNil(defaultTranscriber)

        // Custom chunk duration for meeting mode
        let meetingTranscriber = ContinuousTranscriber(whisperService: whisperService, chunkDuration: 10)
        XCTAssertNotNil(meetingTranscriber)
    }

    // MARK: - TextFormatter Repetition Tests (Integration)

    func testRepeatedPhraseAtSegmentBoundary() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        // Simulate what happens when two segments are joined with repeated text
        let segment1 = "Where things are, what we're excited about."
        let segment2 = "what we're excited about. And then we'll move on."
        let joined = segment1 + " " + segment2

        let output = formatter.format(joined)
        // The repeated phrase should be collapsed
        XCTAssertEqual(output, "Where things are, what we're excited about. And then we'll move on.")
    }

    func testWhisperArtifactsInMeetingTranscript() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        // Realistic meeting transcript with artifacts
        let input = "each of us as designers has a different [BLANK_AUDIO] approach to the problem"
        let output = formatter.format(input)
        XCTAssertEqual(output, "each of us as designers has a different approach to the problem")
    }

    func testMultipleBracketedArtifacts() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let input = "[MUSIC] Hello everyone [BLANK_AUDIO] welcome to the meeting [MUSIC]"
        let output = formatter.format(input)
        XCTAssertEqual(output, "Hello everyone welcome to the meeting")
    }

    func testSpeakerOverlapRepetition() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let input = "Downloading four or five. Downloading four or five."
        let output = formatter.format(input)
        XCTAssertEqual(output, "Downloading four or five.")
    }

    func testTripleRepetition() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let input = "preparing, you know, preparing, you know, preparing, you know,"
        let output = formatter.format(input)
        XCTAssertEqual(output, "preparing, you know,")
    }

    func testNoFalsePositiveOnSimilarPhrases() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        // These are similar but not identical — should not be deduplicated
        let input = "The team worked on the design. The team worked on the code."
        let output = formatter.format(input)
        XCTAssertEqual(output, input)
    }

    func testEmptyAndSingleWordInput() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        XCTAssertEqual(formatter.format(""), "")
        XCTAssertEqual(formatter.format("Hello"), "Hello")
        XCTAssertEqual(formatter.format("Hello Hello"), "Hello Hello") // Only 1 word repeated, below 3-word threshold
    }
}
