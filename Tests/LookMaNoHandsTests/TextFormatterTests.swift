import XCTest
@testable import LookMaNoHands

final class TextFormatterTests: XCTestCase {
    func testFormatTrimsWhitespaceAndFixesCommonErrors() {
        let formatter = TextFormatter()
        formatter.applyVocabulary = false
        formatter.smartCapitalization = false
        formatter.addFinalPunctuation = false

        let input = "  i dont  know  ,  "
        let output = formatter.format(input)

        XCTAssertEqual(output, "i don't know,")
    }

    func testVocabularyReplacementUsesWordBoundariesAndIsCaseInsensitive() {
        let settings = Settings.shared
        let originalVocabulary = settings.customVocabulary
        defer { settings.customVocabulary = originalVocabulary }

        settings.customVocabulary = [
            VocabularyEntry(phrase: "api", replacement: "API", enabled: true),
            VocabularyEntry(phrase: "foo", replacement: "bar", enabled: true),
        ]

        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.trimWhitespace = false

        let output = formatter.format("Foo football api apis")

        XCTAssertEqual(output, "bar football API apis")
    }

    // MARK: - Whisper Artifact Removal

    func testRemoveWhisperArtifactsStripsBlankAudio() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let output = formatter.format("Hello [BLANK_AUDIO] world")
        XCTAssertEqual(output, "Hello world")
    }

    func testRemoveWhisperArtifactsStripsMusicMarker() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let output = formatter.format("The meeting started [MUSIC] and then continued")
        XCTAssertEqual(output, "The meeting started and then continued")
    }

    func testRemoveWhisperArtifactsPreservesCleanText() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let input = "This is perfectly normal text"
        let output = formatter.format(input)
        XCTAssertEqual(output, input)
    }

    // MARK: - Repeated Phrase Removal

    func testRemoveRepeatedPhrasesCollapsesImmediateRepetition() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let output = formatter.format("I don't know if this is right. I don't know if this is right.")
        XCTAssertEqual(output, "I don't know if this is right.")
    }

    func testRemoveRepeatedPhrasesHandlesMultipleRepetitions() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let output = formatter.format("going to measure that going to measure that going to measure that")
        XCTAssertEqual(output, "going to measure that")
    }

    func testRemoveRepeatedPhrasesPreservesNonRepeatedText() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let input = "The quick brown fox jumps over the lazy dog"
        let output = formatter.format(input)
        XCTAssertEqual(output, input)
    }

    func testCombinedArtifactAndRepetitionRemoval() {
        let formatter = TextFormatter()
        formatter.fixCommonErrors = false
        formatter.applyVocabulary = false

        let output = formatter.format("[BLANK_AUDIO] So the focus is right. So the focus is right. [MUSIC]")
        XCTAssertEqual(output, "So the focus is right.")
    }
}
