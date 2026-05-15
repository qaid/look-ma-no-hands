---
name: mental-model
description: Manage structured YAML expertise files as personal mental models. Use when starting tasks (read for context), completing work (capture learnings), or when your understanding of the system needs updating.
---

# Mental Model

You have personal expertise files -- structured YAML documents that represent your mental model of the system you work on. These are YOUR files. You own them. They are how you remember what you have learned across sessions.

## When to Read

- **At the start of every task** -- read your expertise file(s) before doing anything else
- **When you need to recall** prior observations, decisions, or patterns
- **When a teammate references something** you have tracked before

## When to Update

- **After completing meaningful work** -- capture what you learned
- **When you discover something new** about the system (architecture, patterns, gotchas)
- **When your understanding changes** -- update stale entries, do not just append
- **When you observe patterns in other agents' work** -- note what to watch for when reviewing or coordinating with them

Skip the update for trivial work: single-file fixes with no new learning, documentation typos, status queries. If you learned nothing new, write nothing.

## How to Structure

Write structured YAML. Let categories emerge from your work -- do not pre-define sections you have nothing to put in yet. Keep it scannable.

```yaml
# Good: structured, dated, actionable
architecture:
  api_layer:
    pattern: "REST with server-sent events for real-time push"
    key_files:
      - "src/scopematch/web/public.py -- public routes, ~600 lines"
    decisions:
      - "[2026-03-28] Chose SSE over WebSocket -- simpler for read-only push to lab owners"
    gotchas:
      - "[2026-04-01] Rate limiter middleware must be registered before auth middleware"

patterns:
  - "[2026-03-24] Backend agent handles scope-heavy requests better when given explicit file paths upfront"
  - "[2026-04-02] Frontend agent misses dark mode tokens when CSS file has no existing dark section to reference"

constraints:
  - "uv run python always -- never bare python"
  - "Germany: absolute blocker for cold email (UWG Section 7(2)(2))"

open_questions:
  - "Should we split auth module? Growing past 400 lines."

agent_observations:   # optional -- only for coordinating agents
  frontend_engineer:
    watch_for:
      - "dark mode tokens on new CSS properties"
      - "aria-label on icon-only buttons"
```

## What NOT to Store

- Do not copy-paste entire files -- reference by path
- Do not store conversation logs -- that is what the session log is for
- Do not store transient data (build output, test results) -- just conclusions
- Do not create sections you have nothing to put in yet -- let structure emerge
- Do not record something you are not confident is true -- mark as `uncertain:` if needed

## First Run

If your expertise file does not exist:

1. Create it at the path specified in your system prompt
2. Add a minimal starting structure matching your domain
3. Add 2-3 entries based on what you already know about the system

```yaml
domain: "backend -- Flask routes, SQLAlchemy models, pipeline scripts"
architecture: {}
constraints: []
open_questions: []
```

The file will grow naturally as you work. Do not pad it with placeholder sections.

## How to Update Safely

YAML is sensitive to formatting. One bad indent breaks the whole file.

1. **Read the file first** -- understand current structure before writing
2. **Append to lists** at the existing indent level with `- ` prefix
3. **Update existing entries in place** -- find the entry and change it, do not duplicate
4. **Preserve indentation** of sections you are not editing
5. **Prefix dated entries** with `[YYYY-MM-DD]` so the timeline is readable

If you are uncertain about YAML syntax for a complex update, rewrite the whole file from scratch: read the current contents, add your new entries, write the complete new version. This is safer than a partial edit on a complex structure.

After writing, read the file back to verify it looks correct.

## Handling Stale and Conflicting Entries

- **Stale entry** (no longer true): update it in place, note the change date
- **Superseded decision**: update the entry, add `# superseded [date]: <new approach>`
- **Conflicting observations**: investigate before writing -- do not record contradictions without resolving them
- **Wrong entry**: correct it directly, do not append a correction alongside the wrong entry

```yaml
# Good: updated in place with history preserved
decisions:
  - "[2026-03-24] Chose WebSocket for real-time # superseded [2026-04-01]: migrated to SSE, simpler for read-only push"
```

## Migrating from Markdown

If your expertise file is currently in markdown format (section headers + bullet points), convert it on your first meaningful update:

1. Read the full markdown file
2. Map section headers to YAML keys (use `snake_case`)
3. Map each bullet entry to a list item, preserving the `[date, slug]` prefix as `[date]`
4. Write the YAML version to the same path
5. The content stays the same -- only the structure changes

```yaml
# Markdown entry:  - [2026-03-28, outreach-legal] France permits B2B prospection email...
# Becomes:
gdpr_and_email_marketing:
  - "[2026-03-28] France permits B2B prospection email if it relates to recipient's professional role (Art. L34-5 CPCE)"
```

## Line Limit Enforcement

Your system prompt specifies a `max-lines` limit for your expertise file. After every write:

1. Check the line count: `wc -l <file>`
2. If within limit: done
3. If over limit, consolidate:
   - Remove entries that are no longer relevant (old gotchas that became non-issues, decisions that have been fully superseded and are no longer informative)
   - Merge related entries that say similar things into one
   - Keep all active constraints, open questions, and recent patterns
   - Do NOT delete entries that represent current architectural decisions or unresolved risks

The goal is a file that is always current and scannable -- not a complete archive. The session log and git history are the archive.
