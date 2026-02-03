---
name: git-workflow
description: Quick reference for git operations, commit patterns, and workflow best practices
---

# Git Workflow Skill

## Overview
This skill provides quick reference for common git operations, commit message patterns specific to this repository, and safety checklists for git workflows. Use this when you need a refresher on git commands or want to verify you're following project conventions.

## Workflow Decision Tree

```
What do you need to do?

├─ Save work locally
│  ├─ Stage specific files → git add <files>
│  ├─ Stage all changes → git add . (check for sensitive files first!)
│  └─ Commit changes → git commit (analyze style from git log first)
│
├─ Share work with team
│  ├─ Push current branch → git push (REQUIRES user confirmation)
│  ├─ Create pull request → gh pr create (analyze full branch history first)
│  └─ Update from remote → git pull
│
├─ Manage branches
│  ├─ Create new branch → git checkout -b <name> or git switch -c <name>
│  ├─ Switch branches → git checkout <name> or git switch <name>
│  ├─ List branches → git branch -vv (shows tracking info)
│  └─ Delete branch → git branch -d <name> (confirm if unmerged)
│
├─ Review changes
│  ├─ See current status → git status
│  ├─ View uncommitted changes → git diff
│  ├─ View commit history → git log --oneline --graph
│  ├─ View file history → git log -- <file>
│  └─ Compare branches → git diff <branch1>...<branch2>
│
├─ Fix mistakes
│  ├─ Undo last commit (keep changes) → git reset --soft HEAD~1
│  ├─ Amend last commit → git commit --amend
│  ├─ Discard local changes → git restore <file> (CONFIRM first)
│  └─ Hard reset → git reset --hard (CONFIRM first - destructive!)
│
└─ Temporary storage
   ├─ Save work in progress → git stash push -m "description"
   ├─ List stashes → git stash list
   ├─ Apply latest stash → git stash pop
   └─ Apply specific stash → git stash apply stash@{N}
```

## Core Guidelines

### Project-Specific Requirements

**CRITICAL RULES:**
- ❌ **NEVER** include `Co-Authored-By: Claude Sonnet` footer in commits
- ❌ **NEVER** include "🤖 Generated with [Claude Code]" branding
- ⚠️ **ALWAYS** confirm with user before pushing to remote (`git push`)
- ✅ Commits can be made freely locally
- ✅ Pushing requires explicit user approval

### Commit Message Style

Based on analysis of this repository's commit history:

**Format**: `<Action verb> <concise description>`

**Action Verbs**:
- `Add` - New features, files, or functionality
- `Fix` - Bug fixes or corrections
- `Improve` - Enhancements to existing features
- `Redesign` - Significant UI/UX changes
- `Optimize` - Performance improvements
- `Security` - Security-related changes
- `Refactor` - Code restructuring without behavior change
- `Update` - Dependencies or configuration updates

**Examples from this repo**:
```
Add animated waveform visualization to recording indicator
Fix slow dictation transcription with enhanced logging and safety timeout
Improve waveform visualizer: fix amplitude scaling and light mode support
Redesign Meeting Transcription window and fix dictation indicator tracking
Optimize dictation latency for faster text insertion
Security: Redact transcription content from crash reports
```

**Style Rules**:
- Single line (no body unless absolutely necessary)
- Focus on **what changed and why**, not implementation details
- Use colon to separate component from details (optional)
- **NO** emojis, markdown, or special formatting
- **NO** attribution footers or branding

### Safety Checklist

**Before Staging Files**:
- [ ] Check for sensitive files (.env, credentials.json, *.key, *.pem)
- [ ] Review `git diff` to understand what's being committed
- [ ] Verify no debug code, console.logs, or TODO comments
- [ ] Ensure no large binary files (use .gitignore if needed)

**Before Committing**:
- [ ] Run `git status` to see what will be committed
- [ ] Review `git log --oneline -5` to match commit message style
- [ ] Write clear, descriptive commit message
- [ ] NO Co-Authored-By footer
- [ ] NO Claude Code branding

**Before Pushing**:
- [ ] Verify correct branch (`git branch --show-current`)
- [ ] Check remote tracking (`git branch -vv`)
- [ ] Run `git log origin/<branch>..HEAD` to see outgoing commits
- [ ] Get user confirmation (REQUIRED for this project)

**Before Destructive Operations**:
- [ ] Understand what will be lost
- [ ] Consider alternatives (stash instead of hard reset)
- [ ] Get user confirmation
- [ ] Never force push to main/master without explicit approval

## Quick Reference

### Common Commands

**Status & Information**:
```bash
git status                           # Show working tree status
git status -sb                       # Short status with branch info
git diff                             # Show unstaged changes
git diff --staged                    # Show staged changes
git log --oneline --graph -10        # Pretty commit history
git log --oneline --all --graph      # All branches history
git branch -vv                       # List branches with tracking info
```

