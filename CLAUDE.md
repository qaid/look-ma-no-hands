# Look Ma No Hands - Claude Code Context

[Project Docs Index]|root:./.claude
|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
|root:{settings.local.json,learnings.md}
|references:{cli-tools.md}
|agents:{build-orchestrator.md,git-workflow.md,macos-app-designer.md,security-review.md,swiftui-expert.md,ux-review.md,web-research-synthesizer.md}
|skills/claude-skills-optimizer:{SKILL.md}
|skills/claude-skills-optimizer/references:{optimization-checklist.md,vercel-findings.md}
|skills/git-workflow:{SKILL.md}
|skills/macos-app-design:{SKILL.md}
|skills/macos-app-design/references:{macos-design-guide.md}
|skills/reflect:{SKILL.md}
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
./scripts/deploy.sh            # Build + deploy to ~/Applications (recommended)
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

## Content Search Tool Policy

**This project prefers ripgrep (rg) for content search** - faster, respects .gitignore, and matches all examples in this file.

**Preference Order:**
1. **FIRST CHOICE**: `Bash("rg 'pattern'")` - Use this when ripgrep is available
2. **FALLBACK**: Grep tool - Use only if ripgrep unavailable or fails
3. **AVOID**: bash `grep` commands - Slowest option, use rg or Grep tool instead

**When Grep tool is acceptable:**
- Ripgrep is not installed on the system (`which rg` returns empty)
- The `rg` command fails with an error
- Working in a different project without ripgrep
- User's environment doesn't have rg available

**Why prefer rg in this project:**
- Faster than grep or Grep tool on large codebases
- Respects .gitignore by default (cleaner results)
- Project convention - all examples use rg
- Better defaults for TypeScript/React codebases

**Quick verification:**
```bash
which rg  # If this returns a path, prefer rg. If empty, use Grep tool.
```

## ALWAYS START WITH THESE COMMANDS FOR COMMON TASKS

**Task: "List/summarize all files and directories"**

```bash
# PREFER (if available):
fd . -t f           # Lists ALL files recursively (FASTEST)
# OR
rg --files          # Lists files (respects .gitignore)

# FALLBACK (if fd/rg unavailable):
# Use Glob tool with pattern **/*
```

**Task: "Search for content in files"**

```bash
# PREFER (if available):
rg "search_term"    # Search everywhere (FASTEST, project standard)

# FALLBACK (if rg unavailable):
# Use Grep tool
```

**Task: "Find files by name"**

```bash
# PREFER (if available):
fd "filename"       # Find by name pattern (FASTEST)

# FALLBACK (if fd unavailable):
# Use Glob tool with pattern **/filename*
```

### Directory/File Exploration

```bash
# PREFER - List all files/dirs recursively (if available):
fd . -t f           # All files (fastest)
fd . -t d           # All directories
rg --files          # All files (respects .gitignore)

# FALLBACK - If fd/rg unavailable:
# Use Glob tool with appropriate patterns

# For current directory only:
ls -la              # OK for single directory view
```

### Tool Preference Order (This Project)

**Content Search:**
1. ✅ **FIRST CHOICE**: `Bash("rg 'pattern'")` - ripgrep (fastest, respects .gitignore, project convention)
2. ✅ **FALLBACK**: Grep tool - only if rg unavailable or fails
3. ❌ **AVOID**: bash `grep` or `grep -r` commands - slowest option

**File Finding:**
1. ✅ **FIRST CHOICE**: `Bash("fd 'pattern'")` - fd is faster
2. ✅ **FALLBACK**: Glob tool - if fd unavailable
3. ❌ **AVOID**: bash `find` command - slower

**File Listing:**
1. ✅ **FIRST CHOICE**: `Bash("rg --files")` or `Bash("fd . -t f")` - respects .gitignore
2. ✅ **FALLBACK**: Glob tool with `**/*` pattern
3. ❌ **NEVER**: `tree` - NOT INSTALLED on this system

**Availability Check:**
```bash
which rg    # If returns path, use rg. If empty, use Grep tool.
which fd    # If returns path, use fd. If empty, use Glob tool.
```

### Preferred Tools (When Available)

**Use via Bash tool for optimal performance:**

```bash
# ripgrep (rg) - content search (PREFERRED in this project)
Bash("rg 'search_term'")                # Search in all files
Bash("rg -i 'case_insensitive'")        # Case-insensitive
Bash("rg 'pattern' -t ts")              # Only TypeScript files
Bash("rg 'pattern' -t tsx")             # Only TSX (React) files
Bash("rg 'pattern' -g '*.md'")          # Only Markdown
Bash("rg -l 'pattern'")                 # Filenames with matches
Bash("rg -c 'pattern'")                 # Count matches per file
Bash("rg -n 'pattern'")                 # Show line numbers
Bash("rg -A 3 -B 3 'error'")            # Context lines
Bash("rg '(TODO|FIXME|HACK)'")          # Multiple patterns

# ripgrep (rg) - file listing
Bash("rg --files")                      # List files (respects .gitignore)
Bash("rg --files | rg 'pattern'")       # Find files by name
Bash("rg --files -t md")                # Only Markdown files

# fd - file finding (PREFERRED in this project)
Bash("fd -e tsx")                       # All React component files
Bash("fd -e ts")                        # All TypeScript files
Bash("fd -x command {}")                # Exec per-file
Bash("fd -e md -x ls -la {}")           # Example with ls

# jq - JSON processing
Bash("jq . data.json")                  # Pretty-print
Bash("jq -r .name file.json")           # Extract field
Bash("jq '.id = 0' x.json")             # Modify field
```

**Note:** If `rg` or `fd` are unavailable (check with `which rg` or `which fd`), fall back to Grep/Glob tools.

### Search Strategy

When using ripgrep (preferred):
1. Start broad, then narrow: `Bash("rg 'partial' | rg 'specific'")`
2. Filter by type early: `Bash("rg -t tsx 'export function'")` or `Bash("rg -t ts 'interface'")`
3. Batch patterns: `Bash("rg '(pattern1|pattern2|pattern3)'")`
4. Limit scope: `Bash("rg 'pattern' src/")` or `Bash("rg 'pattern' .planning/")`

### Project-Specific Examples

**Using ripgrep (preferred when available):**

**Fallback (if rg/fd unavailable):**
Use Grep tool with similar patterns or Glob tool for file finding.

### INSTANT DECISION TREE

```
User asks to "list/show/summarize/explore files"?
  → PREFER: Bash("fd . -t f")  (fastest, shows all files)
  → OR: Bash("rg --files")  (respects .gitignore)
  → FALLBACK: Glob tool if fd/rg unavailable

User asks to "search/grep/find text content"?
  → PREFER: Bash("rg 'pattern'")  (fastest, project standard)
  → FALLBACK: Grep tool if rg unavailable or fails
  → AVOID: bash grep command

User asks to "find file/directory by name"?
  → PREFER: Bash("fd 'name'")  (faster than find)
  → FALLBACK: Glob tool if fd unavailable
  → AVOID: bash find command

User asks for "directory structure/tree"?
  → PREFER: Bash("fd . -t d") for dirs + Bash("fd . -t f") for files
  → NEVER: tree (not installed!)

Need just current directory?
  → USE: Bash("ls -la")  (OK for single dir)

Unsure if tool is available?
  → CHECK: Bash("which rg") or Bash("which fd")
  → Use tool if returns path, use fallback if empty
```


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
