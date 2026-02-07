import Foundation
import AppKit
import ApplicationServices

/// Service for inserting text into the currently focused text field
/// Uses multiple strategies to maximize compatibility across applications
class TextInsertionService {
    
    // MARK: - Public Methods
    
    /// Insert text into the currently focused text field
    /// Tries multiple methods in order of preference
    /// - Parameter text: The text to insert (raw transcription)
    /// - Returns: True if insertion was successful
    @discardableResult
    func insertText(_ text: String) -> Bool {
        // First apply basic cleanup
        let cleanedText = basicCleanup(text)

        // Then apply context-aware formatting before insertion
        let formattedText = applyContextAwareFormatting(cleanedText)

        // Strategy 1: Try Accessibility API (cleanest method)
        if insertViaAccessibility(formattedText) {
            print("TextInsertionService: Inserted via Accessibility API")
            return true
        }

        // Strategy 2: Try clipboard + paste (most compatible)
        if insertViaClipboard(formattedText) {
            print("TextInsertionService: Inserted via clipboard paste")
            return true
        }

        // Strategy 3: Copy to clipboard and notify user
        copyToClipboard(formattedText)
        print("TextInsertionService: Text copied to clipboard (manual paste required)")

        return false
    }
    
    // MARK: - Strategy 1: Accessibility API

    private func insertViaAccessibility(_ text: String) -> Bool {
        // Get the focused UI element
        guard let focusedElement = getFocusedElement() else {
            print("TextInsertionService: Could not get focused element")
            return false
        }

        // Check if it's a text field/area
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleValue)

        guard roleResult == .success,
              let role = roleValue as? String,
              role == kAXTextFieldRole || role == kAXTextAreaRole else {
            print("TextInsertionService: Focused element is not a text field")
            return false
        }

        // PRIORITY 1: Try inserting at selection (preserves existing text)
        if insertAtSelection(focusedElement, text: text) {
            return true
        }

