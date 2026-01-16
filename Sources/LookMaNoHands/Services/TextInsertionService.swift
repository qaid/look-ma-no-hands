import Foundation
import AppKit
import ApplicationServices

/// Service for inserting text into the currently focused text field
/// Uses multiple strategies to maximize compatibility across applications
class TextInsertionService {
    
    // MARK: - Public Methods
    
    /// Insert text into the currently focused text field
    /// Tries multiple methods in order of preference
    /// - Parameter text: The text to insert
    /// - Returns: True if insertion was successful
    @discardableResult
    func insertText(_ text: String) -> Bool {
        // Apply context-aware formatting before insertion
        let formattedText = applyContextAwareFormatting(text)

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
        
        // Build new text with insertion
        let startIndex = currentText.index(currentText.startIndex, offsetBy: range.location)
        let endIndex = currentText.index(startIndex, offsetBy: range.length)
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

    // MARK: - Context-Aware Formatting

    /// Apply context-aware formatting based on surrounding text
    /// Adjusts capitalization based on what comes before the cursor
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
        let shouldCapitalize = shouldCapitalizeBasedOnContext(currentText, cursorPosition: range.location)

        // Adjust first character based on context
        if shouldCapitalize {
            // Already capitalized (Whisper does this), keep as-is
            return text
        } else {
            // Mid-sentence, lowercase the first character
            return text.prefix(1).lowercased() + text.dropFirst()
        }
    }

    /// Determine if text should be capitalized based on what comes before cursor
    private func shouldCapitalizeBasedOnContext(_ existingText: String, cursorPosition: Int) -> Bool {
        // If cursor is at the very beginning, capitalize
        guard cursorPosition > 0 else {
            return true
        }

        // Get text before cursor (up to 10 characters for context)
        let startIndex = max(0, cursorPosition - 10)
        let contextStart = existingText.index(existingText.startIndex, offsetBy: startIndex)
        let contextEnd = existingText.index(existingText.startIndex, offsetBy: cursorPosition)
        let context = String(existingText[contextStart..<contextEnd])

        // Trim whitespace to analyze the actual content
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty context = beginning of field
        guard !trimmedContext.isEmpty else {
            return true
        }

        // Get the last non-whitespace character
        guard let lastChar = trimmedContext.last else {
            return true
        }

        // Sentence-ending punctuation followed by space = new sentence
        let sentenceEnders: Set<Character> = [".", "!", "?"]
        if sentenceEnders.contains(lastChar) {
            // Check if there's a space after the punctuation (before cursor)
            let afterPunctuation = String(existingText[contextEnd..<existingText.index(existingText.startIndex, offsetBy: cursorPosition)])
            if afterPunctuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }

        // Check for newlines (paragraph breaks)
        if context.contains("\n") {
            // If there's a newline near the cursor, it's likely a new sentence
            let lastFewChars = String(context.suffix(3))
            if lastFewChars.contains("\n") {
                return true
            }
        }

        // Default: mid-sentence, don't capitalize
        return false
    }
}
