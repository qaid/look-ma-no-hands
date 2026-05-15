---
name: lmnh-implement-ticket
description: Single-ticket implementation chain for Look Ma No Hands GitHub issues. Fetches the issue, assesses scope, routes to fast-path or standard-path, dispatches to engineering agents, and drives the review-fix-merge loop.
---

# /lmnh-implement-ticket

Single-ticket implementation chain. Routes through fast-path or standard-path based on scope assessment.

## Input

`$ARGUMENTS` -- GitHub issue number, e.g. `42`

## Process

**1. Fetch the issue**:
```bash
gh issue view $ARGUMENTS --repo qaid/look-ma-no-hands --json number,title,body,labels
```

**2. Check for an existing PR**:
```bash
gh pr list --repo qaid/look-ma-no-hands --state open --json number,title,headRefName
```
If a PR already exists for this issue, dispatch to engineering-manager with `type: code-review`.

**3. Assess fast-path vs standard-path**:

Fast-path when ALL are true:
- Change touches <= 2 files
- No new services, dependencies, or architectural patterns
- No new system permissions required (mic, AX, screen recording)
- Easily reversible

**4a. Fast-path**: Dispatch directly to engineering-manager with full issue context. Skip the planner.

**4b. Standard-path**: Dispatch to planner with issue number and full body. Planner returns DISPATCH block. Orchestrator reads DISPATCH and dispatches to engineering-manager.

**5. Engineering-manager runs**: Worker agents implement, code-reviewer reviews, fix loop runs until clean, PR opened.

**6. OUTCOME**: Engineering-manager returns OUTCOME block. Read the `verdict:` field and branch:

- **`verdict: SHIP`** -- surface to Q.: "PR #N is ready. Proceed to merge."

- **`verdict: NEEDS_WORK`** -- engineering-manager handles the re-dispatch loop internally. Orchestrator waits for a subsequent OUTCOME with `verdict: SHIP`. Surface to Q. only after 3+ iterations.

- **`verdict: MAJOR_RETHINK`** -- surface the verbatim `## Review Verdict` block to Q. with:
  > "Reviewer flagged architectural concerns on PR #N. Your call: proceed / revise / abort."
  Await Q.'s explicit response.

For `status: blocked` or `status: needs-q`: surface the blocker or decision with options.
