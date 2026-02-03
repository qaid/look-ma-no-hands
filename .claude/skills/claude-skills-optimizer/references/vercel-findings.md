# Vercel Agent Eval Findings

Source: Vercel blog, January 2026

## The Experiment

Vercel tested two approaches for teaching Claude agents framework-specific knowledge (Next.js 16 APIs not in training data):

1. **Skills** - On-demand retrieval where agents invoke documentation when needed
2. **AGENTS.md** - Passive context with compressed docs index always available

## Results Summary

| Configuration | Pass Rate | vs Baseline |
|--------------|-----------|-------------|
| Baseline (no docs) | 53% | - |
| Skill (default) | 53% | +0pp |
| Skill (explicit instructions) | 79% | +26pp |
| AGENTS.md docs index | 100% | +47pp |

## Key Findings

### Finding 1: Skills weren't triggered reliably

In 56% of eval cases, the skill was never invoked even when available. The agent had access but chose not to use it.

### Finding 2: Explicit trigger instructions helped but were fragile

Adding "Before writing code, first explore the project structure, then invoke the nextjs-doc skill" improved trigger rate to 95%+ and pass rate to 79%.

However, wording variations produced dramatically different results:
- "You MUST invoke the skill" → Agent reads docs first, anchors on doc patterns, misses project context
- "Explore project first, then invoke skill" → Better results

### Finding 3: Passive context eliminated the decision point

With AGENTS.md, there's no moment where the agent must decide "should I look this up?" The information is already present.

Benefits:
- No decision point required
- Consistent availability (in context every turn vs async loading)
- No ordering issues (read docs first vs explore project first)

### Finding 4: Compression maintained effectiveness

Initial docs injection: ~40KB
Compressed version: ~8KB (80% reduction)
Result: Same 100% pass rate

Compression format used:
```
[Next.js Docs Index]|root: ./.next-docs
|IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning
|01-app/01-getting-started:{01-installation.mdx,02-project-structure.mdx,...}
```

## The Critical Instruction

This single line made retrieval-led reasoning the default:

```
IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning for any Next.js tasks.
```

## Implications for Claude Code Projects

1. **Embed a compressed index in CLAUDE.md** rather than relying on agents/skills to be discovered and invoked
2. **Keep CLAUDE.md lean** - index format pointing to files, not full content
3. **Include the retrieval instruction** to override training-data defaults
4. **Structure docs for retrieval** - organized directories agents can read as needed
5. **Skills still useful for vertical workflows** - explicit user-triggered tasks like "upgrade my Next.js version" work well as skills

## Token Budget Guidelines

| Size | Assessment |
|------|------------|
| <5KB | Excellent - minimal context overhead |
| 5-10KB | Good - reasonable for complex projects |
| 10-20KB | Caution - evaluate if all content is necessary |
| >20KB | Problem - likely contains content that should be in reference files |
