# Implementation Roadmap

## Overview

This roadmap breaks the project into phases with specific, actionable tasks. Each task includes acceptance criteria.

---

## Phase 1: Foundation

**Goal**: Create a working menu bar app shell with proper permissions handling.

### Task 1.1: Project Setup
- [ ] Create Package.swift with correct dependencies
- [ ] Create basic directory structure
- [ ] Verify project builds with `swift build`

**Acceptance Criteria**: Running `swift build` completes without errors.

### Task 1.2: Basic Menu Bar App
- [ ] Create main app entry point
- [ ] Create AppDelegate for menu bar setup
- [ ] Display menu bar icon (system microphone icon initially)
- [ ] Create dropdown menu with "Quit" option

**Acceptance Criteria**: App launches, shows icon in menu bar, can be quit from menu.

### Task 1.3: Microphone Permission
- [ ] Add Info.plist with NSMicrophoneUsageDescription
- [ ] Create permission request flow
- [ ] Handle permission denied state
- [ ] Show permission status in menu

**Acceptance Criteria**: App prompts for microphone permission on first launch, handles denial gracefully.

### Task 1.4: Accessibility Permission
- [ ] Create accessibility permission check
- [ ] Guide user to System Preferences if needed
- [ ] Implement permission polling to detect when granted
- [ ] Show permission status in menu

**Acceptance Criteria**: App detects accessibility permission status and guides user to grant it.

### Task 1.5: Ollama Detection
- [ ] Check if Ollama is running (ping localhost:11434)
- [ ] Show status in menu bar dropdown
- [ ] Provide guidance if Ollama not detected

**Acceptance Criteria**: App correctly detects Ollama presence and shows appropriate status.

---

## Phase 2: Core Recording

**Goal**: Implement keyboard capture and audio recording with visual feedback.

### Task 2.1: Keyboard Monitor (Caps Lock)
- [ ] Create CGEvent tap for keyboard events
- [ ] Detect Caps Lock key press
- [ ] Toggle recording state on Caps Lock
- [ ] Handle permission requirements

**Acceptance Criteria**: Pressing Caps Lock toggles internal recording state (logged to console).

### Task 2.2: Keyboard Monitor Fallback
- [ ] If Caps Lock capture fails, implement Right Option fallback
- [ ] Make trigger key configurable in code

**Acceptance Criteria**: Recording can be triggered by fallback key if Caps Lock fails.

### Task 2.3: Audio Capture
- [ ] Set up AVAudioEngine
- [ ] Configure input format (16kHz, mono)
- [ ] Capture audio to buffer during recording
- [ ] Stop and return buffer when recording ends

**Acceptance Criteria**: Audio can be captured and saved to a test file for verification.

### Task 2.4: Recording Indicator Window
- [ ] Create floating window (always on top)
- [ ] Design minimal recording indicator (red dot or similar)
- [ ] Show window when recording starts
- [ ] Hide window when recording stops
- [ ] Position window appropriately (near cursor or corner)

**Acceptance Criteria**: Visual indicator appears during recording and disappears after.

---

## Phase 3: Transcription

**Goal**: Convert recorded audio to text using local Whisper model.

### Task 3.1: Whisper.cpp Integration
- [ ] Add whisper.cpp as dependency (or include source)
- [ ] Create Swift bridging for whisper.cpp
- [ ] Test basic transcription functionality

**Acceptance Criteria**: Can transcribe a test audio file via Swift code.

### Task 3.2: Model Management
- [ ] Download Whisper base model on first run (or bundle with app)
- [ ] Store model in appropriate location
- [ ] Load model at app startup

**Acceptance Criteria**: Model loads successfully, transcription works.

### Task 3.3: Transcription Pipeline
- [ ] Connect audio buffer output to Whisper input
- [ ] Run transcription on background thread
- [ ] Return transcribed text

**Acceptance Criteria**: Recorded audio is transcribed to text (logged to console).

### Task 3.4: Basic Text Insertion
- [ ] Copy transcribed text to clipboard
- [ ] Simulate Cmd+V paste
- [ ] Test with various applications

**Acceptance Criteria**: Transcribed text appears in active text field after recording.

