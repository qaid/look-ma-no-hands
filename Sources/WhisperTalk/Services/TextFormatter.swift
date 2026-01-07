import Foundation

/// Rule-based text formatter that cleans up transcribed text
/// No AI required - uses deterministic rules for fast, predictable formatting
class TextFormatter {

    // MARK: - Configuration

    /// Whether to enable smart capitalization
    var smartCapitalization = true

    /// Whether to add punctuation at the end if missing
    var addFinalPunctuation = true

    /// Whether to fix common transcription errors
    var fixCommonErrors = true

    /// Whether to trim excessive whitespace
    var trimWhitespace = true

    // MARK: - Public Methods

    /// Format transcribed text with rule-based processing
    /// - Parameter text: Raw transcribed text from Whisper
    /// - Returns: Cleaned and formatted text
    func format(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // 1. Trim whitespace
        if trimWhitespace {
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        // 2. Fix common transcription errors
        if fixCommonErrors {
            result = fixCommonTranscriptionErrors(result)
        }

        // 3. Smart capitalization
        if smartCapitalization {
            result = applySmartCapitalization(result)
        }

        // 4. Add final punctuation if missing
        if addFinalPunctuation {
            result = ensureFinalPunctuation(result)
        }

        return result
    }

    // MARK: - Private Helpers

    /// Fix common transcription errors that Whisper makes
    private func fixCommonTranscriptionErrors(_ text: String) -> String {
        var result = text

        // Common homophones and transcription mistakes
        let corrections: [(pattern: String, replacement: String)] = [
            // Contractions that might be transcribed as two words
            ("\\bcan not\\b", "cannot"),
            ("\\bwont\\b", "won't"),
            ("\\bdont\\b", "don't"),
            ("\\bdidnt\\b", "didn't"),
            ("\\bwasnt\\b", "wasn't"),
            ("\\bisnt\\b", "isn't"),
            ("\\barent\\b", "aren't"),
            ("\\bhavent\\b", "haven't"),
            ("\\bhasnt\\b", "hasn't"),
            ("\\bhadnt\\b", "hadn't"),
            ("\\bwouldnt\\b", "wouldn't"),
            ("\\bshouldnt\\b", "shouldn't"),
            ("\\bcouldnt\\b", "couldn't"),
            ("\\bmustnt\\b", "mustn't"),

            // Common phrase corrections
            ("\\ba lot\\b", "a lot"), // Fix spacing
            ("\\bal ot\\b", "a lot"),

            // Fix spaces before punctuation
            ("\\s+([,\\.!?;:])", "$1"),

            // Fix double spaces
            ("  +", " "),
        ]

        for (pattern, replacement) in corrections {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    /// Apply smart capitalization rules
    private func applySmartCapitalization(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Capitalize first letter
        result = result.prefix(1).uppercased() + result.dropFirst()

        // Capitalize after sentence-ending punctuation (., !, ?)
        let sentencePattern = "([.!?])\\s+(\\w)"
        if let regex = try? NSRegularExpression(pattern: sentencePattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)

            // Process in reverse to maintain indices
            for match in matches.reversed() {
                if match.numberOfRanges >= 3 {
                    let letterRange = match.range(at: 2)
                    if let swiftRange = Range(letterRange, in: result) {
                        let letter = result[swiftRange]
                        result.replaceSubrange(swiftRange, with: letter.uppercased())
                    }
                }
            }
        }

        // Capitalize "I" when used as a pronoun
        result = result.replacingOccurrences(
            of: "\\bi\\b",
            with: "I",
            options: .regularExpression
        )

        return result
    }

    /// Ensure the text ends with appropriate punctuation
    private func ensureFinalPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let lastChar = text.last!

        // Already has punctuation
        if ".,!?;:".contains(lastChar) {
            return text
        }

        // Detect if it's a question (simple heuristic)
        let questionWords = ["what", "where", "when", "why", "who", "how", "which", "whose", "whom"]
        let lowercased = text.lowercased()

        for word in questionWords {
            if lowercased.hasPrefix(word + " ") {
                return text + "?"
            }
        }

        // Default to period
        return text + "."
    }
}

// MARK: - Convenience Extensions

extension TextFormatter {
    /// Common presets for different use cases
    enum Preset {
        /// Minimal formatting - just clean up whitespace
        case minimal
        /// Standard formatting - capitalization, punctuation, basic fixes
        case standard
        /// Maximum formatting - all rules enabled
        case maximum

        func configure(_ formatter: TextFormatter) {
            switch self {
            case .minimal:
                formatter.smartCapitalization = false
                formatter.addFinalPunctuation = false
                formatter.fixCommonErrors = false
                formatter.trimWhitespace = true

            case .standard:
                formatter.smartCapitalization = true
                formatter.addFinalPunctuation = true
                formatter.fixCommonErrors = true
                formatter.trimWhitespace = true

            case .maximum:
                formatter.smartCapitalization = true
                formatter.addFinalPunctuation = true
                formatter.fixCommonErrors = true
                formatter.trimWhitespace = true
            }
        }
    }

    /// Create a formatter with a preset configuration
    static func with(preset: Preset) -> TextFormatter {
        let formatter = TextFormatter()
        preset.configure(formatter)
        return formatter
    }
}
