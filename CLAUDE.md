# Look Ma No Hands - Claude Code Context

[Project Docs Index]|root:./.claude
|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
|root:{settings.local.json}
|references:{cli-tools.md}
|agents:{build-orchestrator.md,git-workflow.md,macos-app-designer.md,security-review.md,swiftui-expert.md,ux-review.md,web-research-synthesizer.md}
|skills/claude-skills-optimizer:{SKILL.md}
|skills/claude-skills-optimizer/references:{optimization-checklist.md,vercel-findings.md}
|skills/git-workflow:{SKILL.md}
|skills/macos-app-design:{SKILL.md}
|skills/macos-app-design/references:{macos-design-guide.md}
|skills/security-review:{SKILL.md}
|skills/swiftui-expert-skill:{SKILL.md}
|skills/swiftui-expert-skill/references:{animation-advanced.md,animation-basics.md,animation-transitions.md,image-optimization.md,layout-best-practices.md,liquid-glass.md,list-patterns.md,modern-apis.md,performance-patterns.md,scroll-patterns.md,sheet-navigation-patterns.md,state-management.md,text-formatting.md,view-structure.md}
|skills/ux-review:{SKILL.md}
|skills/web-research-synthesizer:{SKILL.md}

## Project Overview

**Look Ma No Hands** - macOS menu bar app for system-wide voice dictation and meeting transcription.

**Core Features**:
- Press Caps Lock → Record → Speak → Auto-insert formatted text anywhere
- Meeting mode (active): System audio capture + structured notes via Ollama
- 100% local processing (whisper.cpp + optional Ollama)

**Tech Stack**: Swift + SwiftUI + SPM | whisper.cpp (via SwiftWhisper 1.0.0+) | Ollama (optional) | AVFoundation + ScreenCaptureKit

**System Permissions**: Microphone + Accessibility (dictation) | Screen Recording (meeting mode)

## Key Architecture

**Why Swift?**: Required for `CGEvent` (keyboard monitoring), `AXUIElement` (text insertion), `NSStatusBar` (menu bar), `ScreenCaptureKit` (system audio capture)

**Structure**: `App/` (entry + delegate) | `Views/` (indicator, settings, onboarding) | `Services/` (audio, whisper, formatting, text insertion, meeting analysis) | `Models/` (state)

**Key Services**: `WhisperService`, `TextFormatter`, `TextInsertionService`, `KeyboardMonitor`, `AudioRecorder`, `SystemAudioRecorder`, `MeetingAnalyzer`, `OllamaService`, `ContinuousTranscriber`, `MixedAudioRecorder`

## Build & Deploy

```bash
./deploy.sh                    # Build + deploy to ~/Applications (recommended)
swift build -c release         # Manual release build
swift run LookMaNoHands        # Run from source (debugging)
open ~/Applications/LookMaNoHands.app  # Launch production app
```

## Project-Specific Rules

### Git Commits
- **NEVER** add "🤖 Generated with Claude Code" footer
- **NEVER** add "Co-Authored-By: Claude Sonnet" attribution
- **NEVER** push to GitHub without explicit user request
- Wait for user confirmation before `git push`
- Write clear commit messages matching existing style

### Development Guidelines
- **No Xcode**: Use Swift Package Manager + CLI tools only
- **Privacy first**: All processing stays local on user's Mac
- **Test incrementally**: Each component testable in isolation
- **Graceful failures**: If Ollama isn't running, offer raw transcription
- **Handle permissions**: Guide users through granting system access

## Technical Constraints

| Constraint | Details |
|------------|---------|
| Platform | macOS 14+ (Sonoma) for @Observable macro |
| No Xcode | SPM command-line only |
| Local only | No cloud services, no data leaves device |
| Caps Lock trigger | Preferred key (with fallback to Right Option/Fn if needed) |

## Current Dependencies

- **SwiftWhisper** (1.0.0+) - whisper.cpp with Core ML support
- **Ollama** (optional) - Local LLM for meeting note structuring (http://localhost:11434/api/generate)

## Useful Resources

- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- SwiftWhisper: https://github.com/exPHAT/SwiftWhisper
- Ollama: https://ollama.ai
- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
