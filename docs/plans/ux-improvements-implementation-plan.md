# UI/UX Improvements Implementation Plan

## Overview

This plan addresses UI/UX improvements for the Look Ma No Hands macOS app based on the comprehensive UX review in `/docs/macos-ui-ux-review.md`. The improvements are organized into modular phases that can be implemented independently, allowing you to pick and choose based on your priorities.

**Current Status:** 7.5/10 overall UX rating
**Target:** 9/10 with HIG compliance and accessibility
**Total Estimated Time:** 36-45 hours across 4 weeks

**Your Primary Goal:** Meeting feature usability (export, confirmations)
**Your Time Budget:** Complete overhaul (implementing all phases)
**Your Immediate Pain Points:**
- Menu bar icon doesn't match system theme
- Accidentally clearing transcripts without warning
- Export options are confusing in Meeting view

**RECOMMENDED START:** Begin with Phase 4 (Meeting View UX) for immediate impact on your primary concerns, then tackle the quick wins in Phase 1 to fix the menu bar icon issue.

---

## Progress Tracking

**Instructions for AI Agents:** Mark tasks with status indicators as you complete them:
- `[ ]` - Not started
- `[IN_PROGRESS]` - Currently working on
- `[✓]` - Completed
- `[SKIPPED]` - Intentionally skipped
- `[BLOCKED]` - Cannot proceed (add note explaining why)

Update the phase completion percentages below as you complete tasks.

### Phase Status Overview

| Phase | Status | Progress | Priority | Time Estimate |
|-------|--------|----------|----------|---------------|
| Phase 1: Menu Bar & Window Management | [ ] | 0/4 tasks | HIGH | 2-3 hours |
| Phase 2: Accessibility & VoiceOver | [ ] | 0/6 tasks | HIGH | 3-4 hours |
| Phase 3: Keyboard Navigation | [ ] | 0/3 tasks | MEDIUM | 2-3 hours |
| Phase 4: Meeting View UX | [ ] | 0/7 tasks | HIGH | 5-7 hours |
| Phase 5: Recording Indicator Customization | [ ] | 0/4 tasks | MEDIUM | 2-3 hours |
| Phase 6: Animation & Visual Polish | [ ] | 0/4 tasks | LOW | 2-3 hours |
| Phase 7: Advanced Transcript Interaction | [ ] | 0/2 tasks | LOW | 2-3 hours |
| Phase 8: Documentation & Testing | [ ] | 0/6 tasks | MEDIUM | 4-6 hours |

**Overall Completion:** 0/34 tasks (0%)

**Last Updated:** 2026-02-02 (Plan created)

**Current Session Notes:**
```
[AI agents: Add brief notes about what you're working on here]
- Session started: [timestamp]
- Working on: [phase and task numbers]
- Blockers: [any issues encountered]
- Next up: [what to tackle next]
```

---

## Phase Organization Approach

Each phase below is **self-contained** and can be implemented independently. Within each phase, tasks are ordered by:
1. **Impact** (High → Medium → Low)
2. **Effort** (Quick wins first)
3. **Dependencies** (prerequisites listed when needed)

You can:
- ✅ Implement phases in any order
- ✅ Pick individual tasks from different phases
- ✅ Skip phases entirely if not relevant to your goals
- ✅ Combine quick wins from multiple phases for rapid iteration

---

## PHASE 1: Menu Bar & Window Management
**Priority Level:** HIGH
**Time Estimate:** 2-3 hours
**Impact:** Immediate visual polish, HIG compliance
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/4 tasks

### Task Tracking

- [ ] 1.1 Fix Menu Bar Icon Template Mode (5 min)
- [ ] 1.2 Add Standard About Panel (10 min)
- [ ] 1.3 Hide Developer Reset Behind Option Key (15 min)
- [ ] 1.4 Add Window Position Restoration (30 min)

### Tasks

#### 1.1 Fix Menu Bar Icon Template Mode (5 min)
**File:** `Sources/LookMaNoHands/App/AppDelegate.swift:878-892`

**Current Issue:** Emoji icon doesn't adapt to light/dark menu bars

**Change:**
```swift
private func createMenuBarIcon() -> NSImage {
    // Use SF Symbol instead of emoji
    let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
    let image = NSImage(
        systemSymbolName: "waveform.badge.mic",
        accessibilityDescription: "Look Ma No Hands"
    )!.withSymbolConfiguration(config)!

    image.isTemplate = true  // ← KEY CHANGE: Adapts to menu bar theme
    return image
}
```

**Update button setup at line 220:**
```swift
button.image = createMenuBarIcon()  // Replace emojiImage() call
```

**Impact:** High - Fixes visual inconsistency in menu bar theming

---

#### 1.2 Add Standard About Panel (10 min)
**File:** `Sources/LookMaNoHands/App/AppDelegate.swift:214-282`

**Current Issue:** Missing standard "About" menu item

**Add method:**
```swift
@objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Look Ma No Hands",
        .applicationVersion: "0.1.0",
        .version: "",
        .credits: NSAttributedString(string: "Fast, local voice dictation for macOS\n\nPowered by Whisper.cpp and Ollama")
    ])
}
```

**Update menu structure in `setupMenuBar()`:**
```swift
// Add as first item
menu.addItem(NSMenuItem(
    title: "About Look Ma No Hands",
    action: #selector(showAbout),
    keyEquivalent: ""
))

menu.addItem(NSMenuItem.separator())

// ... rest of menu
```

**Impact:** High - HIG compliance requirement

---

#### 1.3 Hide Developer Reset Behind Option Key (15 min)
**File:** `Sources/LookMaNoHands/App/AppDelegate.swift:266-270`

