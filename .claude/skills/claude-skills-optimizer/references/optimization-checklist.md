# Optimization Checklist

Use this checklist to evaluate and improve Claude Code project configurations.

## Pre-Optimization Assessment

Before making changes, gather this information:

- [ ] Current CLAUDE.md file size (bytes and estimated tokens)
- [ ] Number of agent definitions in .claude/agents/
- [ ] Number of skills in .claude/skills/
- [ ] Total reference files across all locations
- [ ] Current pain points (if user reports them)

## Checklist Categories

### 1. Index Presence

**Question:** Does CLAUDE.md contain a compressed index of available documentation?

**Pass criteria:**
- Index exists near the top of CLAUDE.md
- Uses compact format (pipe-delimited or similar)
- Covers all major documentation directories
- Points to files rather than embedding content

**If missing:** Generate index using `scripts/generate-index.py`

### 2. Retrieval Instruction

**Question:** Does the config include the retrieval-led reasoning instruction?

**Pass criteria:**
- Contains: "Prefer retrieval-led reasoning over pre-training-led reasoning"
- Appears early in CLAUDE.md (within first 500 characters)
- Scoped appropriately ("for project-specific tasks" or similar)

**If missing:** Add instruction immediately after the index

### 3. Redundancy Check

**Question:** Is information duplicated between CLAUDE.md and reference files?

**Red flags:**
- Same content appears in CLAUDE.md and a reference file
- CLAUDE.md contains detailed instructions that belong in agent/skill files
- Multiple reference files cover the same topic

**If present:** Move detailed content to reference files, keep only index/pointers in CLAUDE.md

### 4. Trigger Clarity

**Question:** Are agent and skill descriptions clear enough to trigger reliably?

**Pass criteria for descriptions:**
- States WHAT the agent/skill does
- Lists specific TRIGGERS (file types, commands, task types)
- Avoids vague language ("helps with various tasks")

**If unclear:** Rewrite descriptions following this pattern:
```
[What it does]. Use when [specific triggers]. Handles [specific file types/tasks].
```

### 5. Token Budget

**Question:** Is CLAUDE.md appropriately sized?

| Size | Action |
|------|--------|
| <5KB | No action needed |
| 5-10KB | Review for unnecessary content |
| 10-20KB | Actively trim - move content to references |
| >20KB | Urgent - significant refactoring needed |

**Common bloat sources:**
- Inline examples that could be in reference files
- Repeated boilerplate across sections
- Verbose explanations of concepts Claude already knows

### 6. Directory Structure

**Question:** Is the .claude/ directory organized for easy retrieval?

**Recommended structure:**
```
.claude/
├── agents/           # Agent definitions (one per file)
├── docs/             # Project documentation
├── plans/            # Planning documents
├── skills/
│   └── skill-name/
│       ├── SKILL.md
│       ├── references/
│       ├── scripts/
│       └── assets/
└── CLAUDE.md         # Root config with index
```

**If disorganized:** Propose restructuring with clear rationale

## Recommendation Template

When presenting recommendations, use this format:

```
## Current State
- CLAUDE.md: [X] bytes ([Y] estimated tokens)
- Agents: [N] files
- Skills: [N] directories
- Reference files: [N] total

## Recommendations

### [Priority: High/Medium/Low] [Category]
**Current:** [what exists now]
**Proposed:** [what should change]
**Rationale:** [why this helps]
**Token impact:** [+/- estimate]

## Proposed Index

[Generated compressed index]

## Next Steps
1. [Action item]
2. [Action item]
```
