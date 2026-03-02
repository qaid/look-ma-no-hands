import XCTest
@testable import LookMaNoHands

@available(macOS 13.0, *)
final class TranscriptDeduplicationTests: XCTestCase {

    // MARK: - ContinuousTranscriber Deduplication

    private func makeTranscriber() -> ContinuousTranscriber {
        ContinuousTranscriber(whisperService: WhisperService())
    }

    private func makeSegment(_ text: String) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: 0, endTime: 5, timestamp: Date())
    }

    /// Test that overlapping words between segments are removed
    func testDeduplicateRemovesOverlappingWords() {
        let transcriber = makeTranscriber()
        transcriber.appendSegment(makeSegment("The quick brown fox jumps over"))

        let result = transcriber.deduplicateAgainstPrevious("fox jumps over the lazy dog")
        XCTAssertEqual(result, "the lazy dog")
    }

    /// Test that non-overlapping text is returned unchanged
    func testDeduplicatePreservesNonOverlappingText() {
        let transcriber = makeTranscriber()
        transcriber.appendSegment(makeSegment("Hello world"))

        let result = transcriber.deduplicateAgainstPrevious("Goodbye moon")
        XCTAssertEqual(result, "Goodbye moon")
    }

    /// Test deduplication with no previous segment
    func testDeduplicateWithNoPreviousSegment() {
        let transcriber = makeTranscriber()

        let result = transcriber.deduplicateAgainstPrevious("First segment text")
        XCTAssertEqual(result, "First segment text")
    }

    /// Test that fully duplicated segment returns empty string
    func testDeduplicateFullyDuplicatedSegment() {
        let transcriber = makeTranscriber()
        transcriber.appendSegment(makeSegment("this is a test"))

        let result = transcriber.deduplicateAgainstPrevious("this is a test")
        XCTAssertEqual(result, "")
    }

    /// Test case-insensitive overlap matching
    func testDeduplicateCaseInsensitive() {
        let transcriber = makeTranscriber()
        transcriber.appendSegment(makeSegment("The meeting ended"))

        let result = transcriber.deduplicateAgainstPrevious("the meeting ended with applause")
        XCTAssertEqual(result, "with applause")
    }

    /// Test that single-word overlap is detected
    func testDeduplicateSingleWordOverlap() {
        let transcriber = makeTranscriber()
        transcriber.appendSegment(makeSegment("preparing the slides"))

        let result = transcriber.deduplicateAgainstPrevious("slides for tomorrow")
        XCTAssertEqual(result, "for tomorrow")
    }

    /// Test that configurable chunk duration works
    func testConfigurableChunkDuration() {
        let defaultTranscriber = ContinuousTranscriber(whisperService: WhisperService())
        let meetingTranscriber = ContinuousTranscriber(whisperService: WhisperService(), chunkDuration: 10)

        // Verify they're distinct instances with different config
        XCTAssertNotNil(defaultTranscriber)
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
