# Cursor-Positioned Recording Indicator - UX Improvement Plan

## Overview

Improve the dictation recording indicator to match Apple's native dictation UX, where the indicator appears directly at the cursor position in the focused text field, rather than at a fixed screen location.

## Current Behavior

- **Floating window** appears at top or bottom of screen (user preference)
- Fixed position regardless of where cursor is
- Shows "Recording" text with pulsing red dot
- Siri-style animated multi-color border
- Always visible at screen edge during dictation

## Desired Behavior (Apple-Style)

- **Cursor-positioned indicator** appears directly below (or above) the text cursor
- Follows the insertion point where text will actually appear
- Shows **live transcription** as it arrives from Whisper
- More compact, text-focused design
- Contextually positioned based on text field location

## Benefits

1. **Clearer feedback** - User sees exactly where dictated text will appear
2. **Better context** - Visual connection between speech and insertion point
3. **Live preview** - See transcription as it happens (like Apple dictation)
4. **Familiar UX** - Matches system dictation behavior users already know
5. **Less intrusive** - No need to look away from cursor to see recording status

---

## Technical Implementation Plan

### Phase 1: Cursor Position Tracking

**New File:** `Sources/LookMaNoHands/Services/CursorPositionService.swift`

```swift
class CursorPositionService {
    /// Get screen coordinates of the cursor in the focused text field
    func getCursorScreenPosition() -> NSRect?

    /// Get the focused text element via Accessibility API
    private func getFocusedTextElement() -> AXUIElement?

    /// Convert text field selection range to screen coordinates
    private func getScreenRect(for element: AXUIElement, range: CFRange) -> NSRect?
}
```

**Key APIs to use:**
- `AXUIElementCreateSystemWide()` - Get system-wide accessibility element
- `kAXFocusedUIElementAttribute` - Find focused text field
- `kAXSelectedTextRangeAttribute` - Get cursor position/selection range
- `kAXBoundsForRangeParameterizedAttribute` - Convert range to screen coordinates
- `AXUIElementCopyParameterizedAttributeValue()` - Get bounds for range

**Algorithm:**
1. Get system-wide AX element
2. Get focused application
3. Get focused UI element within app
4. Verify it's a text field (role = `kAXTextFieldRole` or `kAXTextAreaRole`)
5. Get selection range (cursor position)
6. Use `kAXBoundsForRangeParameterizedAttribute` to get screen rect
7. Return `NSRect` representing cursor position on screen

**Edge Cases:**
- Cursor position unavailable → fallback to fixed position mode
- Multi-monitor setups → ensure rect is on correct screen
- Text field role detection fails → try getting bounds anyway
- No focused element → show at mouse cursor position or center of active window

---

### Phase 2: Redesign Recording Indicator

**Modify:** `RecordingIndicator.swift`

**New Design:**
```
┌─────────────────────────────────────┐
│  🔴 "Hello world this is a test"   │
└─────────────────────────────────────┘
   ↑ Small pulsing mic/dot + live text
```

**Changes:**
1. **Show live transcription** instead of static "Recording" text
2. Keep last **30-50 characters** visible (truncate from left if longer)
3. Smaller, more compact design (~200-300px wide, auto-width based on text)
4. Simpler animation - just pulsing red dot or microphone icon
5. Lighter border (or no border) - focus on content

**New State:**
```swift
struct RecordingIndicator: View {
    @State private var transcriptionText: String = ""
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing microphone icon
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
                .scaleEffect(isPulsing ? 1.2 : 1.0)

            // Live transcription (last 50 chars)
            if !transcriptionText.isEmpty {
                Text(transcriptionText.suffix(50))
                    .font(.system(size: 14))
                    .lineLimit(1)
            } else {
                Text("Listening...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(radius: 5)
    }
}
```

**API Addition:**
```swift
class RecordingIndicatorWindowController {
    /// Update the displayed transcription text
    func updateTranscription(_ text: String)
}
```

---

### Phase 3: Dynamic Positioning

**Modify:** `RecordingIndicatorWindowController`

