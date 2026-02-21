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
}