**Current Issue:** Developer tool visible in production menu

**Change:**
```swift
let developerItem = NSMenuItem(
    title: "Developer Reset",
    action: #selector(developerReset),
    keyEquivalent: ""
)
developerItem.isAlternate = true
developerItem.keyEquivalentModifierMask = .option  // Only shows when Option held
menu.addItem(developerItem)
```

**Impact:** Medium - Cleaner menu structure

---

#### 1.4 Add Window Position Restoration (30 min)
**Files:**
- `Sources/LookMaNoHands/App/AppDelegate.swift:309-332` (Settings)
- `Sources/LookMaNoHands/App/AppDelegate.swift:354-381` (Meeting)

**Current Issue:** Windows don't remember position/size across launches

**Changes for Settings window:**
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],  // Add .resizable
    backing: .buffered,
    defer: false
)

window.setFrameAutosaveName("SettingsWindow")  // ← ADD THIS
window.minSize = NSSize(width: 500, height: 400)  // ← ADD THIS
window.maxSize = NSSize(width: 800, height: 800)  // ← ADD THIS

// Only center on first launch
if NSWindow.frameRectForAutosaveName("SettingsWindow") == .zero {
    window.center()
}
```

**Apply same pattern to Meeting window** with name "MeetingWindow"

**Impact:** Medium - Better user experience, professional feel

---

## PHASE 2: Accessibility & VoiceOver Support
**Priority Level:** HIGH
**Time Estimate:** 3-4 hours
**Impact:** Inclusive design, WCAG compliance
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/6 tasks

### Task Tracking

- [ ] 2.1 Audit & Add VoiceOver Labels (1 hour for audit)
- [ ] 2.2 Recording Indicator Accessibility (15 min)
- [ ] 2.3 Settings Tab Picker Accessibility (15 min)
- [ ] 2.4 Onboarding Progress Accessibility (20 min)
- [ ] 2.5 Meeting View Controls Accessibility (30 min)
- [ ] 2.6 VoiceOver Testing Session (1 hour)

### Tasks

#### 2.1 Audit & Add VoiceOver Labels (1 hour for audit)
**Approach:** Systematically review all interactive elements

**Testing procedure:**
1. Enable VoiceOver (⌘F5)
2. Navigate through each view with keyboard
3. Identify missing/unclear labels
4. Document needed changes

---

#### 2.2 Recording Indicator Accessibility (15 min)
**File:** `Sources/LookMaNoHands/Views/RecordingIndicator.swift:41-65`

**Add to main view:**
```swift
WaveformBarsView(frequencyBands: $state.frequencyBands)
    .padding(...)
    .background(...)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Recording in progress")
    .accessibilityValue("Audio level: \(averageLevel)")
    .accessibilityHint("Visual representation of microphone input")

private var averageLevel: String {
    let avg = state.frequencyBands.reduce(0, +) / Float(state.frequencyBands.count)
    if avg > 0.7 { return "High" }
    if avg > 0.3 { return "Medium" }
    return "Low"
}
```

**Impact:** High - Core feature accessible to VoiceOver users

---

#### 2.3 Settings Tab Picker Accessibility (15 min)
**File:** `Sources/LookMaNoHands/Views/SettingsView.swift:53-62`

**Change:**
```swift
Picker("Settings Section", selection: $selectedTab) {  // Add label
    ForEach(SettingsTab.allCases) { tab in
        Label(tab.rawValue, systemImage: tab.icon)
            .tag(tab)
            .accessibilityLabel(tab.rawValue)
            .accessibilityHint("Switch to \(tab.rawValue) settings")
    }
}
.pickerStyle(.segmented)
.padding()
.accessibilityElement(children: .contain)
```

**Impact:** High - Navigation element must be accessible

---

#### 2.4 Onboarding Progress Accessibility (20 min)
**File:** `Sources/LookMaNoHands/Views/OnboardingView.swift:68-71`

**Add:**
```swift
ProgressIndicatorView(currentStep: onboardingState.currentStep)
    .frame(maxWidth: .infinity)
    .background(Color(NSColor.windowBackgroundColor))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Setup progress: Step \(currentStep.rawValue + 1) of 5")
```

**Impact:** Medium - Better onboarding experience for screen reader users

---

#### 2.5 Meeting View Controls Accessibility (30 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift` (multiple locations)

**Add labels to:**
- Start/Stop button (lines 240-256)
- Clear button (lines 259-267)
- Generate Notes button (lines 270-307)
- Export menu (lines 312-346)
- Microphone picker (lines 127-158)
- Timer display (lines 112-122)

**Example for Start/Stop button:**
```swift
Button {
    if meetingState.isRecording {
        Task { await stopRecording() }
    } else {
        Task { await startRecording() }
    }
} label: {
    HStack {
        Image(systemName: meetingState.isRecording ? "stop.circle.fill" : "record.circle")
        Text(meetingState.isRecording ? "Stop Recording" : "Start Recording")
    }
}
.accessibilityLabel(meetingState.isRecording
    ? "Stop recording. Currently recording for \(formatTime(elapsedTime))"
    : "Start recording system audio and microphone")
.accessibilityHint("Tap to \(meetingState.isRecording ? "stop" : "start") meeting transcription")
```

**Impact:** High - Critical for Meeting feature accessibility

---

#### 2.6 VoiceOver Testing Session (1 hour)
**Process:**
1. Test complete app flow with VoiceOver enabled
2. Verify all buttons/controls are announced correctly
3. Check tab order makes logical sense
4. Ensure status messages are read aloud
5. Document any remaining issues

**Impact:** High - Validation of accessibility work

---

