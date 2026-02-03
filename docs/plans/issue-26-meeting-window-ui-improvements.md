# Issue #26: Improve Meeting Transcription Window UI

**GitHub Issue:** https://github.com/qaid/look-ma-no-hands/issues/26
**Inspiration:** Craft.do (https://www.craft.do/)
**Current Branch:** `polish-ux-ui`
**Status:** Planning Complete - Ready for Implementation

---

## Executive Summary

Transform the Meeting Transcription window from a functional-but-basic interface into a polished, professional experience. The improvements are inspired by Craft.do's design principles but adapted for a text-heavy transcription interface, avoiding unnecessary visual decoration in favor of meaningful UX enhancements.

**Key Philosophy:** Adopt Craft.do's **UX principles** (spacing, typography, progressive disclosure) while maintaining macOS native clarity. Do NOT copy their glass aesthetic wholesale - text readability is paramount.

---

## Current State Analysis

### Existing Implementation
- **File:** `Sources/LookMaNoHands/Views/MeetingView.swift`
- **Window Size:** 700x500 (fixed, non-resizable)
- **Structure:**
  ```
  VStack(spacing: 0) {
    headerView          // Icon + "Meeting Transcription" title
    Divider()
    statusBar           // Recording dot, status message, mic picker, timer
    Divider()
    transcriptView      // ScrollView with segments
    Divider()
    controlsView        // Start/Stop, Clear, Generate Notes, Export
  }
  ```

### Current Issues
1. **UX Gaps:**
   - No confirmation before clearing transcript (data loss risk)
   - Export menu hides available formats
   - Can't cancel long-running note generation
   - No warning when closing window during recording

2. **Visual Issues:**
   - Cramped spacing (minimal padding)
   - All buttons have equal visual weight
   - Hard dividers create rigid appearance
   - Empty state lacks visual hierarchy
   - Timer hard to scan quickly

3. **Accessibility:**
   - Missing VoiceOver labels on most controls
   - No keyboard shortcuts for primary actions
   - Status messages not announced to screen readers

---

## Research Findings Summary

### Craft.do Design Analysis
**Source:** Web research by specialized agent (see `docs/waveform-improvements.md` for research methodology)

**Key Patterns Identified:**
1. **8pt spacing grid** - All dimensions use multiples of 8px
2. **Generous padding** - 20-24px margins, 16px section gaps
3. **SF Pro typography hierarchy** - 16px body, 14px metadata, 13px captions
4. **Liquid Glass materials** - Translucent chrome, vibrancy effects
5. **Smooth animations** - 200-400ms transitions, easeInOut curves
6. **Progressive disclosure** - Advanced features hidden until needed
7. **Preset-first approach** - Common patterns as buttons, customization secondary

**What to Adopt:**
- ✅ Spacing system (breathing room improves readability)
- ✅ Typography hierarchy (scannable information)
- ✅ Progressive disclosure (reduces cognitive load)
- ✅ Animation timing standards (professional polish)

**What to AVOID:**
- ❌ Glass effects everywhere (reduces text contrast)
- ❌ Custom translucent buttons (system styles are clearer)
- ❌ Over-designed empty states (7 elements is too many)

### UX Review Findings
**Source:** Professional UX audit by specialized agent

**Critical Insights:**
1. Meeting transcription is **text-heavy** (unlike Craft's visual cards)
2. Users need **high contrast** for 30-60 minute reading sessions
3. **Function over form** - tool window, not showcase app
4. Glass aesthetic works for **floating elements** (recording indicator) but not window chrome

**Risk Assessment:**
- **Low Risk:** Confirmations, split menus, keyboard shortcuts
- **Medium Risk:** Complex empty state, hover effects on segments
- **High Risk:** Glass materials on window chrome (readability impact)

---

## Implementation Plan

### Phase 1: Critical UX Fixes (Week 1 - 2-3 hours)

#### 1.1 Add Clear Confirmation Dialog
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (around line 305)

**Current Code:**
```swift
Button {
    showClearConfirmation = true
} label: {
    HStack {
        Image(systemName: "trash")
        Text("Clear")
    }
}
.disabled(meetingState.segments.isEmpty)
```

**Already Has:** `.confirmationDialog()` at lines 314-325

**Status:** ✅ Already implemented correctly

**Verification:** Test that clicking Clear shows dialog with proper message count

---

#### 1.2 Split Export Menu into Two Buttons
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (lines 358-399)

**Current Implementation:**
- Single "Export Transcript" menu (always visible)
- Conditional "Export Notes" menu (only when notes exist)

**Status:** ✅ Already implemented as two separate menus

**Improvement Needed:** Make them visually distinct buttons instead of menus

**New Design:**
```swift
HStack(spacing: 12) {
    // Transcript export - always visible
    Menu {
        Section("Transcript") {
            Button("Copy Transcript") { copyTranscript() }
            Button("Copy Timestamped") { copyTimestampedTranscript() }
            Divider()
            Button("Save as Text...") { saveTranscript() }
            Button("Save with Timestamps...") { saveTimestampedTranscript() }
        }
    } label: {
        Label("Export Transcript", systemImage: "doc.text")
            .font(.system(size: 14))
    }
    .disabled(meetingState.segments.isEmpty)
    .help("Export raw transcript in various formats")

    // Notes export - conditional
    if meetingState.structuredNotes != nil {
        Menu {
            Button("Copy Notes") { copyStructuredNotes() }
            Button("Save Notes...") { saveStructuredNotes() }
        } label: {
            Label("Export Notes", systemImage: "note.text")
                .font(.system(size: 14))
        }
        .help("Export AI-generated meeting notes")
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
.animation(.easeInOut(duration: 0.3), value: meetingState.structuredNotes != nil)
```

**Key Changes:**
- Use `Label()` with icon + text instead of manual HStack
- Add `.transition()` for smooth appearance of Notes button
- Add `.help()` tooltips for clarity
- Font size 14px for consistency

---

#### 1.3 Add Close Warning During Recording
**File:** `Sources/LookMaNoHands/App/AppDelegate.swift` (lines 354-381, window setup)

**Current Implementation:** Lines 951-975 already have `NSWindowDelegate` extension with `windowShouldClose(_:)`

**Status:** ✅ Already implemented correctly

**Verification:** Test that closing window during recording shows alert with:
- Message: "Recording in Progress"
- Info: "Are you sure you want to stop recording and close this window?"
- Buttons: "Stop & Close" / "Cancel"

---

#### 1.4 Add Cancel Button for Note Generation
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (lines 327-354)

**Current Implementation:**
```swift
Button {
    if meetingState.isAnalyzing {
        cancelAnalysis()
    } else {
        showPromptEditor = true
    }
} label: {
    HStack {
        Image(systemName: meetingState.isAnalyzing ? "xmark.circle.fill" : "sparkles")
        Text(meetingState.isAnalyzing
            ? "Cancel (\(Int(meetingState.generationProgress * 100))%)"
            : (meetingState.structuredNotes != nil ? "Re-Generate Notes" : "Generate Notes")
        )
    }
}
.overlay(alignment: .bottom) {
    if meetingState.isAnalyzing && meetingState.isStreaming {
        ProgressView(value: meetingState.generationProgress)
            .progressViewStyle(.linear)
            .tint(.blue)
            .frame(height: 4)
            .padding(.horizontal, 2)
            .padding(.bottom, -2)
    }
}
```

**Status:** ✅ Already implemented with cancel functionality

**Improvement Needed:** Make progress more visible

**Better Design:**
```swift
Button {
    if meetingState.isAnalyzing {
        cancelAnalysis()
    } else {
        showPromptEditor = true
    }
} label: {
    HStack(spacing: 6) {
        if meetingState.isAnalyzing {
            ProgressView()
                .scaleEffect(0.6)
                .progressViewStyle(.circular)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
        }

        Text(meetingState.isAnalyzing
            ? "Cancel (\(Int(meetingState.generationProgress * 100))%)"
            : (meetingState.structuredNotes != nil ? "Re-Generate Notes" : "Generate Notes")
        )
        .font(.system(size: 14))
    }
}
.disabled(meetingState.segments.isEmpty || meetingState.isRecording)
.animation(.easeInOut(duration: 0.2), value: meetingState.isAnalyzing)
```

**Key Changes:**
- Replace thin progress bar overlay with **circular progress indicator inside button**
- Shows spinning wheel instead of static percentage
- More visible and standard macOS pattern
- Smooth animation when state changes

---

### Phase 2: Visual Polish & Accessibility (Week 2 - 5-6 hours)

#### 2.1 Typography Hierarchy
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (add at top)

**Add Font Extensions:**
```swift
extension Font {
    // Craft.do-inspired typography scale
    static let meetingTitle = Font.system(size: 16, weight: .semibold)
    static let meetingBody = Font.system(size: 16, weight: .regular)
    static let meetingMetadata = Font.system(size: 14, weight: .regular)
    static let meetingCaption = Font.system(size: 13, weight: .regular)
    static let meetingTimestamp = Font.system(size: 13, design: .monospaced, weight: .medium)
}

extension Color {
    // Semantic colors that adapt to light/dark mode
    static let meetingPrimary = Color(nsColor: .labelColor)
    static let meetingSecondary = Color(nsColor: .secondaryLabelColor)
    static let meetingTertiary = Color(nsColor: .tertiaryLabelColor)
    static let meetingAccent = Color.accentColor
    static let meetingBackground = Color(nsColor: .textBackgroundColor)
    static let meetingChrome = Color(nsColor: .controlBackgroundColor)
}
```

**Apply Throughout:**
- Header title: `.font(.meetingTitle)` (line 130)
- Transcript text: `.font(.meetingBody)` (line 249)
- Status messages: `.font(.meetingMetadata)` (line 151)
- Timestamps: `.font(.meetingTimestamp)` (line 246)
- Helper text: `.font(.meetingCaption)`

---

#### 2.2 Spacing System (8pt Grid)
**Apply to All Sections:**

**Header (lines 125-136):**
```swift
.padding(.horizontal, 20)  // 8pt grid: 2.5 units
.padding(.top, 12)         // 8pt grid: 1.5 units
.padding(.bottom, 16)      // 8pt grid: 2 units
```

**Status Bar (lines 140-201):**
```swift
.padding(.horizontal, 20)  // 8pt grid: 2.5 units
.padding(.vertical, 12)    // 8pt grid: 1.5 units
```

**Transcript View (lines 205-276):**
```swift
.padding(.vertical, 16)    // 8pt grid: 2 units (top/bottom)

// Individual segments:
.padding(.horizontal, 24)  // 8pt grid: 3 units
.padding(.vertical, 12)    // 8pt grid: 1.5 units
```

**Controls (lines 280-403):**
```swift
.padding(.horizontal, 20)  // 8pt grid: 2.5 units
.padding(.vertical, 16)    // 8pt grid: 2 units
```

**Spacing Scale Reference:**
```
4px  = 0.5 units (tight spacing)
6px  = 0.75 units (button internal padding)
8px  = 1 unit (standard gap)
12px = 1.5 units (medium spacing)
16px = 2 units (section spacing)
20px = 2.5 units (side margins)
24px = 3 units (content padding)
32px = 4 units (large sections)
```

---

#### 2.3 Simplified Empty State
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (lines 209-240)

**Current Issues:**
- Too many elements (7 total)
- Visual hierarchy unclear
- Arrow + CTA text redundant

**Improved Design:**
```swift
private var emptyStateView: some View {
    VStack(spacing: 24) {
        Spacer()

        // Icon with pulse effect
        Image(systemName: "waveform.circle")
            .font(.system(size: 64, weight: .ultraLight))
            .foregroundStyle(.tertiary)
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.pulse, options: .repeating.speed(0.5))

        // Combined title + subtitle
        VStack(spacing: 8) {
            Text("Ready to Record")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)

            Text("Captures system audio and microphone")
                .font(.meetingMetadata)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(48)
}
```

**Key Changes:**
- Reduced from 7 elements to 3 (icon, title+subtitle, button is below)
- Icon size 64pt (not 72pt - less overwhelming)
- Removed arrow + CTA text (button below is obvious)
- Cleaner, less cluttered appearance

---

#### 2.4 VoiceOver Labels
**Add `.accessibilityLabel()` to All Interactive Elements:**

**Recording Indicator (status bar, line 145):**
```swift
Circle()
    .fill(.red)
    .frame(width: 8, height: 8)
    .accessibilityLabel("Recording in progress")
```

**Status Message (line 150):**
```swift
Text(meetingState.statusMessage)
    .font(.meetingMetadata)
    .foregroundColor(.secondary)
    .accessibilityLiveRegion(.polite)  // Announce changes
```

**Timer (line 194):**
```swift
Text(formatTime(meetingState.elapsedTime))
    .font(.meetingTimestamp)
    .accessibilityLabel("Elapsed time: \(formatTime(meetingState.elapsedTime))")
    .accessibilityValue("\(Int(meetingState.elapsedTime / 60)) minutes")
```

**Transcript Segments (line 243):**
```swift
HStack(alignment: .top, spacing: 12) {
    Text(formatTimestamp(segment.startTime))
        .accessibilityLabel("Time \(formatTimestamp(segment.startTime))")

    Text(segment.text)
        .accessibilityLabel("Transcript: \(segment.text)")
}
.accessibilityElement(children: .combine)
```

**All Buttons:**
```swift
Button("Start Recording") { ... }
    .accessibilityHint("Begins recording system audio and microphone")

Button("Clear") { ... }
    .accessibilityHint("Clears all transcript segments with confirmation")

Button("Generate Notes") { ... }
    .accessibilityHint("Creates AI-generated summary of the meeting")
```

---

#### 2.5 Keyboard Shortcuts
**Add to `body` view:**

```swift
var body: some View {
    VStack(spacing: 0) {
        // ... existing layout
    }
    .keyboardShortcut(.space, modifiers: []) { handleRecordingToggle() }
    .keyboardShortcut("e", modifiers: .command) { showExportMenu() }
    .keyboardShortcut("n", modifiers: .command) { showPromptEditor = true }
    .keyboardShortcut("k", modifiers: .command) { showClearConfirmation = true }
}

private func handleRecordingToggle() {
    if meetingState.isRecording {
        Task { await stopRecording() }
    } else {
        Task { await startRecording() }
    }
}

private func showExportMenu() {
    // Programmatically trigger export menu
    // Note: SwiftUI menus can't be triggered programmatically easily
    // Consider showing a sheet with export options instead
}
```

**Keyboard Shortcuts Reference:**
- **Space**: Toggle recording (start/stop)
- **⌘E**: Export (show export options)
- **⌘N**: Generate notes (open prompt editor)
- **⌘K**: Clear transcript (with confirmation)
- **⌘W**: Close window (system default)
- **Esc**: Dismiss sheets/dialogs (system default)

---

### Phase 3: Advanced Features (Week 3 - Optional)

#### 3.1 Preset System for Note Generation
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (lines 777-959, prompt editor sheet)

**Current Design:**
- Shows large text editor with default prompt
- "Advanced Prompt" disclosure group for jargon terms
- Overwhelming for first-time users

**Improved Design:**
```swift
private var promptEditorSheet: some View {
    VStack(spacing: 0) {
        // Header
        HStack {
            Text("Generate Meeting Notes")
                .font(.system(size: 20, weight: .semibold))
            Spacer()
            Button {
                showPromptEditor = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(24)

        Divider()

        // Content
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose a style")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        presetCard(
                            title: "Quick Summary",
                            description: "Key points and action items",
                            icon: "list.bullet.circle.fill",
                            color: .blue,
                            preset: .quickSummary
                        )

                        presetCard(
                            title: "Detailed Notes",
                            description: "Full summary with context",
                            icon: "doc.text.fill",
                            color: .purple,
                            preset: .detailedNotes
                        )
                    }
                }

                Divider()

                // Customization (collapsed by default)
                DisclosureGroup(
                    isExpanded: $showCustomization,
                    content: {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Domain-Specific Terms")
                                    .font(.system(size: 14, weight: .medium))

                                TextEditor(text: $jargonTerms)
                                    .font(.system(size: 14))
                                    .frame(height: 80)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.3))
                                    )

                                Text("Add technical terms or acronyms (comma-separated)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 16)
                    },
                    label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                    }
                )

                // Model info
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                    Text("Using model: \(Settings.shared.ollamaModel)")
                        .font(.system(size: 13))
                }
                .foregroundColor(.secondary)
            }
            .padding(24)
        }

        Divider()

        // Footer
        HStack {
            Button("Cancel") {
                showPromptEditor = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if showCustomization {
                Button("Generate with Custom Settings") {
                    generateWithCustomSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
    .frame(width: 600, height: 500)
}

private func presetCard(
    title: String,
    description: String,
    icon: String,
    color: Color,
    preset: NotePreset
) -> some View {
    Button {
        generateWithPreset(preset)
    } label: {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.meetingChrome.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
}

@State private var showCustomization = false

private func generateWithPreset(_ preset: NotePreset) {
    showPromptEditor = false
    Task {
        await generateStructuredNotes(with: preset.prompt)
    }
}

private func generateWithCustomSettings() {
    showPromptEditor = false
    Task {
        await generateStructuredNotes(with: buildFinalPrompt())
    }
}
```

**Key Features:**
- **Two preset cards** as primary choices
- **Progressive disclosure** for customization
- **Clear visual hierarchy** (large icons, distinct colors)
- **Reduced cognitive load** (choose intent, not edit raw prompt)

---

#### 3.2 Window Improvements
**File:** `Sources/LookMaNoHands/App/AppDelegate.swift` (lines 354-381)

**Current Window Setup:**
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false
)
```

**Improved Setup:**
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),  // Larger default
    styleMask: [.titled, .closable, .miniaturizable, .resizable],  // Add resizable
    backing: .buffered,
    defer: false
)

window.title = "Meeting Transcription"
window.minSize = NSSize(width: 600, height: 450)  // Minimum comfortable size
window.maxSize = NSSize(width: 1400, height: 1200)  // Maximum reasonable size
window.setFrameAutosaveName("MeetingTranscriptionWindow")  // Remember position/size
```

**Key Changes:**
- Default size increased to 800x600 (more breathing room)
- Added `.resizable` to allow user adjustment
- Min size 600x450 (prevents unusable small sizes)
- Max size 1400x1200 (prevents ridiculous large sizes)
- Auto-save frame (remembers user's preferred size/position)

**Update SwiftUI View:**
```swift
var body: some View {
    VStack(spacing: 0) {
        // ... existing layout
    }
    .frame(minWidth: 600, minHeight: 450)  // Match NSWindow min size
    // Remove .frame(width: 700, height: 500) - let window control size
}
```

---

#### 3.3 Hover Effects on Transcript Segments (OPTIONAL - DEFER)
**Recommendation:** Skip this for initial implementation. Only add if user feedback requests it.

**Rationale:**
- Adds complexity without clear benefit
- Most users won't discover hover actions
- Copy functionality already available via right-click
- Focus on core UX improvements first

---

## Testing Checklist

### Tier 1 (Critical UX)
- [ ] Clear confirmation dialog appears with correct segment count
- [ ] Export buttons are distinct and labeled correctly
- [ ] Close warning appears during recording
- [ ] Cancel button works during note generation (test with long operation)
- [ ] All buttons have correct disabled states

### Tier 2 (Polish & Accessibility)
- [ ] Typography is consistent throughout (16px body, 14px metadata, 13px captions)
- [ ] Spacing uses 8pt grid (20px margins, 16px section gaps)
- [ ] Empty state is clean and not overwhelming
- [ ] VoiceOver reads all elements correctly
- [ ] Keyboard shortcuts work (Space, ⌘E, ⌘N, ⌘K)
- [ ] Tab navigation flows logically through controls

### Tier 3 (Advanced)
- [ ] Preset cards are visually distinct and clickable
- [ ] Customization disclosure group expands/collapses smoothly
- [ ] Window resizes gracefully (test at 600x450 and 1400x1200)
- [ ] Window position/size is remembered across sessions

### Cross-Cutting Concerns
- [ ] All changes work in both light and dark mode
- [ ] No performance degradation with 100+ transcript segments
- [ ] All animations are smooth (200-400ms, no jank)
- [ ] Error states display helpful messages
- [ ] Long microphone names truncate with ellipsis

---

## What NOT to Implement

### ❌ Craft.do Glass Effects on Window Chrome
**Why:** Text readability is paramount. Glass materials reduce contrast.

**Exception:** Recording indicator already uses `.ultraThinMaterial` correctly (it's a floating overlay).

**Keep:** Standard macOS backgrounds:
- `.textBackgroundColor` for content areas
- `.controlBackgroundColor` for chrome (status bar, controls)

---

### ❌ Custom Translucent Button Styles
**Why:** macOS `.borderedProminent` is clearer and more accessible.

**Keep:** System button styles with proper `.buttonStyle()` modifiers

---

### ❌ Over-Designed Empty State
**Why:** 7 elements (icon, title, subtitle, warning, arrow, CTA, button) is too many.

**Use:** 3 elements (icon, combined title+subtitle, button below)

---

### ❌ Hover Actions on Every Segment
**Why:** Adds complexity without clear user benefit. Defer unless requested.

---

## File Structure Reference

### Files to Modify
1. **`Sources/LookMaNoHands/Views/MeetingView.swift`** (primary file)
   - Lines 1-50: Add font/color extensions
   - Lines 125-136: Header improvements
   - Lines 140-201: Status bar refinements
   - Lines 209-240: Simplified empty state
   - Lines 243-276: Transcript segment styling
   - Lines 280-403: Controls with improved buttons
   - Lines 777-959: Preset-based prompt editor

2. **`Sources/LookMaNoHands/App/AppDelegate.swift`**
   - Lines 354-381: Window configuration (size, resizable, autosave)
   - Lines 951-975: Window delegate (already has close warning)

### Files Created
- This plan document: `docs/plans/issue-26-meeting-window-ui-improvements.md`

### Files Referenced (Do Not Modify)
- `Sources/LookMaNoHands/Views/RecordingIndicator.swift` (already has proper styling)
- `Sources/LookMaNoHands/Models/AppState.swift` (used by MeetingState)
- `Sources/LookMaNoHands/Services/WhisperService.swift` (transcription backend)

---

## Implementation Time Estimates

### Tier 1: Critical UX (2-3 hours)
- Split export buttons: 30 min
- Improved cancel button: 1 hour
- Verification testing: 30 min

### Tier 2: Polish & Accessibility (5-6 hours)
- Typography system: 30 min
- Spacing system: 1 hour
- Simplified empty state: 20 min
- VoiceOver labels: 2 hours
- Keyboard shortcuts: 1 hour
- Testing: 1 hour

### Tier 3: Advanced (Optional, 3-4 hours)
- Preset system: 2 hours
- Window improvements: 30 min
- Testing: 1 hour

**Total: 10-13 hours for complete implementation**

---

## Success Criteria

### Before Implementation
- UX Score: 7.5/10 - Functional but plain
- Accessibility: 4/10 - Missing labels and keyboard nav
- Visual Polish: 6/10 - Basic system styling

### After Tier 1
- UX Score: 8.5/10 - Critical safety nets in place
- Key wins: Confirmations, clear export, cancellation

### After Tier 2
- UX Score: 9/10 - Professional, accessible, polished
- Accessibility: 9/10 - Comprehensive support
- Visual Polish: 8/10 - Clean, native-feeling

### After Tier 3
- UX Score: 9.5/10 - Best-in-class meeting transcription
- Key wins: Preset system reduces cognitive load

---

## Notes for Build Agent

### Prerequisites
- Xcode Command Line Tools installed (working as of this plan)
- Swift 5.9+ (current: 6.2.3)
- Branch: `polish-ux-ui` (already has waveform improvements)

### Build Commands
```bash
# From project root directory
swift build -c release
./deploy.sh
```

### Testing
```bash
# Launch app
open ~/Applications/"Look Ma No Hands.app"

# Test recording
# 1. Press Caps Lock to start dictation (waveform should appear)
# 2. Open Meeting Transcription window
# 3. Test all new features
```

### Common Issues
1. **Build hangs:** Xcode beta toolchain issue - already resolved
2. **VoiceOver testing:** Enable in System Settings > Accessibility > VoiceOver
3. **Dark mode testing:** System Settings > Appearance

### Reference Documents
- Original issue: https://github.com/qaid/look-ma-no-hands/issues/26
- Waveform improvements: `docs/waveform-improvements.md`
- Project context: `CLAUDE.md`

---

## Approval Status

**Research:** ✅ Complete (3 specialized agents)
**Design:** ✅ Complete (UX audit passed)
**Plan:** ✅ Complete (this document)
**Ready for Implementation:** ✅ Yes

**Next Step:** Implement Tier 1 (2-3 hours) for immediate UX wins, then Tier 2 (5-6 hours) for full polish.