---

## Phase 4: Smart Formatting

**Goal**: Add AI-powered formatting via local LLM.

### Task 4.1: Ollama HTTP Client
- [ ] Create HTTP client for Ollama API
- [ ] Implement generate endpoint call
- [ ] Handle response parsing
- [ ] Handle errors (connection refused, timeout)

**Acceptance Criteria**: Can send prompt to Ollama and receive response.

### Task 4.2: Formatting Prompts
- [ ] Design base formatting prompt
- [ ] Test prompt effectiveness with various inputs
- [ ] Optimize prompt for speed and quality

**Acceptance Criteria**: Raw dictation is transformed into properly formatted text.

### Task 4.3: Context-Aware Formatting
- [ ] Detect content type from transcription (email, note, code comment, etc.)
- [ ] Adjust formatting based on detected type
- [ ] Allow format hints in dictation (e.g., "email to John...")

**Acceptance Criteria**: Different types of dictation receive appropriate formatting.

### Task 4.4: Formatting Integration
- [ ] Insert formatting step between transcription and text insertion
- [ ] Handle Ollama unavailable (fall back to raw text)
- [ ] Show processing indicator during formatting

**Acceptance Criteria**: Full pipeline works: record → transcribe → format → insert.

---

## Phase 5: Polish

**Goal**: Complete the user experience with settings and error handling.

### Task 5.1: Settings Window
- [ ] Create settings window UI
- [ ] Trigger key selection
- [ ] Whisper model selection (if multiple available)
- [ ] Ollama model selection
- [ ] Permission status display

**Acceptance Criteria**: Users can view and modify app settings.

### Task 5.2: Settings Persistence
- [ ] Save settings to UserDefaults
- [ ] Load settings on app startup
- [ ] Apply settings changes immediately

**Acceptance Criteria**: Settings persist across app restarts.

### Task 5.3: Error Handling
- [ ] Display user-friendly error notifications
- [ ] Log errors for debugging
- [ ] Never lose transcribed text (copy to clipboard as fallback)

**Acceptance Criteria**: All error scenarios handled gracefully with user feedback.

### Task 5.4: Performance Optimization
- [ ] Profile transcription time
- [ ] Profile formatting time
- [ ] Optimize any bottlenecks
- [ ] Ensure UI remains responsive

**Acceptance Criteria**: Total processing time is acceptable for interactive use.

### Task 5.5: Menu Bar Polish
- [ ] Custom app icon
- [ ] Recording state reflected in menu bar icon
- [ ] Recent transcription history in menu (optional)

**Acceptance Criteria**: Menu bar provides clear status and quick actions.

---

## Post-MVP: Future Enhancements

These are not required for the initial release but could be added later:

- [ ] Multiple language support
- [ ] Custom vocabulary/corrections
- [ ] Transcription history with search
- [ ] Audio feedback (beeps)
- [ ] Edit transcription before inserting
- [ ] Embedded llama.cpp (remove Ollama dependency)
- [ ] Automatic model download/update
- [ ] Keyboard shortcut customization UI

---

## Testing Checklist

### Before Each Phase Completion

- [ ] Build succeeds: `swift build`
- [ ] App launches without crash
- [ ] All phase features work as described
- [ ] Error cases handled (permissions denied, services unavailable)

### Final Testing

- [ ] Test in Mail.app
- [ ] Test in Notes.app
- [ ] Test in Safari (web forms)
- [ ] Test in Terminal
- [ ] Test in VS Code
- [ ] Test in Slack
- [ ] Test with long dictation (2+ minutes)
- [ ] Test with short dictation (few words)
- [ ] Test error recovery

---

## Time Estimates

| Phase | Estimated Duration |
|-------|-------------------|
| Phase 1: Foundation | 3-5 days |
| Phase 2: Core Recording | 4-6 days |
| Phase 3: Transcription | 5-7 days |
| Phase 4: Smart Formatting | 3-5 days |
| Phase 5: Polish | 3-5 days |
| **Total** | **3-5 weeks** |

Note: Estimates assume part-time development and may vary based on familiarity with Swift/macOS development.