## PHASE 3: Keyboard Navigation & Shortcuts
**Priority Level:** MEDIUM
**Time Estimate:** 2-3 hours
**Impact:** Power user efficiency
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/3 tasks

### Task Tracking

- [ ] 3.1 Add Settings Tab Shortcuts (⌘1-6) (30 min)
- [ ] 3.2 Add Keyboard Shortcut Hints to Tab Labels (15 min)
- [ ] 3.3 Full Keyboard Navigation Testing (30 min)

### Tasks

#### 3.1 Add Settings Tab Shortcuts (⌘1-6) (30 min)
**File:** `Sources/LookMaNoHands/Views/SettingsView.swift:87-100`

**Add keyboard event handler:**
```swift
var body: some View {
    VStack(spacing: 0) {
        // ... existing UI
    }
    .frame(minWidth: 550, minHeight: 450)
    .onAppear {
        checkPermissions()
        checkOllamaStatus()
        checkWhisperModelStatus()
        if selectedTab == .permissions {
            startPermissionPolling()
        }
        setupKeyboardShortcuts()  // ← ADD
    }
    .onDisappear {
        stopPermissionPolling()
        removeKeyboardShortcuts()  // ← ADD
    }
}

@State private var keyMonitor: Any?

private func setupKeyboardShortcuts() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
        handleKeyPress(event)
    }
}

private func removeKeyboardShortcuts() {
    if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
    }
}

private func handleKeyPress(_ event: NSEvent) -> NSEvent? {
    guard event.modifierFlags.contains(.command) else { return event }

    switch event.charactersIgnoringModifiers {
    case "1": selectedTab = .general; return nil
    case "2": selectedTab = .recording; return nil
    case "3": selectedTab = .models; return nil
    case "4": selectedTab = .permissions; return nil
    case "5": selectedTab = .diagnostics; return nil
    case "6": selectedTab = .about; return nil
    default: return event
    }
}
```

**Impact:** Medium - Significantly improves keyboard navigation

---

#### 3.2 Add Keyboard Shortcut Hints to Tab Labels (15 min)
**File:** `Sources/LookMaNoHands/Views/SettingsView.swift:53-62`

**Change:**
```swift
Picker("", selection: $selectedTab) {
    ForEach(SettingsTab.allCases.enumerated().map { $0 }, id: \.element) { index, tab in
        Label {
            Text(tab.rawValue)
        } icon: {
            Image(systemName: tab.icon)
        }
        .tag(tab)
        .help("⌘\(index + 1)")  // ← ADD: Shows tooltip on hover
    }
}
```

**Impact:** Medium - Discoverability for keyboard shortcuts

---

#### 3.3 Full Keyboard Navigation Testing (30 min)
**Process:**
1. Test all windows are navigable with Tab/Shift+Tab
2. Verify Escape closes sheets/dialogs
3. Check Return/Space activates default buttons
4. Test arrow keys in pickers/lists
5. Ensure keyboard focus is visible

**Impact:** Medium - Validation of keyboard support

---

## PHASE 4: Meeting View UX Improvements
**Priority Level:** HIGH (YOUR PRIMARY FOCUS)
**Time Estimate:** 5-7 hours
**Impact:** Major usability wins for Meeting feature
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/7 tasks

### Task Tracking

- [ ] 4.1 Add Clear Transcript Confirmation (10 min) - **YOUR PAIN POINT**
- [ ] 4.2 Split Export Menu into Transcript/Notes Buttons (30 min) - **YOUR PAIN POINT**
- [ ] 4.3 Add Close Warning During Recording (30 min) - **YOUR PAIN POINT**
- [ ] 4.4 Improve Empty State Visual Hierarchy (20 min)
- [ ] 4.5 Move Progress Bar to Button Overlay (30 min)
- [ ] 4.6 Add Cancellation Support to Note Generation (1 hour)
- [ ] 4.7 Simplify Prompt Editor with Presets (2 hours)

### Tasks

#### 4.1 Add Clear Transcript Confirmation (10 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:259-267`

**Current:** Instant deletion without warning

**Add state:** `@State private var showClearConfirmation = false`

**Change button:**
```swift
Button {
    showClearConfirmation = true  // Show dialog instead of clearing
} label: {
    HStack {
        Image(systemName: "trash")
        Text("Clear")
    }
}
.disabled(meetingState.segments.isEmpty)
.confirmationDialog(
    "Clear Transcript?",
    isPresented: $showClearConfirmation,
    titleVisibility: .visible
) {
    Button("Clear Transcript", role: .destructive) {
        clearTranscript()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will permanently delete \(meetingState.segments.count) transcript segments.")
}
```

**Impact:** HIGH - Prevents accidental data loss

---

#### 4.2 Split Export Menu into Transcript/Notes Buttons (30 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:312-346`

**Current Issue:** Confusing "Export" → "Export Ready" label change, hidden options

**Replace single menu with:**
```swift
HStack(spacing: 12) {
    // Transcript export (always available if segments exist)
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
    }
    .disabled(meetingState.segments.isEmpty)
    .help("Export raw transcript in various formats")

    // Notes export (only when generated)
    if meetingState.structuredNotes != nil {
        Menu {
            Button("Copy Notes") { copyStructuredNotes() }
            Button("Save Notes...") { saveStructuredNotes() }
        } label: {
            Label("Export Notes", systemImage: "note.text")
        }
        .help("Export AI-generated meeting notes")
    }
}
```

**Impact:** HIGH - Much clearer export options, better discoverability

---

#### 4.3 Add Close Warning During Recording (30 min)
**Files:**
- `Sources/LookMaNoHands/Views/MeetingView.swift:84-90`
- `Sources/LookMaNoHands/App/AppDelegate.swift:948-972`

