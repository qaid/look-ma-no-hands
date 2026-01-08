# Look Ma No Hands - Claude Code Context

This file provides context for Claude Code sessions working on this project.

## Project Overview

**Look Ma No Hands** is a macOS application that provides:
1. **System-wide voice dictation** - Press Caps Lock to toggle recording, speak, and the transcribed + formatted text is inserted into any active input field
2. **Meeting transcription** (planned) - Record system audio during video calls and produce structured, actionable meeting notes

## Core Requirements

| Requirement | Description |
|-------------|-------------|
| Platform | macOS only |
| Trigger | Caps Lock key toggles recording (with fallback to alternative key if needed) |
| Scope | System-wide - works in any application, any input field |
| Transcription | 100% local using whisper.cpp |
| Formatting | Rule-based capitalization and punctuation |
| Interface | Menu bar icon + floating recording indicator + settings window |
| Privacy | No cloud services - everything runs on user's Mac |

## Technology Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Language | Swift | Required for macOS system integration |
| UI Framework | SwiftUI | Modern, declarative UI |
| Build System | Swift Package Manager | No Xcode required |
| Whisper Engine | whisper.cpp via SwiftWhisper | C++ library with Swift bindings |
| Smart Formatting | Rule-based | Capitalization and punctuation (LLM support planned) |
| Audio | AVFoundation | Apple's native audio framework |
| System Audio Capture | ScreenCaptureKit (planned) | For meeting transcription mode |

## Key Technical Decisions

1. **Swift is required** (not optional) because we need:
   - `CGEvent` APIs for system-wide keyboard monitoring
   - `AXUIElement` Accessibility APIs for text insertion
   - `NSStatusBar` for menu bar presence
   - `NSWindow` for floating indicator

2. **Rule-based formatting first, LLM optional** because:
   - Fast and deterministic for basic dictation
   - No external dependencies
   - Can add Ollama integration later for advanced formatting
   - Privacy-focused (no data processing overhead)

3. **Caps Lock with fallback** because:
   - User's preferred trigger key
   - macOS treats Caps Lock specially, may need alternative
   - Fallback options: Right Option, double-tap Fn, or custom shortcut

## Project Structure

```
LookMaNoHands/
├── CLAUDE.md                     # This file - Claude Code context
├── Package.swift                 # Swift Package Manager config
├── README.md                     # User-facing documentation
├── PERFORMANCE.md                # Core ML optimization guide
├── deploy.sh                     # Automated build and deployment script
├── Resources/
│   └── AppIcon.icns              # App icon
├── Sources/
│   └── LookMaNoHands/
│       ├── App/
│       │   ├── LookMaNoHandsApp.swift    # Main app entry
│       │   └── AppDelegate.swift         # Menu bar setup and coordination
│       ├── Views/
│       │   ├── RecordingIndicator.swift  # Floating indicator window
│       │   └── SettingsView.swift        # Settings window (permissions, models, about)
│       ├── Services/
│       │   ├── KeyboardMonitor.swift         # Caps Lock detection
│       │   ├── AudioRecorder.swift           # Microphone capture
│       │   ├── WhisperService.swift          # Whisper transcription
│       │   ├── TextFormatter.swift           # Rule-based formatting
│       │   └── TextInsertionService.swift    # Paste into apps
│       ├── Models/
│       │   └── AppState.swift                # App state management
│       └── Resources/
│           └── (model files downloaded to ~/.whisper/models/)
```

## Implementation Phases

### Phase 1: Foundation ✅ COMPLETED
- [x] Project setup with Swift Package Manager
- [x] Basic menu bar app shell
- [x] Microphone permission request
- [x] Accessibility permission request
- [x] Custom app icon integration

### Phase 2: Core Recording ✅ COMPLETED
- [x] Keyboard monitoring (Caps Lock detection)
- [x] Audio capture from microphone
- [x] Floating recording indicator window
- [x] Menu bar recording toggle

### Phase 3: Transcription ✅ COMPLETED
- [x] Integrate whisper.cpp library via SwiftWhisper
- [x] Model download system (tiny model with Core ML)
- [x] Audio-to-text pipeline with Core ML acceleration
- [x] Text insertion via Accessibility APIs

