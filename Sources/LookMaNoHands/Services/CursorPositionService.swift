import Foundation
import AppKit
import ApplicationServices

/// Service for tracking cursor position in focused text fields
/// Uses Accessibility APIs to get screen coordinates of the text cursor
class CursorPositionService {

    static let shared = CursorPositionService()

    private init() {}

    // MARK: - Public Methods

    /// Get screen coordinates of the cursor in the focused text field
    /// - Returns: NSRect representing cursor position, or nil if unavailable
    func getCursorScreenPosition() -> NSRect? {
        // Get the focused text element
        guard let focusedElement = getFocusedTextElement() else {
            print("CursorPositionService: No focused text element found")
            // Fallback: use mouse cursor position
            return getMouseCursorPosition()
        }

        // Get cursor position (selection range)
        guard let cursorRange = getCursorRange(for: focusedElement) else {
            print("CursorPositionService: Could not get cursor range, trying mouse position")
            // Fallback: use mouse cursor position
            return getMouseCursorPosition()
        }

        // Convert range to screen coordinates
        guard let screenRect = getScreenRect(for: focusedElement, range: cursorRange) else {
            print("CursorPositionService: Could not convert range to screen rect, trying mouse position")
            // Fallback: use mouse cursor position
            return getMouseCursorPosition()
        }

        print("CursorPositionService: Cursor position found at \(screenRect)")
        return screenRect
    }

    /// Fallback: Get mouse cursor position as a proxy for text cursor
    private func getMouseCursorPosition() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        print("CursorPositionService: Using mouse cursor position as fallback: \(mouseLocation)")

        // Create a small rect at mouse position
        return NSRect(
            x: mouseLocation.x,
            y: mouseLocation.y,
            width: 2,
            height: 20
        )
    }

    // MARK: - Private Methods

    /// Get the focused text element via Accessibility API
    private func getFocusedTextElement() -> AXUIElement? {
        // Get system-wide accessibility element
        let systemWide = AXUIElementCreateSystemWide()

        // Get focused application
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            print("CursorPositionService: Could not get focused application")
            return nil
        }

        // Get focused element within the application
        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success, let element = focusedElement else {
            print("CursorPositionService: Could not get focused UI element")
            return nil
        }

        let axElement = element as! AXUIElement

        // Strategy 1: Check if this element itself is a text field
        if let textElement = validateTextElement(axElement) {
            return textElement
        }

        // Strategy 2: Walk up the parent hierarchy to find a text container
        print("CursorPositionService: Checking parent hierarchy for text element")
        if let parent = getParentTextElement(axElement) {
            return parent
        }

        // Strategy 3: Search children for text area
        print("CursorPositionService: Searching children for text element")
        if let child = findTextElementInChildren(axElement) {
            return child
        }

        // Fallback: use the focused element anyway
        print("CursorPositionService: Using focused element as last resort")
        return axElement
    }

    /// Validate if an element is a text input element
    private func validateTextElement(_ element: AXUIElement) -> AXUIElement? {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )

        if roleResult == .success, let role = roleValue as? String {
            print("CursorPositionService: Element role: \(role)")

            let validRoles = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                "AXWebArea" as String,
                "AXTextField" as String,
                "AXTextArea" as String,
                "AXComboBox" as String
            ]

            if validRoles.contains(role) {
                print("CursorPositionService: Valid text input role found")
                return element
            }
        }

        return nil
    }

    /// Walk up parent hierarchy to find text element
    private func getParentTextElement(_ element: AXUIElement) -> AXUIElement? {
        var current = element
        var depth = 0
        let maxDepth = 5  // Limit depth to avoid infinite loops

        while depth < maxDepth {
            var parent: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parent
            )

            guard result == .success, let parentRef = parent else {
                break
            }

            let parentElement = parentRef as! AXUIElement

            if let textElement = validateTextElement(parentElement) {
                print("CursorPositionService: Found text element in parent at depth \(depth)")
                return textElement
            }

            current = parentElement
            depth += 1
        }

        return nil
    }

    /// Search children for text element
    private func findTextElementInChildren(_ element: AXUIElement) -> AXUIElement? {
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        )

        guard result == .success,
              let childArray = children as? [AXUIElement] else {
            return nil
        }

        // Check each child
        for child in childArray {
            if let textElement = validateTextElement(child) {
                print("CursorPositionService: Found text element in children")
                return textElement
            }
        }

        return nil
    }

    /// Get cursor position (selection range) from text element
    private func getCursorRange(for element: AXUIElement) -> CFRange? {
        // Get selected text range
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard rangeResult == .success else {
            print("CursorPositionService: Could not get selected text range")
            return nil
        }

        // Convert AXValue to CFRange
        var range = CFRange(location: 0, length: 0)
        if let rangeValue = selectedRange {
            let success = AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            if success {
                print("CursorPositionService: Cursor range: location=\(range.location), length=\(range.length)")
                return range
            }
        }

        print("CursorPositionService: Could not convert AXValue to CFRange")
        return nil
    }

    /// Convert text field selection range to screen coordinates
    private func getScreenRect(for element: AXUIElement, range: CFRange) -> NSRect? {
        // Use kAXBoundsForRangeParameterizedAttribute to get screen bounds
        var mutableRange = range
        let rangeValue = AXValueCreate(.cfRange, &mutableRange)

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue!,
            &boundsValue
        )

        guard boundsResult == .success else {
            print("CursorPositionService: kAXBoundsForRangeParameterizedAttribute failed with error: \(boundsResult.rawValue)")

            // Fallback: try to get element bounds instead of cursor bounds
            return getElementBounds(for: element)
        }

        // Convert AXValue to CGRect
        var rect = CGRect.zero
        if let rectValue = boundsValue {
            let success = AXValueGetValue(rectValue as! AXValue, .cgRect, &rect)
            if success {
                // CGRect origin is bottom-left, NSRect origin is also bottom-left in screen coordinates
                return NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
            }
        }

        print("CursorPositionService: Could not convert bounds to CGRect")
        return nil
    }

    /// Fallback: Get the bounds of the text element itself
    private func getElementBounds(for element: AXUIElement) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard posResult == .success, sizeResult == .success else {
            print("CursorPositionService: Could not get element position or size")
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        if let posVal = positionValue {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        }

        if let sizeVal = sizeValue {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        }

        // Position indicator at top-left of text field (where typing would start)
        // Create a small rect at the beginning of the text field
        let cursorRect = NSRect(
            x: position.x + 5,  // Small left padding
            y: position.y + size.height - 20,  // Near top of field
            width: 2,
            height: 20
        )

        print("CursorPositionService: Using element bounds as fallback")
        print("  Element: origin=\(position), size=\(size)")
        print("  Cursor rect: \(cursorRect)")
        return cursorRect
    }
}