**Staging & Committing**:
```bash
git add <file>                       # Stage specific file
git add <dir>                        # Stage directory
git add .                            # Stage all changes (check sensitive files!)
git restore --staged <file>          # Unstage file
git commit -m "message"              # Commit with message
git commit --amend                   # Modify last commit
```

**Branching**:
```bash
git switch -c <branch>               # Create and switch to new branch
git switch <branch>                  # Switch to existing branch
git checkout -b <branch>             # Create and switch (older syntax)
git branch -d <branch>               # Delete merged branch (safe)
git branch -D <branch>               # Force delete branch (confirm first!)
git branch -m <old> <new>            # Rename branch
```

**Remote Operations**:
```bash
git fetch                            # Download remote changes
git pull                             # Fetch and merge
git push                             # Push to remote (REQUIRES confirmation)
git push -u origin <branch>          # Push and set upstream
git remote -v                        # Show remote URLs
```

**Stashing**:
```bash
git stash push -m "description"      # Save work in progress
git stash list                       # List all stashes
git stash pop                        # Apply and remove latest stash
git stash apply                      # Apply latest stash (keep in list)
git stash drop                       # Delete latest stash
git stash clear                      # Delete all stashes
```

**Undo Operations**:
```bash
git restore <file>                   # Discard local changes (CONFIRM!)
git reset --soft HEAD~1              # Undo last commit, keep changes
git reset --mixed HEAD~1             # Undo last commit and staging
git reset --hard HEAD~1              # Undo last commit and changes (CONFIRM!)
git revert <commit>                  # Create new commit that undoes changes
```

## PR Creation Checklist

When creating a pull request:

1. **Analyze full branch context**:
   ```bash
   git log main..HEAD                # All commits in this branch
   git diff main...HEAD              # All changes since branching
   git status                        # Current state
   ```

2. **Draft PR components**:
   - **Title**: < 70 characters, descriptive
   - **Summary**: 2-3 bullet points of what changed
   - **Test Plan**: How to verify the changes work

3. **Push and create**:
   ```bash
   git push -u origin <branch>       # Get user confirmation first!
   gh pr create --title "..." --body "..."
   ```

4. **PR Body Template**:
   ```markdown
   ## Summary
   - First major change
   - Second major change
   - Third major change

   ## Test Plan
   - [ ] Step 1 to test
   - [ ] Step 2 to test
   - [ ] Step 3 to test
   ```

## Git Troubleshooting Guide

### "I accidentally committed to the wrong branch"
```bash
# 1. Note the commit hash
git log --oneline -1

# 2. Undo the commit (keep changes)
git reset --soft HEAD~1

# 3. Switch to correct branch
git switch <correct-branch>

# 4. Commit on correct branch
git add .
git commit -m "message"
```

### "I need to undo my last commit"
```bash
# Keep changes, undo commit
git reset --soft HEAD~1

# Undo commit and unstage, keep changes
git reset --mixed HEAD~1

# Completely undo (DESTRUCTIVE - confirm first!)
git reset --hard HEAD~1
```

### "I want to sync with remote main"
```bash
# From your feature branch
git fetch origin
git rebase origin/main
# Or if you prefer merge
git merge origin/main
```

### "My branch is ahead of remote and I want to force push"
```bash
# DANGEROUS - get user confirmation first!
# NEVER do this on main/master
git push --force-with-lease
```

### "I have uncommitted changes but need to switch branches"
```bash
# Option 1: Stash changes
git stash push -m "work in progress"
git switch <other-branch>
# Later: git stash pop

# Option 2: Commit changes
git add .
git commit -m "WIP: work in progress"
git switch <other-branch>
```

### "I accidentally staged sensitive files"
```bash
# Unstage specific file
git restore --staged .env

# Unstage all files
git restore --staged .

# Add to .gitignore to prevent future accidents
echo ".env" >> .gitignore
git add .gitignore
git commit -m "Add .env to .gitignore"
```

## Safety Notes

**Destructive Commands** (always confirm with user):
- `git reset --hard` - Permanently deletes uncommitted changes
- `git push --force` - Overwrites remote history
- `git branch -D` - Deletes unmerged branch
- `git clean -fd` - Deletes untracked files
- `git stash drop` - Permanently removes stashed changes

**Never Use Without Explicit User Request**:
- `--no-verify` - Skips pre-commit hooks
- `--no-gpg-sign` - Skips commit signing
- `--force` on main/master - Can break production

**Sensitive Files to Watch For**:
- `.env`, `.env.local`, `.env.*`
- `credentials.json`, `secrets.*`
- `*.key`, `*.pem`, `*.crt`
- `config/secrets.yml`
- `*.sqlite`, `*.db` (if contains sensitive data)

## Philosophy

Git is powerful but unforgiving. This skill emphasizes:
- **Safety first**: Confirm before destructive operations
- **Project compliance**: Follow repository-specific rules
- **Clear communication**: Write commit messages for humans
- **Reversibility**: Prefer soft resets and reverts over hard resets
- **Context awareness**: Understand what you're committing and why