### Phase 4: Smart Formatting ✅ COMPLETED (Basic)
- [x] Rule-based capitalization and punctuation
- [ ] Optional Ollama integration for advanced formatting (future)

### Phase 5: Polish ✅ COMPLETED
- [x] Settings window UI (permissions, models, about tabs)
- [x] Real-time permission status checking
- [x] Performance optimization (Core ML, tiny model)
- [x] Automated deployment script (deploy.sh)
- [x] Documentation (README, PERFORMANCE, CLAUDE)

---

## Future Phases: Meeting Transcription Mode

### Phase 6: System Audio Capture (Planned)
- [ ] Integrate ScreenCaptureKit for system audio recording
- [ ] Request screen recording permission
- [ ] Add audio source selection (microphone vs system audio vs both)
- [ ] Detect active video call applications (Zoom, Meet, Teams)
- [ ] Create "Meeting Mode" toggle in UI

### Phase 7: Long-Form Transcription (Planned)
- [ ] Implement streaming transcription for long recordings
- [ ] Handle audio chunking for continuous transcription
- [ ] Real-time display of transcription in progress
- [ ] Save raw transcript to file (markdown format)

### Phase 8: Meeting Note Structuring (Planned)
- [ ] Integrate Ollama for post-processing transcripts
- [ ] Design prompts for extracting:
  - Meeting participants (speaker diarization)
  - Key discussion topics
  - Action items and owners
  - Decisions made
  - Questions raised
- [ ] Create structured markdown output template
- [ ] Add export options (markdown, PDF, plain text)

### Phase 9: Meeting Mode UX (Planned)
- [ ] Dedicated "Meeting Mode" window with:
  - Start/stop recording controls
  - Real-time transcription display
  - Meeting duration timer
  - Audio level indicators
- [ ] Save meeting notes to ~/Documents/LookMaNoHands/Meetings/
- [ ] Meeting history browser in Settings
- [ ] Search across past meeting notes

### Phase 10: Advanced Features (Future)
- [ ] Speaker identification and labeling
- [ ] Integration with calendar for automatic meeting context
- [ ] Custom formatting templates for different meeting types
- [ ] Automatic highlight detection (important moments)
- [ ] Meeting summary email generation

## Development Guidelines

1. **No Xcode**: Use Swift Package Manager and command-line tools only
2. **Test incrementally**: Each component should be testable in isolation
3. **Handle permissions gracefully**: Guide users through granting access
4. **Fail gracefully**: If Ollama isn't running, offer raw transcription
5. **Privacy first**: Never send data off the device

## Git Commit Guidelines

**IMPORTANT**: When creating git commits for this project:
- **NEVER** include "🤖 Generated with [Claude Code]" footer
- **NEVER** include "Co-Authored-By: Claude Sonnet" attribution
- Write clear, concise commit messages that follow the existing style
- Focus on describing what changed and why, without AI attribution

## Commands

```bash
# Build and deploy (recommended during development)
./deploy.sh

# Manual build for release
swift build -c release

# Run from source (for debugging)
swift run LookMaNoHands

# Launch production app
open ~/Applications/LookMaNoHands.app
```

## Required System Permissions

### Current (Dictation Mode)
1. **Microphone Access** - to capture audio for dictation
2. **Accessibility Access** - to monitor keyboard (Caps Lock) and insert text

### Future (Meeting Mode)
3. **Screen Recording** - required by macOS to capture system audio via ScreenCaptureKit

## Current Dependencies

- **SwiftWhisper** (1.0.0+) - Swift wrapper for whisper.cpp with Core ML support
- **whisper.cpp** - Bundled within SwiftWhisper, provides local transcription
- **Core ML models** - ggml-tiny-encoder.mlmodelc for Neural Engine acceleration

## Future Dependencies (Meeting Mode)

- **Ollama** (optional) - Local LLM for advanced meeting note structuring
  - HTTP client via URLSession
  - API endpoint: http://localhost:11434/api/generate

## Useful Resources

- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- SwiftWhisper: https://github.com/exPHAT/SwiftWhisper
- Ollama: https://ollama.ai
- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
