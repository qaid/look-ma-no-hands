# Look Ma No Hands - Claude Code Context

[Project Docs Index]|root:./.claude
|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
|root:{settings.local.json}
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

---

## Future Advanced Features
- [ ] Save meeting notes to ~/Documents/LookMaNoHands/Meetings/
- [ ] Meeting history browser in Settings
- [ ] Search across past meeting notes
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
- **NEVER** commit and push to GitHub without explicit user request
- Always wait for user confirmation before running `git push`
- Write clear, concise commit messages that follow the existing style
- Focus on describing what changed and why, without AI attribution

**Git Workflow**:
- Commits can be made freely to track progress locally
- Pushing to remote requires explicit user approval
- User will say "commit and push" or "update the repo" when ready

## ALWAYS START WITH THESE COMMANDS FOR COMMON TASKS

**Task: "List/summarize all files and directories"**

```bash
fd . -t f           # Lists ALL files recursively (FASTEST)
# OR
rg --files          # Lists files (respects .gitignore)
```

**Task: "Search for content in files"**

```bash
rg "search_term"    # Search everywhere (FASTEST)
```

**Task: "Find files by name"**

```bash
fd "filename"       # Find by name pattern (FASTEST)
```

### Directory/File Exploration

```bash
# FIRST CHOICE - List all files/dirs recursively:
fd . -t f           # All files (fastest)
fd . -t d           # All directories
rg --files          # All files (respects .gitignore)

# For current directory only:
ls -la              # OK for single directory view
```

### BANNED - Never Use These Slow Tools

* ❌ `tree` - NOT INSTALLED, use `fd` instead
* ❌ `find` - use `fd` or `rg --files`
* ❌ `grep` or `grep -r` - use `rg` instead
* ❌ `ls -R` - use `rg --files` or `fd`
* ❌ `cat file | grep` - use `rg pattern file`

### Use These Faster Tools Instead

```bash
# ripgrep (rg) - content search 
rg "search_term"                # Search in all files
rg -i "case_insensitive"        # Case-insensitive
rg "pattern" -t py              # Only Python files
rg "pattern" -g "*.md"          # Only Markdown
rg -1 "pattern"                 # Filenames with matches
rg -c "pattern"                 # Count matches per file
rg -n "pattern"                 # Show line numbers 
rg -A 3 -B 3 "error"            # Context lines
rg " (TODO| FIXME | HACK)"      # Multiple patterns

# ripgrep (rg) - file listing 
rg --files                      # List files (respects •gitignore)
rg --files | rg "pattern"       # Find files by name 
rg --files -t md                # Only Markdown files 

# fd - file finding 
fd -e js                        # All •js files (fast find) 
fd -x command {}                # Exec per-file 
fd -e md -x ls -la {}           # Example with ls 

# jq - JSON processing 
jq. data.json                   # Pretty-print 
jq -r .name file.json           # Extract field 
jq '.id = 0' x.json             # Modify field
```

### Search Strategy

1. Start broad, then narrow: `rg "partial" | rg "specific"`
2. Filter by type early: `rg -t python "def function_name"`
3. Batch patterns: `rg "(pattern1|pattern2|pattern3)"`
4. Limit scope: `rg "pattern" src/`

### INSTANT DECISION TREE

```
User asks to "list/show/summarize/explore files"?
  → USE: fd . -t f  (fastest, shows all files)
  → OR: rg --files  (respects .gitignore)

User asks to "search/grep/find text content"?
  → USE: rg "pattern"  (NOT grep!)

User asks to "find file/directory by name"?
  → USE: fd "name"  (NOT find!)

User asks for "directory structure/tree"?
  → USE: fd . -t d  (directories) + fd . -t f  (files)
  → NEVER: tree (not installed!)

Need just current directory?
  → USE: ls -la  (OK for single dir)
```


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
