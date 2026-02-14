#!/usr/bin/env bash
#
# Stop hook guard for auto-reflection
# Triggered when user stops a session. Decides whether to block and request brief reflection.
#
# Input: JSON on stdin with fields stop_hook_active, transcript_path, cwd
# Output: JSON decision {"decision": "allow"} or {"decision": "block", "reason": "..."}
#

set -euo pipefail

# Read stdin JSON
INPUT=$(cat)

# Guard 1: Check if stop hook is already active (prevent infinite loops)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Guard 2: Check transcript exists and is substantial
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

LINE_COUNT=$(wc -l < "$TRANSCRIPT_PATH" | tr -d ' ')
if [[ "$LINE_COUNT" -lt 50 ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Guard 3: Check that learnings.md exists in project
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
LEARNINGS_FILE="$CWD/.claude/learnings.md"
if [[ ! -f "$LEARNINGS_FILE" ]]; then
  echo '{"decision": "allow"}'
  exit 0
fi

# All guards passed - block and request brief reflection
cat <<'EOF'
{
  "decision": "block",
  "reason": "Before stopping, briefly analyze this session for learnings using the /reflect skill. Keep it concise - just capture any corrections, approved patterns, or notable observations, then stop. If nothing noteworthy, say so in one sentence and exit."
}
EOF