**Current Issue:** Can close window mid-recording, losing work

**Add to AppDelegate window delegate:**
```swift
extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === meetingWindow else { return true }

        // Check if meeting is recording (need to track this state)
        // For now, add a property: var isMeetingRecording = false
        guard isMeetingRecording else { return true }

        let alert = NSAlert()
        alert.messageText = "Recording in Progress"
        alert.informativeText = "Are you sure you want to stop recording and close this window?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop & Close")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Signal MeetingView to stop recording
            isMeetingRecording = false
            return true
        } else {
            return false  // Cancel close
        }
    }
}
```

**Note:** Requires adding `isMeetingRecording` state tracking between AppDelegate and MeetingView

**Impact:** HIGH - Prevents accidental data loss

---

#### 4.4 Improve Empty State Visual Hierarchy (20 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:178-195`

**Current:** Plain text, no visual hierarchy

**Replace with:**
```swift
VStack(spacing: 16) {
    Image(systemName: "waveform.circle")
        .font(.system(size: 64))
        .foregroundColor(.accentColor)
        .symbolEffect(.pulse, isActive: true)  // Subtle animation

    VStack(spacing: 8) {
        Text("Ready to Record")
            .font(.title2)
            .fontWeight(.semibold)

        Text("Captures system audio and microphone")
            .font(.body)
            .foregroundColor(.secondary)
    }

    // Permission check hint
    if !hasRequiredPermissions {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Screen recording permission required")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding(.top, 4)
    }

    // Visual CTA
    VStack(spacing: 8) {
        Image(systemName: "arrow.down")
            .font(.caption)
            .foregroundColor(.tertiary)

        Text("Click Start Recording below")
            .font(.caption)
            .foregroundColor(.tertiary)
    }
    .padding(.top, 8)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.padding(40)
```

**Add computed property:**
```swift
private var hasRequiredPermissions: Bool {
    // Check screen recording permission
    // Implementation depends on PermissionManager
    return true  // Placeholder
}
```

**Impact:** MEDIUM - More engaging, better guidance

---

#### 4.5 Move Progress Bar to Button Overlay (30 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:270-307`

**Current Issue:** Progress bar below button causes layout shift

**Replace VStack with overlaid progress:**
```swift
Button {
    showPromptEditor = true
} label: {
    HStack {
        Image(systemName: meetingState.isAnalyzing ? "hourglass" : "sparkles")
        Text(meetingState.isAnalyzing
            ? "Analyzing... \(Int(meetingState.generationProgress * 100))%"
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
            .padding(.bottom, -2)  // Slightly outside button bounds
    }
}
.disabled(meetingState.segments.isEmpty || meetingState.isRecording || meetingState.isAnalyzing)
.help(helpText)

private var helpText: String {
    if meetingState.isAnalyzing {
        return "Generating structured notes via Ollama..."
    } else if meetingState.structuredNotes != nil {
        return "Re-generate notes with different settings"
    } else {
        return "Generate AI-powered meeting notes"
    }
}
```

**Impact:** MEDIUM - Smoother UI, no layout shift

---

#### 4.6 Add Cancellation Support to Note Generation (1 hour)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:461-538`

**Current Issue:** No way to cancel generation once started

**Add state:** `@State private var analysisTask: Task<Void, Never>?`

**Change Generate button:**
```swift
Button {
    if meetingState.isAnalyzing {
        cancelAnalysis()  // Cancel if running
    } else {
        showPromptEditor = true  // Start if idle
    }
} label: {
    HStack {
        Image(systemName: meetingState.isAnalyzing ? "xmark.circle.fill" : "sparkles")
        Text(meetingState.isAnalyzing ? "Cancel" : "Generate Notes")
    }
}
.disabled(meetingState.segments.isEmpty || meetingState.isRecording)
```

**Add cancellation logic:**
```swift
private func generateStructuredNotes(with prompt: String) async {
    analysisTask = Task {
        // ... existing generation code

        // Add periodic cancellation checks
        for await chunk in streamingResponse {
            if Task.isCancelled { break }
            // ... process chunk
        }
    }

    await analysisTask?.value
}

private func cancelAnalysis() {
    analysisTask?.cancel()
    analysisTask = nil

    meetingState.isAnalyzing = false
    meetingState.isStreaming = false
    meetingState.statusMessage = "Note generation cancelled"
    resetGenerationState()
}
```

**Impact:** MEDIUM - Better user control, prevents stuck state

---

#### 4.7 Simplify Prompt Editor with Presets (2 hours)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:660-779`

**Current Issue:** Overwhelming for first-time users, unclear use case

**Add preset enum:**
```swift
enum NotePreset {
    case quickSummary
    case detailedNotes

    var prompt: String {
        switch self {
        case .quickSummary:
            return """
            Summarize this meeting transcript concisely:

            ## Key Points
            - List the 3-5 main topics discussed

            ## Action Items
            - List specific tasks and owners

            ## Decisions Made
            - List concrete decisions
            """
        case .detailedNotes:
            return Settings.defaultMeetingPrompt
        }
    }
}
```

