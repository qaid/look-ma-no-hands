# Decision Log

This document records key decisions made during project planning, including context, options considered, and rationale.

---

## Decision 1: Programming Language

**Date**: Project inception

**Context**: Need to build a macOS app that can capture keyboard events system-wide and insert text into any application.

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| Swift | Native macOS APIs, best performance, full system access | Learning curve if unfamiliar |
| Python | Familiar, easy Whisper integration | Cannot access required macOS APIs |
| Electron | Cross-platform, web technologies | Cannot access low-level macOS APIs |
| React Native | Cross-platform | Limited macOS system integration |

**Decision**: **Swift**

**Rationale**: Swift is not optional for this project. The core requirements (system-wide keyboard capture, text insertion into any app, menu bar presence) all require native macOS APIs that are only accessible from Swift or Objective-C.

---

## Decision 2: Build System

**Date**: Project inception

**Context**: User explicitly wants to avoid Xcode for development.

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| Xcode | Full IDE, visual tools | User explicitly doesn't want this |
| Swift Package Manager | Command-line, works with any editor | Less visual tooling |
| Bazel | Powerful, scalable | Overkill for this project |

**Decision**: **Swift Package Manager**

**Rationale**: SPM is the standard command-line build tool for Swift. It integrates well with Claude Code and allows development without Xcode.

---

## Decision 3: Transcription Engine

**Date**: Project inception

**Context**: Need local speech-to-text capability using Whisper.

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| OpenAI Whisper (Python) | Official implementation | Requires Python runtime, slower |
| whisper.cpp | Fast, C/C++, Apple Silicon optimized | Requires C interop |
| WhisperKit (Apple) | Native Swift, CoreML | Newer, less documentation |

**Decision**: **whisper.cpp**

**Rationale**: whisper.cpp is well-established, fast, optimized for Apple Silicon, and has existing Swift bindings/examples. It avoids the need for a Python runtime.

---

## Decision 4: Local LLM Solution

**Date**: Project inception

**Context**: User wants smart formatting to run 100% locally (no cloud APIs).

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| Ollama | Easy setup, flexible, good ecosystem | Separate app dependency |
| llama.cpp (embedded) | Self-contained app | Complex integration |
| MLX (Apple) | Best Apple Silicon performance | Newer, Apple Silicon only |
| Cloud API (Claude/GPT) | Highest quality | Not local, user rejected |

**Decision**: **Ollama (for now), with option to migrate to llama.cpp later**

**Rationale**: Ollama provides the fastest path to a working prototype. Users install it once, and our app communicates via simple HTTP. If users later want a completely self-contained app, we can migrate to embedded llama.cpp.

---

## Decision 5: Trigger Key

**Date**: Project inception

**Context**: User wants Caps Lock to toggle recording.

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| Caps Lock | User's preference, convenient | macOS treats it specially, complex to capture |
| Right Option | Easy to capture | Different from user's preference |
| Double-tap Fn | Easy, no modifier conflict | Requires timing logic |
| Custom shortcut | Maximum flexibility | Requires UI for configuration |

**Decision**: **Caps Lock with fallback to alternative**

**Rationale**: Attempt Caps Lock first since it's the user's preference. If technical challenges prove too difficult, implement a fallback key (likely Right Option) with minimal friction.

---

## Decision 6: Whisper Model Size

**Date**: Project inception

**Context**: Need to balance transcription accuracy vs. speed and disk space.

**Options Considered**:

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| tiny | 75MB | Fastest | Basic |
| base | 150MB | Fast | Good |
| small | 500MB | Medium | Better |
| medium | 1.5GB | Slow | Great |
| large | 3GB | Slowest | Best |

**Decision**: **Start with "base" model**

**Rationale**: The base model offers a good balance of accuracy and speed for dictation purposes. Users can optionally upgrade to larger models through settings if they need better accuracy.

---

## Decision 7: UI Framework

**Date**: Project inception

**Context**: Need to build menu bar app, floating window, and settings UI.

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| SwiftUI | Modern, declarative, less code | Some AppKit features need bridging |
| AppKit | Full control, mature | More verbose, imperative |
| Hybrid | Best of both worlds | Two paradigms to manage |

**Decision**: **SwiftUI with AppKit bridging where needed**

**Rationale**: SwiftUI is the modern standard and works well for most UI needs. For specific features like menu bar integration and special window behaviors, we'll bridge to AppKit as needed.

---

## Decision 8: LLM Model for Formatting

**Date**: Project inception

**Context**: Need to choose which local LLM model to recommend for formatting tasks.

**Options Considered**:

| Model | Size | RAM Needed | Quality |
|-------|------|------------|---------|
| llama3.2:1b | 1.3GB | 4GB | Good |
| llama3.2:3b | 2GB | 6GB | Better |
| phi3:mini | 2.3GB | 6GB | Great |
| mistral:7b | 4GB | 8GB | Excellent |

**Decision**: **Recommend llama3.2:3b as default, support user choice**

**Rationale**: The 3B model provides good formatting quality while remaining fast enough for interactive use. Settings will allow users to choose different models based on their hardware and preferences.

---

## Decision 9: Text Insertion Strategy

**Date**: Project inception

**Context**: Need to insert text into the currently focused input field in any application.

**Options Considered**:

| Option | Pros | Cons |
|--------|------|------|
| Accessibility API only | Clean, direct | May not work in all apps |
| Clipboard + paste only | Universal | Overwrites user's clipboard |
| Keystroke simulation | Works everywhere | Slow, character by character |
| Layered approach | Best reliability | More complex |

**Decision**: **Layered approach (Accessibility → Clipboard → Keystrokes)**

**Rationale**: Try Accessibility API first (cleanest). If that fails, use clipboard + paste (fast fallback). As last resort, simulate keystrokes. This gives us the best chance of working in any application.

---

## Decision 10: Error Handling Philosophy

**Date**: Project inception

**Context**: Define how the app should handle failures gracefully.

**Decision**: **Graceful degradation with user feedback**

**Principles**:
1. If Ollama isn't running, insert raw transcription (don't fail completely)
2. If text insertion fails, copy to clipboard and notify user
3. Always show clear, actionable error messages
4. Never lose the user's transcribed text due to an error

---

## Future Decisions to Make

These decisions will be made during implementation:

1. **Specific whisper.cpp integration method** - Direct C interop vs. wrapper
2. **Audio format details** - Exact buffer sizes, recording limits
3. **Settings storage** - UserDefaults vs. file-based config
4. **Indicator window design** - Exact appearance, animation style
5. **App icon design** - Visual branding
