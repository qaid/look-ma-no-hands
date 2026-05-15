---
name: lmnh-heartbeat
description: Project status briefing for Look Ma No Hands. Reads git activity, open PRs and issues, build health, and last-session handoff to produce a unified briefing. Only invoke when the user explicitly requests a status briefing.
---

# /lmnh-heartbeat

> **Invoke only on explicit user request.** Do not run this automatically at session start.

Project status briefing. Executes in two phases: data collection (Scout) and synthesis (Orchestrator).

## Execution Model

### Phase 1: Data Collection (Scout)

Spawn a Scout agent with this task:

```
Collect LMNH project status data. Return results in a ---HEARTBEAT-DATA--- block with these sections:

## last-session
Read memory/last-session.md -- full contents (or "empty" if file is blank).

## recent-commits
git -C /Users/qaid/Code/look-ma-no-hands log --oneline -15

## open-prs
gh pr list --repo qaid/look-ma-no-hands --state open --json number,title,headRefName,updatedAt

## open-issues
gh issue list --repo qaid/look-ma-no-hands --state open --json number,title,labels,updatedAt --limit 30

## build-health
swift build -c release 2>&1 | tail -15

## test-health
swift test 2>&1 | tail -20

## worktrees
git worktree list

---HEARTBEAT-DATA---
[structured output here]
---END HEARTBEAT-DATA---
```

Use the returned block as-is for Phase 2. Do NOT re-fetch any sources.

### Phase 2: Synthesis (Orchestrator)

Parse the `---HEARTBEAT-DATA---` block returned by Scout and produce the unified briefing below.

## Briefing Format

### Resuming From
[Only if last-session has content]
- Session date and topic
- Unfinished work items as suggested first actions
- Quick context narrative

### Recent Activity
- Last 15 commits in plain language (group related commits)

### Build Health
- `swift build -c release` status: clean / warnings / errors
- `swift test` status: passing / failing / count

### Open Issues
- Grouped by theme/label
- Total open count
- `updatedAt` date for each so staleness is visible

### Open PRs
- Numbered list with branch name and age

### Active Worktrees
- In-flight worktrees

### Suggested Actions
- If build or tests are failing: prioritise that first
- Most important next actions based on all the above
- Flag drift between open issues and recent git activity
