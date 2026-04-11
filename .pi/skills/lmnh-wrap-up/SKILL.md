---
name: lmnh-wrap-up
description: End-of-session summary for Look Ma No Hands. Reviews the conversation, writes session log, updates handoff file, and commits wrap-up files. Use at the end of every session.
---

# /lmnh-wrap-up

End-of-session summary. Reviews the conversation and persists state.

> **Timing note:** Run wrap-up BEFORE the final `gh pr merge` of the session wherever possible so wrap-up files land in the same merge.

## GUARDRAILS

**Step 6 (commit/PR/merge) is MANDATORY and MUST be executed before wrap-up is considered complete.**

## Process

**1. Review the conversation**

Identify what was discussed, decided, and done. Classify the session type:

- `code` -- implementation, bug fixes, PRs
- `design` -- SwiftUI/macOS design work
- `strategy` -- roadmap, architecture decisions
- `admin` -- issue triage, documentation, tooling
- `mixed` -- two or more of the above

---

**2. Verify live state -- do this before writing anything**

```bash
# Open PRs
gh pr list --repo qaid/look-ma-no-hands --state open --json number,title

# Issues touched or created this session
gh issue list --repo qaid/look-ma-no-hands --state open --json number,title,state
```

Only carry forward items confirmed open/incomplete.

---

**3. Write session log**

Create `memory/session-log/YYYY-MM-DD-<topic-slug>.md`:

```markdown
---
date: YYYY-MM-DD
topic: <topic-slug>
session-type: <code|design|strategy|admin|mixed>
---

## What Was Discussed
[2-4 sentences]

## Actions Taken
[Bulleted list -- what was done, with PR/issue numbers]

## Decisions Made
- Decision: [what was decided] -- Rationale: [why]

## Open Items / Next Steps
- [ ] [Specific incomplete task with PR/issue number]
```

**Then immediately update `memory/MEMORY.md`**: append to the session logs index:
```
- [session-log/YYYY-MM-DD-topic.md](session-log/YYYY-MM-DD-topic.md) -- brief one-line description
```

---

**4. Write session handoff**

Overwrite `memory/last-session.md`:

```markdown
# Session Handoff
Date: YYYY-MM-DD
Session: <topic-slug>
Session type: <code|design|strategy|admin|mixed>

## What We Were Working On
[Active task with specific details, file paths, branch names, issue/PR numbers]

## Decisions Made This Session
- [Decision -- Rationale: why]

## Unfinished Work
**Do NOT list GitHub issues here -- they are read live from gh CLI.**

Only record things NOT tracked in GitHub:
- [ ] Local branches not yet pushed (branch name + intent)
- [ ] In-progress local tasks (checkpoint, script state)

If all carry-forwards are in GitHub, write: "All carry-forwards tracked as GitHub issues."

## Next Steps (Prioritised)
1. [Most important next action]
2. [Second priority]

## Session State
- Code branch: [branch or "main"]
- Worktrees active: [list or "none"]
- Issues touched: [#NNN list]
- PRs open: [verified via gh pr list]

## Quick Context
[2-3 sentences: what was accomplished, what momentum exists, what the next session should pick up on.]
```

---

**5. Update expertise file**

Append any new pattern or lesson from this session to the relevant `expertise/*.md` file. One to three bullet points maximum. If nothing new was learned, skip.

---

**6. MANDATORY -- Commit wrap-up files via PR**

```bash
REPO="/Users/qaid/Code/look-ma-no-hands"
cd "$REPO"
DATE=$(date +%Y%m%d)
TOPIC=<topic-slug>
git checkout main && git pull origin main
git checkout -b chore/session-wrap-${DATE}
git add memory/last-session.md memory/MEMORY.md memory/session-log/ expertise/
git commit -m "chore: session wrap-up $(date +%Y-%m-%d) (${TOPIC})"
git push -u origin chore/session-wrap-${DATE}
gh pr create --repo qaid/look-ma-no-hands \
  --title "chore: session wrap-up $(date +%Y-%m-%d) (${TOPIC})" \
  --body "Automated session wrap-up: log, handoff, expertise update." \
  --base main
gh pr merge --repo qaid/look-ma-no-hands --squash --delete-branch
```

---

**7. Report**

```
## Wrap-up complete

Session type: [type]
Handoff written: memory/last-session.md
Session log: memory/session-log/[filename]
MEMORY.md: updated
Wrap-up PR: [PR URL or number]

Suggested first actions next session:
1. [action]
2. [action]
```