**Redesign sheet:**
```swift
private var promptEditorSheet: some View {
    VStack(spacing: 20) {
        // Header (existing)
        HStack {
            Text("Generate Meeting Notes")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                showPromptEditor = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }

        // NEW: Quick generate option
        VStack(alignment: .leading, spacing: 12) {
            Text("What type of notes do you need?")
                .font(.headline)

            HStack(spacing: 12) {
                // Preset 1: Quick summary
                Button {
                    generateWithPreset(.quickSummary)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "list.bullet.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Quick Summary")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Key points and action items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Preset 2: Detailed notes
                Button {
                    generateWithPreset(.detailedNotes)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("Detailed Notes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Full summary with context")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }

        Divider()

        // Existing customization (now secondary, in disclosure group)
        DisclosureGroup(
            isExpanded: $showCustomization,
            content: {
                VStack(alignment: .leading, spacing: 16) {
                    // Existing jargon terms and advanced prompt editor
                    // (Keep existing implementation)
                }
                .padding(.top, 8)
            },
            label: {
                Text("Customize Notes")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        )

        Spacer()

        // Action buttons (only show if customization expanded)
        HStack {
            Button("Cancel") {
                showPromptEditor = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if showCustomization {
                Button("Generate with Custom Settings") {
                    showPromptEditor = false
                    Task {
                        await generateStructuredNotes(with: buildFinalPrompt())
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }
    .padding(24)
    .frame(width: 650, height: 500)
}

@State private var showCustomization = false

private func generateWithPreset(_ preset: NotePreset) {
    showPromptEditor = false
    Task {
        await generateStructuredNotes(with: preset.prompt)
    }
}
```

**Impact:** MEDIUM - Much better first-run experience, clearer use case

---

## PHASE 5: Recording Indicator Customization
**Priority Level:** MEDIUM
**Time Estimate:** 2-3 hours
**Impact:** User preference support, reduced intrusiveness
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/4 tasks

### Task Tracking

- [ ] 5.1 Create IndicatorStyle Enum (15 min)
- [ ] 5.2 Build MinimalRecordingIndicator View (1 hour)
- [ ] 5.3 Update RecordingIndicatorWindowController (1 hour)
- [ ] 5.4 Add Picker to Settings General Tab (15 min)

### Tasks

#### 5.1 Create IndicatorStyle Enum (15 min)
**File:** `Sources/LookMaNoHands/Models/Settings.swift`

**Add enum:**
```swift
enum IndicatorStyle: String, CaseIterable, Identifiable {
    case full = "Full (with waveform)"
    case minimal = "Minimal (dot + timer)"
    case off = "Off"

    var id: String { rawValue }
}
```

**Add property:**
```swift
@AppStorage("indicatorStyle") var indicatorStyle: IndicatorStyle = .full
```

**Impact:** Foundation for customization

---

#### 5.2 Build MinimalRecordingIndicator View (1 hour)
**New File:** `Sources/LookMaNoHands/Views/MinimalRecordingIndicator.swift`

**Create:**
```swift
import SwiftUI

struct MinimalRecordingIndicator: View {
    let elapsedTime: TimeInterval
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseScale)
                .shadow(color: .red.opacity(0.5), radius: 4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseScale = 1.3
                    }
                }

            Text(formatTime(elapsedTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityValue("Duration: \(formatTime(elapsedTime))")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
```

**Impact:** New indicator variant for less intrusive recording

---

#### 5.3 Update RecordingIndicatorWindowController (1 hour)
**File:** Look for `RecordingIndicatorWindowController` (likely in `AppDelegate.swift` or separate file)

**Modify window creation logic:**
```swift
private func setupRecordingIndicator() {
    let style = Settings.shared.indicatorStyle

    guard style != .off else {
        // Don't create indicator if disabled
        recordingIndicatorWindow = nil
        return
    }

    let contentView: NSView

    switch style {
    case .full:
        contentView = NSHostingView(rootView: RecordingIndicator(state: indicatorState))
    case .minimal:
        contentView = NSHostingView(rootView: MinimalRecordingIndicator(elapsedTime: 0))
    case .off:
        return
    }

    // ... rest of window setup
}
```

**Update during recording** to pass elapsed time to minimal indicator

**Impact:** Complete indicator customization system

---

#### 5.4 Add Picker to Settings General Tab (15 min)
**File:** `Sources/LookMaNoHands/Views/SettingsView.swift` (General tab section)

**Add picker:**
```swift
// In General tab content
VStack(alignment: .leading, spacing: 8) {
    Text("Recording Indicator")
        .font(.headline)

    Picker("Indicator Style", selection: $settings.indicatorStyle) {
        ForEach(Settings.IndicatorStyle.allCases) { style in
            Text(style.rawValue).tag(style)
        }
    }
    .pickerStyle(.radioGroup)  // Radio buttons for clear selection

    Text("Choose how the recording indicator appears while dictating")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

**Impact:** User control over indicator visibility/style

---

## PHASE 6: Animation & Visual Polish
**Priority Level:** LOW
**Time Estimate:** 2-3 hours
**Impact:** Delightful interactions, "juice"
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/4 tasks

### Task Tracking

- [ ] 6.1 Add Haptic Feedback on Recording (10 min)
- [ ] 6.2 Add Checkmark Spring Animation (15 min)
- [ ] 6.3 Add Empty State Animation (30 min)
- [ ] 6.4 Add Status Bar Gradient (10 min)

### Tasks

#### 6.1 Add Haptic Feedback on Recording (10 min)
**File:** `Sources/LookMaNoHands/App/AppDelegate.swift:645-675, 752-774`

**Add to start/stop methods:**
```swift
private func startRecording() {
    // Check permissions first
    guard transcriptionState.hasAccessibilityPermission else {
        handleMissingAccessibilityPermission()
        return
    }

    // Haptic feedback on record start
    NSHapticFeedbackManager.defaultPerformer.perform(
        .generic,
        performanceTime: .now
    )

    transcriptionState.startRecording()
    // ... rest of method
}

