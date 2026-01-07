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
        // Strategy 1: Try Accessibility API (cleanest method)
        if insertViaAccessibility(text) {
            print("TextInsertionService: Inserted via Accessibility API")
            return true
        }
        
        // Strategy 2: Try clipboard + paste (most compatible)
        if insertViaClipboard(text) {
            print("TextInsertionService: Inserted via clipboard paste")
            return true
        }
        
        // Strategy 3: Copy to clipboard and notify user
        copyToClipboard(text)
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
        
        // Try to set the value directly
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        
        if setResult == .success {
            return true
        }
        
        // If direct set failed, try inserting at selection
        return insertAtSelection(focusedElement, text: text)
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
}
