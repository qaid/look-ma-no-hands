# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        User's Mac                                │
│                   (100% Local Processing)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │  Menu Bar    │    │   Floating   │    │    Settings      │   │
│  │    Icon      │    │  Indicator   │    │     Window       │   │
│  └──────┬───────┘    └──────┬───────┘    └────────┬─────────┘   │
│         │                   │                     │              │
│         └───────────────────┼─────────────────────┘              │
│                             │                                    │
│                    ┌────────▼────────┐                           │
│                    │   App Core      │                           │
│                    │  (Swift/SwiftUI)│                           │
│                    └────────┬────────┘                           │
│                             │                                    │
│         ┌───────────────────┼───────────────────┐                │
│         │                   │                   │                │
│  ┌──────▼──────┐    ┌───────▼───────┐   ┌──────▼──────┐         │
│  │  Keyboard   │    │    Audio      │   │    Text     │         │
│  │  Monitor    │    │   Capture     │   │  Insertion  │         │
│  │ (Caps Lock) │    │ (Microphone)  │   │(Accessibility│         │
│  └─────────────┘    └───────┬───────┘   └─────────────┘         │
│                             │                                    │
│                    ┌────────▼────────┐                           │
│                    │  whisper.cpp    │                           │
│                    │  (Local Model)  │                           │
│                    └────────┬────────┘                           │
│                             │                                    │
│                             │ Raw transcription                  │
│                             ▼                                    │
│                    ┌─────────────────┐                           │
│                    │     Ollama      │◄── Runs as local service  │
│                    │  (Local LLM)    │    on localhost:11434     │
│                    └────────┬────────┘                           │
│                             │                                    │
│                             │ Formatted text                     │
│                             ▼                                    │
│                    ┌─────────────────┐                           │
│                    │  Insert into    │                           │
│                    │  Active App     │                           │
│                    └─────────────────┘                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Keyboard Monitor (KeyboardMonitor.swift)

**Purpose**: Detect Caps Lock key press system-wide

**Technology**: CGEvent tap

**Key APIs**:
- `CGEvent.tapCreate()` - Create event tap
- `CGEventMask` - Filter for key events
- `kCGEventFlagsChanged` - Detect modifier key changes

**Challenges**:
- Caps Lock is a modifier key, handled differently by macOS
- May need to intercept and suppress the normal Caps Lock behavior
- Requires Accessibility permissions

**Fallback**: If Caps Lock proves problematic, support Right Option key or custom shortcut

### 2. Audio Recorder (AudioRecorder.swift)

**Purpose**: Capture microphone audio during recording

**Technology**: AVFoundation

**Key APIs**:
- `AVAudioEngine` - Audio processing graph
- `AVAudioInputNode` - Microphone input
- `AVAudioPCMBuffer` - Audio data buffer

**Output Format**:
- 16kHz sample rate (Whisper requirement)
- Mono channel
- 16-bit PCM or Float32

**Permissions**: Requires microphone access (NSMicrophoneUsageDescription in Info.plist)

### 3. Whisper Service (WhisperService.swift)

**Purpose**: Convert audio to text using local Whisper model

**Technology**: whisper.cpp

**Integration Options**:
1. Direct C interop via Swift's C bridging
2. Use existing Swift wrapper (whisper.swiftui or similar)
3. Shell out to whisper CLI (simplest but slowest)

**Model Selection**:
| Model | Size | Use Case |
|-------|------|----------|
| tiny | 75MB | Testing, very fast |
| base | 150MB | Default - good balance |
| small | 500MB | Better accuracy if needed |

**Model Location**: `Resources/whisper-model/ggml-base.bin`

### 4. Ollama Service (OllamaService.swift)

**Purpose**: Format raw transcription using local LLM

**Technology**: HTTP client to Ollama API

**Endpoint**: `POST http://localhost:11434/api/generate`

**Request Format**:
```json
{
  "model": "llama3.2:3b",
  "prompt": "Format the following dictated text...",
  "stream": false
}
```

**Response Format**:
```json
{
  "response": "Formatted text here..."
}
```

**Error Handling**:
- If Ollama not running: Show notification, offer raw text
- If model not installed: Guide user to install via Ollama

### 5. Text Insertion Service (TextInsertionService.swift)

**Purpose**: Insert formatted text into the active application's input field

**Technology**: Accessibility APIs + Clipboard fallback

**Strategy** (in order of attempt):
1. **Accessibility API**: Find focused element, set value directly
2. **Clipboard + Paste**: Copy to clipboard, simulate Cmd+V
3. **Key simulation**: Type characters one by one (last resort)

**Key APIs**:
- `AXUIElement` - Accessibility element
- `AXUIElementCopyAttributeValue` - Get focused element
- `AXUIElementSetAttributeValue` - Set text value
- `NSPasteboard` - Clipboard access
- `CGEvent` - Key simulation

### 6. User Interface

#### Menu Bar (MenuBarView.swift)
- Status item with microphone icon
- Dropdown menu with:
  - Recording status
  - Quick settings
  - Open full settings
  - Quit

#### Recording Indicator (RecordingIndicator.swift)
- Small floating window (always on top)
- Appears when recording starts
- Shows visual feedback (pulsing dot, waveform, or similar)
- Disappears when recording stops

#### Settings Window (SettingsView.swift)
- Trigger key selection
- Whisper model selection
- Ollama model selection
- Formatting preferences
- Permission status display

## Data Flow

```
1. User presses Caps Lock
         │
         ▼
2. KeyboardMonitor detects press
         │
         ▼
3. Recording starts
   - RecordingIndicator appears
   - AudioRecorder begins capturing
         │
         ▼
4. User presses Caps Lock again
         │
         ▼
5. Recording stops
   - AudioRecorder returns audio buffer
         │
         ▼
6. WhisperService processes audio
   - Returns raw transcription
         │
         ▼
7. OllamaService formats text
   - Returns formatted text
         │
         ▼
8. TextInsertionService inserts text
   - RecordingIndicator disappears
```

## State Management

Use a central `TranscriptionState` observable object:

```swift
enum RecordingState {
    case idle
    case recording
    case processing
    case error(String)
}

@Observable
class TranscriptionState {
    var recordingState: RecordingState = .idle
    var lastTranscription: String?
    var lastFormattedText: String?
}
```

## Error Handling Strategy

| Error | User Feedback | Fallback |
|-------|---------------|----------|
| No microphone permission | Show system dialog | Cannot proceed |
| No accessibility permission | Show instructions | Cannot proceed |
| Whisper model missing | Offer to download | Cannot proceed |
| Ollama not running | Show notification | Insert raw text |
| Ollama model not installed | Show instructions | Insert raw text |
| Text insertion failed | Show notification | Copy to clipboard |

## Performance Considerations

1. **Whisper inference**: Run on background thread, not main thread
2. **Ollama request**: Async HTTP, show processing indicator
3. **Audio buffer**: Limit recording duration (e.g., 5 minutes max)
4. **Memory**: Release audio buffers promptly after transcription