private func stopRecordingAndTranscribe() {
    NSHapticFeedbackManager.defaultPerformer.perform(
        .generic,
        performanceTime: .now
    )

    // ... rest of method
}
```

**Impact:** LOW - Nice tactile feedback on Macs with Force Touch trackpads

---

#### 6.2 Add Checkmark Spring Animation (15 min)
**File:** `Sources/LookMaNoHands/Views/OnboardingView.swift:109-114`

**Add state:** `@State private var checkmarkScale: CGFloat = 1.0`

**Update checkmark:**
```swift
if step.rawValue < currentStep.rawValue {
    Image(systemName: "checkmark")
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.white)
        .scaleEffect(checkmarkScale)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                checkmarkScale = 1.2
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) {
                checkmarkScale = 1.0
            }
        }
}
```

**Impact:** LOW - Delightful onboarding polish

---

#### 6.3 Add Empty State Animation (30 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:180-195`

**Update empty state icon:**
```swift
Image(systemName: "waveform.circle")
    .font(.system(size: 64))
    .foregroundColor(.accentColor)
    .symbolEffect(.variableColor.iterative, isActive: true)  // macOS 14+
```

**Add transition:**
```swift
VStack(spacing: 16) {
    // ... content
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.padding(40)
.transition(.opacity.combined(with: .scale))
```

**Impact:** LOW - More engaging empty state

---

#### 6.4 Add Status Bar Gradient (10 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:109-170`

**Update background:**
```swift
private var statusBar: some View {
    HStack {
        // ... existing content
    }
    .padding(.horizontal)
    .padding(.vertical, 10)  // Increase from 8
    .background(
        LinearGradient(
            colors: [
                Color(NSColor.controlBackgroundColor),
                Color(NSColor.controlBackgroundColor).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    )
}
```

**Impact:** LOW - Subtle visual depth

---

## PHASE 7: Advanced Transcript Interaction
**Priority Level:** LOW
**Time Estimate:** 2-3 hours
**Impact:** Power user features
**Dependencies:** None
**Status:** [ ] Not Started | Progress: 0/2 tasks

### Task Tracking

- [ ] 7.1 Add Hover Actions to Transcript Segments (1 hour)
- [ ] 7.2 Add Copy Timestamp Function (30 min)

### Tasks

#### 7.1 Add Hover Actions to Transcript Segments (1 hour)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift:196-213`

**Add state:** `@State private var hoveredSegment: UUID?`

**Update segment view:**
```swift
HStack(alignment: .top, spacing: 12) {
    // Timestamp (clickable to copy)
    Button {
        copyTimestamp(segment.startTime)
    } label: {
        Text(formatTimestamp(segment.startTime))
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
    }
    .buttonStyle(.plain)
    .help("Click to copy timestamp")
    .frame(width: 60, alignment: .leading)

    // Text with hover actions
    HStack(alignment: .top, spacing: 8) {
        Text(segment.text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

        // Show actions on hover
        if hoveredSegment == segment.id {
            VStack(spacing: 4) {
                Button {
                    copySegment(segment)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy this segment")
            }
            .transition(.opacity)
        }
    }
}
.padding(.vertical, 4)
.onHover { isHovered in
    hoveredSegment = isHovered ? segment.id : nil
}
```

**Impact:** LOW - Nice for power users, not critical

---

#### 7.2 Add Copy Timestamp Function (30 min)
**File:** `Sources/LookMaNoHands/Views/MeetingView.swift`

**Add methods:**
```swift
private func copyTimestamp(_ time: TimeInterval) {
    let timestamp = formatTimestamp(time)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(timestamp, forType: .string)

    // Optional: Show toast notification
    meetingState.statusMessage = "Timestamp copied"
}

private func copySegment(_ segment: TranscriptSegment) {
    let text = "[\(formatTimestamp(segment.startTime))] \(segment.text)"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    meetingState.statusMessage = "Segment copied"
}
```

**Impact:** LOW - Convenience feature

---

## PHASE 8: Documentation & Testing
**Priority Level:** MEDIUM
**Time Estimate:** 4-6 hours
**Impact:** Validation, maintainability
**Dependencies:** Complete PHASE 1-4 first
**Status:** [ ] Not Started | Progress: 0/6 tasks

### Task Tracking

- [ ] 8.1 VoiceOver Regression Testing (1 hour)
- [ ] 8.2 Keyboard Navigation Testing (30 min)
- [ ] 8.3 Window Management Testing (30 min)
- [ ] 8.4 Update README with Keyboard Shortcuts (30 min)
- [ ] 8.5 Create Accessibility Guide (1 hour)
- [ ] 8.6 Update CLAUDE.md (30 min)

### Tasks

#### 8.1 VoiceOver Regression Testing (1 hour)
**Process:**
1. Enable VoiceOver (⌘F5)
2. Test complete app flow:
   - Onboarding wizard
   - Settings window (all tabs)
   - Recording trigger
   - Meeting transcription
3. Document any issues
4. Fix critical blockers

**Impact:** HIGH - Validation of accessibility work

---

#### 8.2 Keyboard Navigation Testing (30 min)
**Process:**
1. Disconnect mouse
2. Navigate entire app with keyboard only
3. Test all shortcuts (⌘1-6, ⌘,, etc.)
4. Verify focus indicators visible
5. Check tab order makes sense

**Impact:** MEDIUM - Validation of keyboard support

---

#### 8.3 Window Management Testing (30 min)
**Process:**
1. Open Settings → Move/Resize → Quit → Reopen
2. Verify position/size restored
3. Test with multiple displays
4. Check min/max size constraints

**Impact:** MEDIUM - Validation of window restoration

---

#### 8.4 Update README with Keyboard Shortcuts (30 min)
**File:** `README.md`