        // PRIORITY 2: Fall back to setting value directly (replaces all text)
        // This is a last resort for fields that don't support insertion
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        return setResult == .success
    }
    
    /// Get the currently focused accessibility element
    private func getFocusedElement() -> AXUIElement? {
        // Get the system-wide accessibility element
        let systemWide = AXUIElementCreateSystemWide()
        
        // Get the focused application
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        
        guard appResult == .success,
              let app = focusedApp else {
            return nil
        }
        
        // Get the focused element within the application
        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard elementResult == .success,
              let element = focusedElement else {
            return nil
        }
        
        return (element as! AXUIElement)
    }
    
    /// Insert text at the current selection point
    private func insertAtSelection(_ element: AXUIElement, text: String) -> Bool {
        // Get current value
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )
        
        // Get selection range
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        
        guard valueResult == .success,
              rangeResult == .success,
              let currentText = currentValue as? String else {
            return false
        }
        
        // Convert AXValue to CFRange
        var range = CFRange()
        if let rangeValue = selectedRange {
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
        } else {
            // Append at end if no selection
            range = CFRange(location: currentText.count, length: 0)
        }

        // Clamp range to valid bounds
        let safeLocation = min(range.location, currentText.count)
        let maxLength = currentText.count - safeLocation
        let safeLength = min(range.length, maxLength)

        // Build new text with insertion using safe indices
        guard let startIndex = currentText.index(currentText.startIndex, offsetBy: safeLocation, limitedBy: currentText.endIndex),
              let endIndex = currentText.index(startIndex, offsetBy: safeLength, limitedBy: currentText.endIndex) else {
            // Index calculation failed, fall back to appending
            let newText = currentText + text
            let setResult = AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                newText as CFTypeRef
            )
            return setResult == .success
        }

        var newText = currentText
        newText.replaceSubrange(startIndex..<endIndex, with: text)
        
        // Set the new value
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )
        
        return setResult == .success
    }
    
    // MARK: - Strategy 2: Clipboard + Paste
    
    private func insertViaClipboard(_ text: String) -> Bool {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        let success = simulatePaste()
        
        // Optionally restore previous clipboard content after a delay
        // (This is debatable - some users might want to paste again)
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Only restore if clipboard still contains our text
                if pasteboard.string(forType: .string) == text {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
        
        return success
    }
    
    /// Simulate Cmd+V keystroke
    private func simulatePaste() -> Bool {
        // Create key down event for Cmd+V
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        
        // V key is keycode 9
        let keyCode: CGKeyCode = 9
        
        // Key down with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            return false
        }
        keyDown.flags = .maskCommand
        
        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        keyUp.flags = .maskCommand
        
        // Post the events
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        
        return true
    }
    
    // MARK: - Strategy 3: Copy to Clipboard (Fallback)

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Context Detection (for Whisper prompting)

    /// Get the name of the frontmost application
    /// - Returns: Bundle identifier or app name, or nil if unavailable
    func getFocusedAppName() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            return nil
        }

        // Try to get the app title
        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        if titleResult == .success, let title = titleValue as? String {
            return title
        }

        return nil
    }

    /// Read the last N characters from the currently focused text field
    /// - Parameter maxLength: Maximum number of characters to read from before the cursor
    /// - Returns: Text before the cursor, or nil if unavailable
    func getExistingFieldText(maxLength: Int = 200) -> String? {
        guard let focusedElement = getFocusedElement() else {
            return nil
        }

        // Get current text content
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        guard valueResult == .success, let currentText = currentValue as? String, !currentText.isEmpty else {
            return nil
        }

        // Get cursor position via selection range
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        var cursorPosition = currentText.count
        if rangeResult == .success, let rangeValue = selectedRange {
            var range = CFRange()
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            cursorPosition = min(range.location, currentText.count)
        }

        // Get the last maxLength characters before cursor
        let startOffset = max(0, cursorPosition - maxLength)

        guard let startIndex = currentText.index(currentText.startIndex, offsetBy: startOffset, limitedBy: currentText.endIndex),
              let endIndex = currentText.index(currentText.startIndex, offsetBy: cursorPosition, limitedBy: currentText.endIndex) else {
            return nil
        }

        let beforeCursor = String(currentText[startIndex..<endIndex])
        return beforeCursor.isEmpty ? nil : beforeCursor
    }

    // MARK: - Basic Text Cleanup

    /// Apply basic cleanup to transcribed text without context
    /// Only fixes obvious issues like whitespace and "I" pronoun
    private func basicCleanup(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fix excessive whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Fix spaces before punctuation
        result = result.replacingOccurrences(of: "\\s+([,\\.!?;:])", with: "$1", options: .regularExpression)

        // Capitalize "I" when used as a pronoun
        result = result.replacingOccurrences(of: "\\bi\\b", with: "I", options: .regularExpression)

        return result
    }

    // MARK: - Context-Aware Formatting

    /// Apply context-aware formatting based on surrounding text
    /// Adjusts capitalization and punctuation based on what comes before the cursor
    private func applyContextAwareFormatting(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Get the focused element and its context
        guard let focusedElement = getFocusedElement() else {
            // Can't get context, return text as-is
            return text
        }

        // Get current text content
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        // Get selection range to find cursor position
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard valueResult == .success,
              rangeResult == .success,
              let currentText = currentValue as? String,
              !currentText.isEmpty else {
            // No existing text or can't read it - keep original capitalization
            return text
        }

        // Get cursor position
        var range = CFRange()
        if let rangeValue = selectedRange {
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
        } else {
            // No selection info, assume end of text
            range = CFRange(location: currentText.count, length: 0)
        }

        // Analyze context before cursor
        let context = analyzeContext(currentText, cursorPosition: range.location)

        var result = text

        // Adjust capitalization based on context
        if context.shouldCapitalize {
            // Capitalize first letter (Whisper usually does this already)
            result = result.prefix(1).uppercased() + result.dropFirst()
        } else {
            // Mid-sentence, lowercase the first character
            result = result.prefix(1).lowercased() + result.dropFirst()
        }

        // Adjust punctuation based on context
        if context.shouldAddPunctuation {
            // Add period at end if no punctuation present
            let lastChar = result.last
            if lastChar != nil && !".,!?;:".contains(lastChar!) {
                result += "."
            }
        } else {
            // Inserting mid-text: strip trailing punctuation that was auto-added by TextFormatter
            while let lastChar = result.last, ".?".contains(lastChar) {
                result = String(result.dropLast())
            }
        }

        return result
    }

    /// Context information about where text will be inserted
    private struct InsertionContext {
        let shouldCapitalize: Bool
        let shouldAddPunctuation: Bool
    }

    /// Analyze the context to determine formatting needs
    private func analyzeContext(_ existingText: String, cursorPosition: Int) -> InsertionContext {
        // If cursor is at the very beginning
        guard cursorPosition > 0 else {
            // If there's text after cursor, we're inserting before existing content
            let hasTextAfter = !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: !hasTextAfter)
        }

        // Safely clamp cursor position to valid range
        let safePosition = min(cursorPosition, existingText.count)

        // Check if we're at the end of the text
        let isAtEnd = safePosition >= existingText.count

        // Get text before cursor (up to 10 characters for context)
        let startOffset = max(0, safePosition - 10)

        guard let contextStart = existingText.index(existingText.startIndex, offsetBy: startOffset, limitedBy: existingText.endIndex),
              let contextEnd = existingText.index(existingText.startIndex, offsetBy: safePosition, limitedBy: existingText.endIndex) else {
            // Index calculation failed - treat as beginning of text
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: isAtEnd)
        }

        let beforeCursor = String(existingText[contextStart..<contextEnd])

        // Get text after cursor (up to 10 characters)
        var afterCursor = ""
        if safePosition < existingText.count {
            guard let afterStart = existingText.index(existingText.startIndex, offsetBy: safePosition, limitedBy: existingText.endIndex) else {
                // Failed to get after start, skip after context
                return analyzeBeforeContext(beforeCursor: beforeCursor, isAtEnd: isAtEnd)
            }

            let remainingLength = existingText.count - safePosition
            let lengthToRead = min(10, remainingLength)

            if let afterEnd = existingText.index(afterStart, offsetBy: lengthToRead, limitedBy: existingText.endIndex) {
                afterCursor = String(existingText[afterStart..<afterEnd])
            }
        }

        return analyzeBeforeContext(beforeCursor: beforeCursor, isAtEnd: isAtEnd, afterCursor: afterCursor)
    }

    /// Analyze the text before cursor to determine formatting
    private func analyzeBeforeContext(beforeCursor: String, isAtEnd: Bool, afterCursor: String = "") -> InsertionContext {
        // Trim whitespace to analyze the actual content
        let trimmedBefore = beforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty context = beginning of field
        guard !trimmedBefore.isEmpty else {
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: isAtEnd)
        }

        // Get the last non-whitespace character before cursor
        guard let lastChar = trimmedBefore.last else {
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: isAtEnd)
        }

        var shouldCapitalize = false
        var shouldAddPunctuation = isAtEnd

        // Sentence-ending punctuation = new sentence
        let sentenceEnders: Set<Character> = [".", "!", "?"]
        if sentenceEnders.contains(lastChar) {
            shouldCapitalize = true
            shouldAddPunctuation = isAtEnd
        }
        // Colon or semicolon = maybe capitalize (after colon, usually yes)
        else if lastChar == ":" {
            shouldCapitalize = true
            shouldAddPunctuation = isAtEnd
        }
        // Comma or dash = mid-sentence, don't capitalize
        else if ",;-—".contains(lastChar) {
            shouldCapitalize = false
            shouldAddPunctuation = false
        }
        // Opening quote/paren = depends on context
        else if "\"'([{".contains(lastChar) {
            shouldCapitalize = true
            shouldAddPunctuation = false
        }
        // Check for newlines (paragraph breaks)
        else if beforeCursor.suffix(3).contains("\n") {
            shouldCapitalize = true
            shouldAddPunctuation = isAtEnd
        }
        // Default: mid-sentence
        else {
            shouldCapitalize = false
            shouldAddPunctuation = false
        }

        // If there's text after cursor, don't add punctuation (we're in the middle)
        if !afterCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shouldAddPunctuation = false
        }

        return InsertionContext(
            shouldCapitalize: shouldCapitalize,
            shouldAddPunctuation: shouldAddPunctuation
        )
    }
}