**New Positioning Logic:**
```swift
func updatePosition(for cursorRect: NSRect) {
    guard let window = window else { return }

    // Position indicator below cursor with small offset
    var origin = NSPoint(
        x: cursorRect.midX - (windowWidth / 2),  // Center horizontally on cursor
        y: cursorRect.minY - windowHeight - 8     // 8pt below cursor
    )

    // Handle screen edge cases
    if let screen = NSScreen.main {
        let screenFrame = screen.visibleFrame

        // Too close to bottom edge? Show above cursor instead
        if origin.y < screenFrame.minY + 20 {
            origin.y = cursorRect.maxY + 8  // 8pt above cursor
        }

        // Too close to left edge?
        if origin.x < screenFrame.minX + 10 {
            origin.x = screenFrame.minX + 10
        }

        // Too close to right edge?
        if origin.x + windowWidth > screenFrame.maxX - 10 {
            origin.x = screenFrame.maxX - windowWidth - 10
        }
    }

    window.setFrameOrigin(origin)
}
```

**Positioning Strategy:**
1. **Default:** 8 pixels below cursor, horizontally centered
2. **Near bottom edge:** Show above cursor instead
3. **Near left/right edge:** Shift horizontally to stay on screen
4. **Multi-monitor:** Ensure positioned on screen containing text field
5. **Update frequency:** Throttle to every 200ms to avoid jitter

---

### Phase 4: Live Transcription Streaming

**Integration Points:**

**1. Audio Recording Pipeline:**
```swift
// In AudioRecorder.swift or wherever transcription happens
func onPartialTranscription(_ text: String) {
    // Send to indicator
    recordingIndicator.updateTranscription(text)
}
```

**2. WhisperService Integration:**
- Already has `transcribe(audioURL:)` method
- Need to add streaming/partial results callback
- Update indicator as words are recognized

**3. Continuous Updates:**
```swift
// In keyboard monitoring loop
@MainActor
func startRecording() {
    // Get initial cursor position
    if let cursorRect = CursorPositionService.shared.getCursorScreenPosition() {
        recordingIndicator.updatePosition(for: cursorRect)
    } else {
        // Fallback to fixed position
        recordingIndicator.updatePosition(fixed: .bottom)
    }

    recordingIndicator.show()
    audioRecorder.startRecording()

    // Optional: Update position periodically (in case cursor moves)
    positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
        if let newRect = CursorPositionService.shared.getCursorScreenPosition() {
            recordingIndicator.updatePosition(for: newRect)
        }
    }
}
```

---

### Phase 5: Settings & Fallback

**Add to Settings.swift:**
```swift
@AppStorage("indicatorPositionMode") var indicatorPositionMode: IndicatorPositionMode = .cursor

enum IndicatorPositionMode: String, Codable {
    case cursor      // Follow cursor (new default)
    case top         // Fixed at top of screen
    case bottom      // Fixed at bottom of screen
}
```

**Settings UI (SettingsView.swift):**
```swift
Picker("Recording Indicator Position", selection: $settings.indicatorPositionMode) {
    Text("At Cursor (Apple-style)").tag(IndicatorPositionMode.cursor)
    Text("Top of Screen").tag(IndicatorPositionMode.top)
    Text("Bottom of Screen").tag(IndicatorPositionMode.bottom)
}
```

**Fallback Strategy:**
1. Always **try cursor positioning first**
2. If `getCursorScreenPosition()` returns `nil` → use fixed position from settings
3. If cursor detected but off-screen → use fixed position
4. Log failures for debugging: "Could not get cursor position, using fallback"

---

## Implementation Sequence

### Sprint 1: Cursor Tracking Foundation
- [ ] Create `CursorPositionService.swift`
- [ ] Implement `getCursorScreenPosition()` with AX APIs
- [ ] Add error handling and fallback logic
- [ ] Unit test cursor detection in various apps (TextEdit, Safari, Chrome, VSCode)

### Sprint 2: Indicator Redesign
- [ ] Update `RecordingIndicator` view with live text display
- [ ] Add `updateTranscription(_ text:)` method
- [ ] Implement text truncation (last 50 chars)
- [ ] Simplify animations

### Sprint 3: Dynamic Positioning
- [ ] Add `updatePosition(for cursorRect:)` to `RecordingIndicatorWindowController`
- [ ] Implement edge case handling (screen boundaries)
- [ ] Add periodic position updates during recording
- [ ] Test multi-monitor scenarios