**Add section:**
```markdown
## Keyboard Shortcuts

### Global
- **Caps Lock** (or custom hotkey): Start/Stop dictation
- **⌘,**: Open Settings
- **⌘Q**: Quit

### Settings Window
- **⌘1**: General tab
- **⌘2**: Recording tab
- **⌘3**: Models tab
- **⌘4**: Permissions tab
- **⌘5**: Diagnostics tab
- **⌘6**: About tab

### Meeting Transcription
- **⌘M**: Open Meeting window
- **Space**: Start/Stop recording (when focused)
- **⌘S**: Save transcript
```

**Impact:** MEDIUM - User documentation

---

#### 8.5 Create Accessibility Guide (1 hour)
**New File:** `docs/accessibility.md`

**Content:**
- VoiceOver support overview
- Keyboard navigation guide
- Known limitations
- Reporting accessibility issues

**Impact:** MEDIUM - Inclusive documentation

---

#### 8.6 Update CLAUDE.md (30 min)
**File:** `CLAUDE.md`

**Add sections:**
- New keyboard shortcuts
- Indicator style options
- Meeting UX improvements
- Accessibility features

**Impact:** LOW - Developer documentation

---

## Critical Files Reference

### High-Touch Files (Most Changes)
1. **AppDelegate.swift** - Menu bar, windows, haptics
2. **MeetingView.swift** - Export, confirmations, empty state, presets
3. **SettingsView.swift** - Tab shortcuts, accessibility, indicator picker
4. **RecordingIndicator.swift** - Accessibility labels

### New Files to Create
1. **MinimalRecordingIndicator.swift** - New indicator variant
2. **docs/accessibility.md** - Accessibility guide (optional)

### Configuration Files
1. **Settings.swift** - Add `IndicatorStyle` enum

---

## Verification Checklist

After implementing any phase, verify:

**General:**
- [ ] App builds and runs without errors
- [ ] No new warnings introduced
- [ ] Existing functionality still works

**UI/UX:**
- [ ] Changes look good in light and dark mode
- [ ] Text is readable at all sizes
- [ ] Animations are smooth (not janky)
- [ ] Spacing/alignment is consistent

**Accessibility:**
- [ ] VoiceOver announces all interactive elements
- [ ] Focus order makes logical sense
- [ ] Keyboard shortcuts work as expected
- [ ] Color contrast meets WCAG AA standards

**Edge Cases:**
- [ ] Test with no permissions granted
- [ ] Test with no microphone connected
- [ ] Test with Ollama not running
- [ ] Test with very long transcripts

---

## Quick Wins Summary

**YOUR IMMEDIATE PRIORITIES** (addresses your specific pain points):

| Task | Time | Impact | Phase | Addresses |
|------|------|--------|-------|-----------|
| Add Clear confirmation | 10 min | HIGH | 4.1 | ✅ Accidental transcript clearing |
| Split Export menu | 30 min | HIGH | 4.2 | ✅ Confusing export options |
| Fix menu bar icon template | 5 min | HIGH | 1.1 | ✅ Icon theme mismatch |
| Add Close warning during recording | 30 min | HIGH | 4.3 | Prevents data loss |

**RECOMMENDED FIRST SESSION (1.5 hours):** Implement these four tasks for immediate, noticeable improvement to your Meeting workflow.

---

**ALL QUICK WINS** (if you want maximum impact with minimal time):

| Task | Time | Impact | Phase |
|------|------|--------|-------|
| Fix menu bar icon template | 5 min | HIGH | 1.1 |
| Add About panel | 10 min | HIGH | 1.2 |
| Add Clear confirmation | 10 min | HIGH | 4.1 |
| Split Export menu | 30 min | HIGH | 4.2 |
| Add window restoration | 30 min | MEDIUM | 1.4 |
| Add VoiceOver labels | 1 hour | HIGH | 2.1-2.5 |

**Total: ~2.5 hours for substantial UX improvement**

---

## Implementation Strategy

### RECOMMENDED FOR YOU: Approach D - Meeting-First Complete Overhaul

Based on your goals (Meeting feature usability + complete overhaul), here's the optimal implementation order:

**Week 1 (7-9 hours): Meeting Feature + Critical Fixes**
1. **Day 1 (1.5 hours):** Your immediate pain points
   - Fix menu bar icon (5 min)
   - Add Clear confirmation (10 min)
   - Split Export menu (30 min)
   - Add close warning (30 min)

2. **Day 2-3 (5.5 hours):** Complete Phase 4 (Meeting View UX)
   - Improve empty state (20 min)
   - Move progress bar to overlay (30 min)
   - Add cancellation support (1 hour)
   - Simplify prompt editor with presets (2 hours)
   - Test Meeting workflow end-to-end (1 hour)

**Week 2 (8-10 hours): Menu Bar, Windows & Accessibility**
- Complete Phase 1 (Menu Bar & Windows) - 2 hours remaining
- Complete Phase 2 (Accessibility & VoiceOver) - 3-4 hours
- Complete Phase 8.1-8.3 (Testing) - 2 hours

**Week 3 (10-12 hours): Navigation & Customization**
- Complete Phase 3 (Keyboard Navigation) - 2-3 hours
- Complete Phase 5 (Recording Indicator Customization) - 2-3 hours
- Complete Phase 7 (Advanced Transcript Interaction) - 2-3 hours
- VoiceOver regression testing - 1 hour

**Week 4 (8-10 hours): Polish & Documentation**
- Complete Phase 6 (Animation & Visual Polish) - 2-3 hours
- Complete Phase 8.4-8.6 (Documentation) - 2 hours
- Final regression testing - 2 hours
- Performance & memory testing - 2 hours

---

### Alternative Approaches

