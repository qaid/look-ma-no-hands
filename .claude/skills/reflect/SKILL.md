---
name: reflect
description: Analyze session transcript for corrections, approvals, and observations; append new learnings to project memory
triggers:
  - /reflect
  - analyze this session for learnings
  - what did we learn from this session
---

# Reflect: Session Learning Analyzer

You are analyzing the current session transcript to identify project-specific learnings that should persist across future sessions. Your goal is to capture actionable insights and append them to the project's living memory.

## Process

### 1. Read Existing Learnings

First, read `.claude/learnings.md` to understand what's already been captured. You'll use this to avoid duplicates.

### 2. Analyze Current Session

Scan the conversation history for three signal types:

**HIGH Confidence - Corrections:**
- User explicitly corrected your approach ("don't use X, use Y", "wrong, do it this way")
- User pointed out a mistake or misunderstanding
- User redirected you after you went down wrong path

**MEDIUM Confidence - Approved Patterns:**
- User explicitly praised an approach ("perfect", "exactly right", "this is the way")
- User confirmed something worked well and wants it repeated
- User highlighted a technique that solved their problem elegantly

**LOW Confidence - Observations:**
- Patterns that worked without explicit praise
- Friction points that slowed progress (but user didn't explicitly complain)
- Technical discoveries (available tools, performance characteristics, quirks)

### 3. Deduplicate

Compare your findings against existing entries in `.claude/learnings.md`. Skip anything already captured (even if phrased differently). Only proceed with genuinely new insights.

### 4. Append New Learnings

For each new learning, append to `.claude/learnings.md` using this exact format:

```markdown
## [Type]: [Brief Title]
**Date:** YYYY-MM-DD
**Confidence:** HIGH | MEDIUM | LOW
**Context:** [One sentence explaining when this applies]

[2-3 sentences: what to do/avoid, and why. Be specific and actionable.]

---
```

**Rules:**
- **Append only** - never edit or remove existing entries
- **Concise** - 3-5 lines of content maximum per entry
- **Project-specific** - only capture learnings unique to this codebase (not generic programming advice)
- **Actionable** - write in imperative mood ("Use X for Y", "Avoid Z when W")
- **Titled** - brief, scannable titles (e.g., "Prefer Edit over Write for existing files")

### 5. Summarize

After updating the file, tell the user:
- How many new learnings were captured (or "nothing new found")
- Brief summary of each new entry (title + confidence level)

If triggered automatically (via Stop hook), keep your summary to 2-3 sentences and don't ask follow-up questions.

---

## What NOT to Capture

- Generic programming knowledge ("functions should be small")
- Language features everyone should know ("Swift has closures")
- Temporary decisions that won't apply to future sessions
- User preferences already documented in CLAUDE.md
- Anything too vague to be actionable

---

## Example Entries

```markdown
## Correction: Never add Claude attribution to commits
**Date:** 2026-02-14
**Confidence:** HIGH
**Context:** When creating git commits in this project

User explicitly instructed to never add "Co-Authored-By: Claude" or "Generated with Claude Code" footers. Project policy documented in CLAUDE.md prefers clean, human-style commit messages.

---

## Approved Pattern: Use rg over Grep tool
**Date:** 2026-02-14
**Confidence:** MEDIUM
**Context:** When searching file contents in this codebase

Project convention prefers `Bash("rg 'pattern'")` over Grep tool for content search. Faster, respects .gitignore, and matches all CLAUDE.md examples. Only fall back to Grep tool if rg unavailable.

---

## Observation: SwiftWhisper async API uses MainActor
**Date:** 2026-02-14
**Confidence:** LOW
**Context:** When calling WhisperService transcription methods

SwiftWhisper's async transcription functions must be called from MainActor context or explicitly wrapped. Attempting to call from background tasks causes runtime warnings. Structure audio recording on background queue, but call whisper from main.

---
```

---

## Automation Note

When triggered by the Stop hook (automatic reflection at session end), you receive a special instruction in the hook's reason field. In this case:

- Be brief and businesslike (no chattiness)
- Don't ask clarifying questions
- Complete the reflection and exit
- If nothing noteworthy found, just say so in one sentence

---

## Implementation

Execute the 5 steps above, using Read/Edit/Write tools as needed. Remember: this file grows over time and loads automatically in every session via CLAUDE.md's index reference. You're building institutional memory.
