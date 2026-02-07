import Foundation
import AppKit
import ApplicationServices

/// Captured AX text field state to avoid multiple reads (race condition)
private struct AXTextFieldState {
    let element: AXUIElement
    let text: String
    let cursorLocation: Int  // UTF-16 offset
    let selectionLength: Int // UTF-16 offset
}

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

        // Read AX state once to avoid race conditions between formatting and insertion
        let state = captureAXState()

        // Apply context-aware formatting using the captured state
        let formattedText = applyContextAwareFormatting(cleanedText, state: state)

        // Strategy 1: Try Accessibility API (cleanest method)
        if let state = state, insertAtSelection(state, text: formattedText) {
            print("TextInsertionService: Inserted via Accessibility API")
            return true
        }

        // Strategy 1b: Try AX without captured state (element might not be a text field)
        if state == nil, let element = getFocusedElement() {
            var roleValue: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            if roleResult == .success,
               let role = roleValue as? String,
               role == kAXTextFieldRole || role == kAXTextAreaRole {
                let setResult = AXUIElementSetAttributeValue(
                    element,
                    kAXValueAttribute as CFString,
                    formattedText as CFTypeRef
                )
                if setResult == .success {
                    print("TextInsertionService: Inserted via Accessibility API (set value)")
                    return true
                }
            }
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

    /// Capture the current AX text field state in a single read
    private func captureAXState() -> AXTextFieldState? {
        guard let focusedElement = getFocusedElement() else {
            return nil
        }

        // Check if it's a text field/area
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleValue)

        guard roleResult == .success,
              let role = roleValue as? String,
              role == kAXTextFieldRole || role == kAXTextAreaRole else {
            return nil
        }

        // Get current value
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        guard valueResult == .success,
              let currentText = currentValue as? String else {
            return nil
        }

        // Get selection range (UTF-16 offsets from AX API)
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        let nsString = currentText as NSString
        var cursorLocation = nsString.length
        var selectionLength = 0

        if rangeResult == .success, let rangeValue = selectedRange {
            var range = CFRange()
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            cursorLocation = min(range.location, nsString.length)
            selectionLength = min(range.length, nsString.length - cursorLocation)
        }

        return AXTextFieldState(
            element: focusedElement,
            text: currentText,
            cursorLocation: cursorLocation,
            selectionLength: selectionLength
        )
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
    
    /// Insert text at the current selection point using captured AX state
    /// Uses UTF-16 offsets (NSString convention) to match AX API behavior
    private func insertAtSelection(_ state: AXTextFieldState, text: String) -> Bool {
        let currentText = state.text
        let nsString = currentText as NSString

        // AX API returns UTF-16 offsets — clamp to valid NSString bounds
        let safeLocation = min(state.cursorLocation, nsString.length)
        let safeLength = min(state.selectionLength, nsString.length - safeLocation)
        let nsRange = NSRange(location: safeLocation, length: safeLength)

        // Convert UTF-16 NSRange to Swift String.Index range
        guard let swiftRange = Range(nsRange, in: currentText) else {
            // Fallback: append at end
            let newText = currentText + text
            let setResult = AXUIElementSetAttributeValue(
                state.element,
                kAXValueAttribute as CFString,
                newText as CFTypeRef
            )
            return setResult == .success
        }

        var newText = currentText
        newText.replaceSubrange(swiftRange, with: text)

        // Set the new value
        let setResult = AXUIElementSetAttributeValue(
            state.element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )

        guard setResult == .success else { return false }

        // Position cursor at end of inserted text (UTF-16 offset)
        let newCursorLocation = safeLocation + (text as NSString).length
        var newRange = CFRange(location: newCursorLocation, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                state.element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
        }

        return true
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

        let nsString = currentText as NSString
        var cursorUTF16 = nsString.length
        if rangeResult == .success, let rangeValue = selectedRange {
            var range = CFRange()
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            cursorUTF16 = min(range.location, nsString.length)
        }

        // Convert UTF-16 cursor position to Swift String.Index
        let cursorIndex = String.Index(utf16Offset: cursorUTF16, in: currentText)

        // Get the last maxLength characters before cursor
        let startIndex = currentText.index(cursorIndex, offsetBy: -min(maxLength, currentText.distance(from: currentText.startIndex, to: cursorIndex)), limitedBy: currentText.startIndex) ?? currentText.startIndex

        let beforeCursor = String(currentText[startIndex..<cursorIndex])
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
    /// Uses pre-captured AX state to avoid race conditions
    private func applyContextAwareFormatting(_ text: String, state: AXTextFieldState?) -> String {
        guard !text.isEmpty else { return text }

        guard let state = state, !state.text.isEmpty else {
            // No existing text or can't read it - keep original capitalization
            return text
        }

        // Analyze context before cursor (using UTF-16 cursor location)
        let context = analyzeContext(state.text, cursorPosition: state.cursorLocation)

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

        // Add leading space if cursor is directly after a non-space character (e.g. after a period)
        if context.needsLeadingSpace {
            result = " " + result
        }

        // Add trailing space if the next character is a non-space character
        if context.needsTrailingSpace {
            result += " "
        }

        return result
    }

    /// Context information about where text will be inserted
    private struct InsertionContext {
        let shouldCapitalize: Bool
        let shouldAddPunctuation: Bool
        let needsLeadingSpace: Bool
        let needsTrailingSpace: Bool
    }

    /// Analyze the context to determine formatting needs
    /// cursorPosition is a UTF-16 offset (from AX API)
    private func analyzeContext(_ existingText: String, cursorPosition: Int) -> InsertionContext {
        // If cursor is at the very beginning
        guard cursorPosition > 0 else {
            let hasTextAfter = !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let firstCharIsNonSpace = existingText.first.map { !$0.isWhitespace } ?? false
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: !hasTextAfter, needsLeadingSpace: false, needsTrailingSpace: firstCharIsNonSpace)
        }

        let nsString = existingText as NSString

        // Clamp UTF-16 cursor position to valid range
        let safePosition = min(cursorPosition, nsString.length)

        // Check if we're at the end of the text
        let isAtEnd = safePosition >= nsString.length

        // Convert UTF-16 cursor position to Swift String.Index
        let cursorIndex = String.Index(utf16Offset: safePosition, in: existingText)

        // Get text before cursor (up to 10 characters for context)
        let beforeStart = existingText.index(cursorIndex, offsetBy: -min(10, existingText.distance(from: existingText.startIndex, to: cursorIndex)), limitedBy: existingText.startIndex) ?? existingText.startIndex
        let beforeCursor = String(existingText[beforeStart..<cursorIndex])

        // Get text after cursor (up to 10 characters)
        var afterCursor = ""
        if cursorIndex < existingText.endIndex {
            let afterEnd = existingText.index(cursorIndex, offsetBy: 10, limitedBy: existingText.endIndex) ?? existingText.endIndex
            afterCursor = String(existingText[cursorIndex..<afterEnd])
        }

        return analyzeBeforeContext(beforeCursor: beforeCursor, isAtEnd: isAtEnd, afterCursor: afterCursor)
    }

    /// Analyze the text before cursor to determine formatting
    private func analyzeBeforeContext(beforeCursor: String, isAtEnd: Bool, afterCursor: String = "") -> InsertionContext {
        // Check if the first character after cursor is a non-space character
        let needsTrailingSpace = afterCursor.first.map { !$0.isWhitespace && !$0.isNewline } ?? false

        // Check if the last character before cursor is a non-space character (needs leading space)
        let needsLeadingSpace = beforeCursor.last.map { !$0.isWhitespace && !$0.isNewline } ?? false

        // Trim whitespace to analyze the actual content
        let trimmedBefore = beforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty context = beginning of field
        guard !trimmedBefore.isEmpty else {
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: isAtEnd, needsLeadingSpace: false, needsTrailingSpace: needsTrailingSpace)
        }

        // Get the last non-whitespace character before cursor
        guard let lastChar = trimmedBefore.last else {
            return InsertionContext(shouldCapitalize: true, shouldAddPunctuation: isAtEnd, needsLeadingSpace: false, needsTrailingSpace: needsTrailingSpace)
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
            shouldAddPunctuation: shouldAddPunctuation,
            needsLeadingSpace: needsLeadingSpace,
            needsTrailingSpace: needsTrailingSpace
        )
    }
}