### Sprint 4: Transcription Streaming
- [ ] Hook up Whisper partial results to indicator
- [ ] Implement throttling (avoid too-frequent updates)
- [ ] Test with short and long dictations

### Sprint 5: Settings & Polish
- [ ] Add position mode setting (cursor/top/bottom)
- [ ] Implement graceful fallback when cursor detection fails
- [ ] Performance testing and optimization
- [ ] User documentation

---

## Testing Checklist

### Cursor Detection
- [ ] TextEdit (native macOS)
- [ ] Safari address bar and text areas
- [ ] Chrome/Brave/Edge (Chromium-based)
- [ ] Firefox
- [ ] Visual Studio Code
- [ ] Slack desktop app
- [ ] Notion
- [ ] Terminal.app
- [ ] iTerm2

### Positioning Edge Cases
- [ ] Cursor near bottom of screen → indicator above cursor
- [ ] Cursor near top of screen → indicator below cursor
- [ ] Cursor near left edge → indicator shifts right
- [ ] Cursor near right edge → indicator shifts left
- [ ] Multi-monitor setup → indicator on correct screen
- [ ] Text field in full-screen app
- [ ] Text field in small window

### Transcription Display
- [ ] Short dictation (1-5 words) → all text visible
- [ ] Long dictation (100+ words) → last 50 chars visible
- [ ] Fast speech → updates keep up without lag
- [ ] Pauses → "..." shown when waiting
- [ ] Special characters and emojis display correctly

### Fallback Scenarios
- [ ] Cursor position unavailable → fixed position used
- [ ] Non-text field focused → fixed position used
- [ ] Accessibility permissions denied → fixed position used
- [ ] Position update fails mid-recording → indicator stays in last good position

---

## Performance Considerations

1. **Cursor position queries** - Don't query on every frame
   - Throttle to 200ms intervals (5 updates/second max)
   - Only query when recording is active

2. **Text updates** - Batch transcription updates
   - Update indicator every 100-200ms, not on every word
   - Use main thread only for UI updates

3. **Window positioning** - Minimize SetFrameOrigin calls
   - Only update when cursor moves significantly (>10px)
   - Cache last position to avoid redundant updates

4. **Memory** - Release resources when not recording
   - Stop position update timer when recording ends
   - Clear transcription text buffer

---

## Open Questions

1. **Whisper partial results** - Does WhisperService support streaming/partial transcriptions?
   - If not, may need to show "Recording..." until transcription completes
   - Could show audio waveform/volume level instead

2. **Cursor tracking frequency** - How often should we update position?
   - Too frequent = performance impact
   - Too infrequent = indicator lags behind cursor movement
   - **Proposed:** 200ms (5 Hz) seems reasonable

3. **Indicator auto-width** - Should indicator width adjust to text length?
   - Fixed width = simpler layout
   - Auto-width = better UX but more complex
   - **Proposed:** Fixed max-width (300px), auto-shrink if text shorter

4. **Animation** - Keep Siri-style border or simplify?
   - Siri border = visually appealing but distracting from text
   - Simple pulse = less flashy, more focused
   - **Proposed:** Simple pulsing red dot, no border

---

## Future Enhancements

1. **Waveform visualization** - Show audio level as waveform bars
2. **Confidence indicators** - Color-code text by Whisper confidence
3. **Editable preview** - Allow user to edit text before insertion
4. **Multi-cursor support** - Handle split editors with multiple cursors
5. **Dictation commands** - Visual feedback for commands like "new line", "delete that"

---

## References

- Apple Dictation UX: System Preferences → Keyboard → Dictation
- Accessibility API: [NSAccessibility](https://developer.apple.com/documentation/appkit/nsaccessibility)
- Parameterized Attributes: [AXUIElementCopyParameterizedAttributeValue](https://developer.apple.com/documentation/applicationservices/1459418-axuielementcopyparameterizedattr)
- Bounds for Range: `kAXBoundsForRangeParameterizedAttribute`

---

**Status:** Planning phase complete - ready for implementation when approved.

**Last Updated:** 2026-01-21
