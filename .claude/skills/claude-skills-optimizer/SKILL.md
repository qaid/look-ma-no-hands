---
name: claude-skills-optimizer
description: Analyzes and optimizes Claude Code project configurations (CLAUDE.md, agents, skills directories) based on Vercel's agent eval research. Use when you want to improve agent performance in a repo by applying passive-context patterns, generating compressed documentation indexes, or auditing existing skill/agent setups for efficiency. Triggers on requests to "optimize my Claude setup", "improve agent performance", "audit my skills directory", or "apply AGENTS.md patterns".
---

# Claude Skills Optimizer

Optimizes Claude Code project configurations based on research showing passive context outperforms on-demand skill retrieval.

## Core Finding

Vercel's agent evals found that an 8KB compressed docs index embedded in AGENTS.md achieved 100% pass rate, while skills maxed at 79%. Key insight: removing the decision point ("should I look this up?") dramatically improves agent performance.

## Critical Instruction for Optimized Configs

Always include this in optimized CLAUDE.md files:

```
IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning for project-specific tasks.
```

## Optimization Workflow

### Phase 1: Analysis

1. **Map the structure.** Run the index generator script:
   ```bash
   python scripts/generate-index.py /path/to/project
   ```

2. **Review the output.** The script produces:
   - A structure map of all .claude/ contents
   - Token estimates for each file
   - A compressed index in Vercel's pipe-delimited format
   - Specific recommendations

3. **Present findings to user.** Never auto-modify. Always show:
   - Current CLAUDE.md token count
   - Proposed changes with rationale
   - Expected token delta

### Phase 2: Recommendations

Evaluate against these criteria (see `references/optimization-checklist.md` for details):

| Check | Question |
|-------|----------|
| Index presence | Does CLAUDE.md contain a compressed index of available docs? |
| Retrieval instruction | Does it include the "prefer retrieval-led reasoning" instruction? |
| Redundancy | Is information duplicated between CLAUDE.md and reference files? |
| Trigger clarity | Are agent/skill descriptions clear enough to trigger reliably? |
| Token budget | Is CLAUDE.md under 10KB? Under 5KB is better. |

### Phase 3: Generate Optimized Config

Use the compressed index format:

```
[Project Docs Index]|root:./.claude
|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
|agents:{figma-mcper.md,rn-architect.md,rn-ui-designer.md,...}
|skills/skill-name/references:{components.md,patterns.md,tokens.md,...}
```

This format:
- Uses pipe delimiters to minimize tokens
- Groups files by directory
- Points to retrievable files rather than embedding content
- Keeps the full index under 1KB for most projects

## When NOT to Optimize

- Projects with only a simple CLAUDE.md (no agents/skills directory)
- Projects where the current setup is already achieving good results
- When the user just wants to understand their setup, not change it

## Reference Files

- `references/vercel-findings.md` - Full research summary with data
- `references/optimization-checklist.md` - Detailed evaluation criteria
- `scripts/generate-index.py` - Automated analysis and index generation
