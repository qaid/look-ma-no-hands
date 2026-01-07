# WhisperDictation - Claude Code Context

This file provides context for Claude Code sessions working on this project.

## Project Overview

**WhisperDictation** is a macOS application that provides system-wide voice dictation with AI-powered smart formatting. Users press Caps Lock to toggle recording, speak, and the transcribed + formatted text is inserted into any active input field.

## Core Requirements

| Requirement | Description |
|-------------|-------------|
| Platform | macOS only |
| Trigger | Caps Lock key toggles recording (with fallback to alternative key if needed) |
| Scope | System-wide - works in any application, any input field |
| Transcription | 100% local using whisper.cpp |
| Formatting | 100% local using Ollama (local LLM) |
| Interface | Menu bar icon + floating recording indicator + settings window |
| Privacy | No cloud services - everything runs on user's Mac |

## Technology Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Language | Swift | Required for macOS system integration |
| UI Framework | SwiftUI | Modern, declarative UI |
| Build System | Swift Package Manager | No Xcode required |
| Whisper Engine | whisper.cpp | C++ library with Swift bindings |
| Smart Formatting | Ollama | Local LLM via HTTP API at localhost:11434 |
| Audio | AVFoundation | Apple's native audio framework |

## Key Technical Decisions

1. **Swift is required** (not optional) because we need:
   - `CGEvent` APIs for system-wide keyboard monitoring
   - `AXUIElement` Accessibility APIs for text insertion
   - `NSStatusBar` for menu bar presence
   - `NSWindow` for floating indicator

2. **Ollama for local LLM** because:
   - Easy to set up and test during development
   - User can choose different models
   - Well-maintained ecosystem
   - Can migrate to embedded llama.cpp later if desired

3. **Caps Lock with fallback** because:
   - User's preferred trigger key
   - macOS treats Caps Lock specially, may need alternative
   - Fallback options: Right Option, double-tap Fn, or custom shortcut

## Project Structure

```
WhisperDictation/
├── CLAUDE.md                     # This file - Claude Code context
├── Package.swift                 # Swift Package Manager config
├── README.md                     # User-facing documentation
├── docs/
│   ├── ARCHITECTURE.md           # Technical architecture details
│   ├── DECISIONS.md              # Decision log with rationale
│   └── ROADMAP.md                # Implementation phases
├── Sources/
│   └── WhisperDictation/
│       ├── App/
│       │   ├── WhisperDictationApp.swift    # Main app entry
│       │   └── AppDelegate.swift            # Menu bar setup
│       ├── Views/
│       │   ├── MenuBarView.swift            # Menu bar interface
│       │   ├── RecordingIndicator.swift     # Floating indicator
│       │   └── SettingsView.swift           # Settings window
│       ├── Services/
│       │   ├── KeyboardMonitor.swift        # Caps Lock detection
│       │   ├── AudioRecorder.swift          # Microphone capture
│       │   ├── WhisperService.swift         # Transcription
│       │   ├── OllamaService.swift          # Local LLM formatting
│       │   └── TextInsertionService.swift   # Paste into apps
│       ├── Models/
│       │   ├── TranscriptionState.swift     # App state
│       │   └── Settings.swift               # User preferences
│       └── Resources/
│           └── whisper-model/               # Whisper model files
```

## Implementation Phases

### Phase 1: Foundation
- [ ] Project setup with Swift Package Manager
- [ ] Basic menu bar app shell
- [ ] Microphone permission request
- [ ] Accessibility permission request
- [ ] Ollama availability check

### Phase 2: Core Recording
- [ ] Keyboard monitoring (Caps Lock detection)
- [ ] Audio capture from microphone
- [ ] Floating recording indicator window

### Phase 3: Transcription
- [ ] Integrate whisper.cpp library
- [ ] Download/bundle Whisper model
- [ ] Audio-to-text pipeline
- [ ] Basic text insertion via clipboard

### Phase 4: Smart Formatting
- [ ] Ollama HTTP client
- [ ] Formatting prompt design
- [ ] Context-aware text transformation

### Phase 5: Polish
- [ ] Settings window UI
- [ ] Error handling and user feedback
- [ ] Performance optimization

## Development Guidelines

1. **No Xcode**: Use Swift Package Manager and command-line tools only
2. **Test incrementally**: Each component should be testable in isolation
3. **Handle permissions gracefully**: Guide users through granting access
4. **Fail gracefully**: If Ollama isn't running, offer raw transcription
5. **Privacy first**: Never send data off the device

## Commands

```bash
# Build the project
swift build

# Run the app
swift run WhisperDictation

# Build for release
swift build -c release
```

## Required System Permissions

The app needs these permissions (requested at runtime):
1. **Microphone Access** - to capture audio
2. **Accessibility Access** - to monitor keyboard and insert text

## Dependencies to Research/Add

- whisper.cpp Swift bindings or C interop
- HTTP client for Ollama communication (URLSession or similar)

## Useful Resources

- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- Ollama: https://ollama.ai
- Ollama API: http://localhost:11434/api/generate
