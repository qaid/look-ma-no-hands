import Foundation

/// Rule-based text formatter that cleans up transcribed text
/// No AI required - uses deterministic rules for fast, predictable formatting
class TextFormatter {

    // MARK: - Configuration

    /// Whether to enable smart capitalization
    /// NOTE: This should stay FALSE for dictation - TextInsertionService handles capitalization context-aware
    var smartCapitalization = false

    /// Whether to add punctuation at the end if missing
    /// NOTE: This should stay FALSE for dictation - TextInsertionService handles punctuation context-aware
    var addFinalPunctuation = false

    /// Whether to fix common transcription errors
    var fixCommonErrors = true

    /// Whether to trim excessive whitespace
    var trimWhitespace = true

    /// Whether to apply custom vocabulary replacements
    var applyVocabulary = true

    /// Whether to remove Whisper hallucination artifacts ([BLANK_AUDIO], [MUSIC], etc.)
    var removeArtifacts = true

    /// Whether to remove immediately-repeated phrases
    var removeRepetitions = true

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

        // 2. Remove Whisper hallucination artifacts
        if removeArtifacts {
            result = removeWhisperArtifacts(result)
        }

        // 3. Remove immediately-repeated phrases
        if removeRepetitions {
            result = removeRepeatedPhrases(result)
        }

        // 4. Fix common transcription errors
        if fixCommonErrors {
            result = fixCommonTranscriptionErrors(result)
        }

        // 5. Apply custom vocabulary replacements
        if applyVocabulary {
            result = applyVocabularyReplacements(result)
        }

        // 6. Smart capitalization
        if smartCapitalization {
            result = applySmartCapitalization(result)
        }

        // 7. Add final punctuation if missing
        if addFinalPunctuation {
            result = ensureFinalPunctuation(result)
        }

        return result
    }

    // MARK: - Private Helpers

    /// Remove common Whisper hallucination artifacts
    private func removeWhisperArtifacts(_ text: String) -> String {
        let artifacts = ["[BLANK_AUDIO]", "[MUSIC]", "(mumbles)", "(overlapping chatter)",
                         "[silence]"]
        var result = text
        for artifact in artifacts {
            result = result.replacingOccurrences(of: artifact, with: "", options: .caseInsensitive)
        }
        // Collapse resulting double-spaces and trim
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove immediately-repeated phrases (e.g., "the focus. the focus." → "the focus.")
    /// Uses word-level matching: captures 3+ words and removes immediate repetition.
    private func removeRepeatedPhrases(_ text: String) -> String {
        // Match 3-9 word sequences that are immediately repeated (capped to avoid slow matching on long text)
        let pattern = "\\b((?:\\S+\\s+){2,8}\\S+)(\\s+\\1)+"
        var result = text
        var previous = ""
        // Iterate since removing one repetition may reveal another
        while result != previous {
            previous = result
            result = result.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }
        return result
    }

    /// Apply custom vocabulary replacements from user settings
    /// Only entries with a non-empty `phrase` get regex replacement
    private func applyVocabularyReplacements(_ text: String) -> String {
        let entries = Settings.shared.customVocabulary.filter { $0.enabled && !$0.phrase.isEmpty }
        guard !entries.isEmpty else { return text }

        var result = text
        for entry in entries {
            // Use word-boundary regex for the misheard phrase
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.phrase))\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: entry.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

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
                formatter.removeArtifacts = true
                formatter.removeRepetitions = false

            case .standard:
                formatter.smartCapitalization = false  // Context-aware in TextInsertionService
                formatter.addFinalPunctuation = false  // Context-aware in TextInsertionService
                formatter.fixCommonErrors = true
                formatter.trimWhitespace = true
                formatter.removeArtifacts = true
                formatter.removeRepetitions = true

            case .maximum:
                formatter.smartCapitalization = false  // Context-aware in TextInsertionService
                formatter.addFinalPunctuation = false  // Context-aware in TextInsertionService
                formatter.fixCommonErrors = true
                formatter.trimWhitespace = true
                formatter.removeArtifacts = true
                formatter.removeRepetitions = true
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