#### Approach A: By Priority
1. Implement all HIGH priority tasks first (Phases 1, 2, 4)
2. Then MEDIUM priority (Phases 3, 5, 8)
3. Finally LOW priority polish (Phases 6, 7)

#### Approach B: By Feature Area
1. Complete Menu Bar & Windows (Phase 1)
2. Complete Meeting View (Phase 4)
3. Complete Accessibility (Phase 2)
4. Complete Keyboard Nav (Phase 3)
5. Polish (Phases 5, 6, 7)

#### Approach C: Quick Iterations
1. Do all 5-15 min tasks across phases
2. Do all 30 min tasks
3. Do all 1 hour tasks
4. Do all multi-hour tasks

**Your Best Fit:** Approach D (Meeting-First Complete Overhaul) - addresses your pain points first, then systematically improves everything else.

---

## Notes

- Each phase is **independent** - implement in any order
- Tasks within phases can be **cherry-picked** individually
- All time estimates are **approximate** - adjust based on familiarity
- **Test frequently** - don't batch all changes before testing
- Consider **user feedback** - priorities may shift based on real usage

---

## For AI Agents: Progress Tracking Instructions

### How to Track Your Progress

When implementing tasks from this plan, follow these guidelines to maintain accurate progress tracking:

#### 1. Before Starting a Phase

Update the Phase Status Overview table:
```markdown
| Phase 4: Meeting View UX | [IN_PROGRESS] | 0/7 tasks | HIGH | 5-7 hours |
```

Update the phase header:
```markdown
**Status:** [IN_PROGRESS] In Progress | Progress: 0/7 tasks
```

#### 2. When Starting a Task

Mark the task as in progress:
```markdown
- [IN_PROGRESS] 4.1 Add Clear Transcript Confirmation (10 min) - **YOUR PAIN POINT**
```

#### 3. When Completing a Task

Mark the task as complete and update counters:
```markdown
- [✓] 4.1 Add Clear Transcript Confirmation (10 min) - **YOUR PAIN POINT**
```

Update the phase progress:
```markdown
**Status:** [IN_PROGRESS] In Progress | Progress: 1/7 tasks (14%)
```

Update the Phase Status Overview table:
```markdown
| Phase 4: Meeting View UX | [IN_PROGRESS] | 1/7 tasks | HIGH | 5-7 hours |
```

Update the overall completion:
```markdown
**Overall Completion:** 1/34 tasks (3%)
```

#### 4. When Completing a Phase

Update the phase status:
```markdown
**Status:** [✓] Completed | Progress: 7/7 tasks (100%)
```

Update the Phase Status Overview table:
```markdown
| Phase 4: Meeting View UX | [✓] | 7/7 tasks | HIGH | 5-7 hours |
```

#### 5. If You Need to Skip or Block a Task

Mark with appropriate status and add a note:
```markdown
- [SKIPPED] 4.7 Simplify Prompt Editor with Presets (2 hours)
  **Reason:** User decided current prompt editor is sufficient

- [BLOCKED] 4.3 Add Close Warning During Recording (30 min)
  **Blocker:** Need to clarify state management approach with user first
```

#### 6. Always Update the Timestamp

At the end of your session, update the "Last Updated" field:
```markdown
**Last Updated:** 2026-02-02 14:30 UTC (Completed Phase 4, tasks 4.1-4.3)
```

### Example Progress Update Session

**Before:**
```markdown
**Overall Completion:** 0/34 tasks (0%)

| Phase 4: Meeting View UX | [ ] | 0/7 tasks | HIGH | 5-7 hours |

- [ ] 4.1 Add Clear Transcript Confirmation (10 min)
- [ ] 4.2 Split Export Menu into Transcript/Notes Buttons (30 min)
```

**After completing two tasks:**
```markdown
**Overall Completion:** 2/34 tasks (6%)
**Last Updated:** 2026-02-02 14:30 UTC

| Phase 4: Meeting View UX | [IN_PROGRESS] | 2/7 tasks | HIGH | 5-7 hours |

**Status:** [IN_PROGRESS] In Progress | Progress: 2/7 tasks (29%)

- [✓] 4.1 Add Clear Transcript Confirmation (10 min)
- [✓] 4.2 Split Export Menu into Transcript/Notes Buttons (30 min)
- [ ] 4.3 Add Close Warning During Recording (30 min)
```

### Status Indicators Reference

| Indicator | Meaning | When to Use |
|-----------|---------|-------------|
| `[ ]` | Not started | Task hasn't been attempted yet |
| `[IN_PROGRESS]` | Currently working | You're actively implementing this task right now |
| `[✓]` | Completed | Task is fully implemented and tested |
| `[SKIPPED]` | Intentionally skipped | User or agent decided not to implement (add reason) |
| `[BLOCKED]` | Cannot proceed | External dependency or clarification needed (add blocker info) |

### Benefits of Progress Tracking

1. **Continuity:** Another AI agent can resume work seamlessly
2. **Transparency:** User can see exactly what's been done
3. **Efficiency:** Avoid duplicate work or confusion about status
4. **Debugging:** If issues arise, know which changes were made
5. **Motivation:** Visual progress encourages completion

### Commit Progress Updates

After making significant progress (completing 2-3 tasks or finishing a phase), commit your progress updates to the plan file:

```bash
git add ~/.claude/plans/modular-dancing-muffin.md
git commit -m "Update UX implementation plan progress: completed Phase 4 tasks 4.1-4.3"
```

This ensures the progress tracking persists across sessions.

---

**Plan Version:** 1.0
**Created:** 2026-02-02
**Based On:** `/docs/macos-ui-ux-review.md` (UX Review)
**Progress Tracking:** Enabled (see instructions above)
