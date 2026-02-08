# Claude Code Status Line Setup Guide

This guide explains how to set up a custom status line for Claude Code that displays accurate token usage information, matching the `/context` command output.

## Overview

The status line displays:
- Model name (colored in purple)
- Visual progress bar showing context window usage
- Token count (used/total) with smart abbreviations (K/M)
- Percentage used, color-coded by usage level

Example: `Sonnet 4.5 │ ████████░░░░░░░░░░░░ 28.7K/200K (14%)`

## Setup Instructions

### Step 1: Create the Status Line Script

Create a file at `~/.claude/statusline.sh`:

```bash
#!/bin/bash

# Read JSON input
input=$(cat)

# Extract values using jq
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // "Unknown"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

# Get token counts from current usage
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')

# Calculate total used tokens (IMPORTANT: This matches /context command)
used_tokens=$((cache_read + current_input))

# Fallback: Calculate from percentage if direct counts unavailable
if [ -n "$used_pct" ] && [ -n "$context_size" ] && [ "$used_tokens" -eq 0 ]; then
  used_tokens=$(echo "scale=0; $context_size * $used_pct / 100" | bc)
fi

# Use context window size as total
total_tokens="$context_size"

# Function to abbreviate numbers (1000 -> 1K, 1000000 -> 1M)
abbreviate() {
  local num=$1
  if [ "$num" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "scale=1; $num / 1000000" | bc)" | sed 's/\.0M/M/'
  elif [ "$num" -ge 1000 ]; then
    printf "%.1fK" "$(echo "scale=1; $num / 1000" | bc)" | sed 's/\.0K/K/'
  else
    echo "$num"
  fi
}

# Start building output
output=""

# Model name in purple
output+="$(printf '\033[0;35m%s\033[0m' "$model_name")"

# Add token visualization if available
if [ -n "$used_pct" ] && [ -n "$used_tokens" ] && [ -n "$total_tokens" ]; then
  # Determine color based on usage
  if (( $(echo "$used_pct < 50" | bc -l) )); then
    color='\033[0;32m'  # green
  elif (( $(echo "$used_pct < 80" | bc -l) )); then
    color='\033[0;33m'  # yellow
  else
    color='\033[0;31m'  # red
  fi

  # Create progress bar (20 chars)
  filled=$(printf "%.0f" "$(echo "$used_pct * 20 / 100" | bc -l)")
  empty=$((20 - filled))

  bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  # Format token counts
  used_abbr=$(abbreviate "$used_tokens")
  total_abbr=$(abbreviate "$total_tokens")

  # Add separator and token info
  output+=" $(printf '\033[0;90m│\033[0m') "
  output+="$(printf "${color}%s %s/%s (%.0f%%)\033[0m" "$bar" "$used_abbr" "$total_abbr" "$used_pct")"
fi

echo -e "$output"
```

Make it executable:
```bash
chmod +x ~/.claude/statusline.sh
```

### Step 2: Update Claude Code Settings

Add this to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

### Step 3: Restart Claude Code

Restart your Claude Code session to see the new status line.

## Understanding the Token Calculation

### Why This Formula is Correct

The script uses this calculation:
```bash
used_tokens = cache_read_input_tokens + input_tokens
```

This matches the `/context` command because:

1. **`cache_read_input_tokens`** - Tokens read from prompt cache
   - These are tokens being reused from cache
   - They still count toward your context window usage
   - They're just cheaper (90% discount) but still "in context"

2. **`input_tokens`** - New input tokens (non-cached)
   - Fresh tokens being processed in this turn
   - Not yet cached

3. **`cache_creation_input_tokens`** - NOT included
   - These are tokens being written TO the cache
   - They're a one-time cost for cache creation
   - They don't represent what's "in context" right now

### Example from Debug Data

```json
{
  "current_usage": {
    "input_tokens": 12,
    "cache_read_input_tokens": 28667,
    "cache_creation_input_tokens": 291
  }
}
```

**Correct calculation:**
```
used_tokens = 28667 + 12 = 28679 tokens
```

**Incorrect calculations (don't use these):**
```
❌ 28667 + 12 + 291 = 28970  (includes cache creation - too high)
❌ 12 only              (ignores cache reads - way too low)
❌ 28667 only           (ignores current input - slightly low)
```

## Debugging

### Check What Data is Available

Create a debug script at `~/.claude/statusline-debug.sh`:

```bash
#!/bin/bash

# Read JSON input from stdin and save it
input=$(cat)
echo "$input" > ~/.claude/statusline-debug.json

# Pretty print to another file
echo "$input" | jq '.' > ~/.claude/statusline-debug-pretty.json 2>&1

# Run the original script
echo "$input" | ~/.claude/statusline.sh
```

Update your settings to use the debug script:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-debug.sh"
  }
}
```

Then check these files:
- `~/.claude/statusline-debug.json` - Raw JSON from Claude Code
- `~/.claude/statusline-debug-pretty.json` - Pretty-printed JSON

### Verify Token Counts Match

1. Look at your status line output
2. Run `/context` command
3. Compare the "Used" token count - they should match

Example:
```
Status line: 28.7K/200K (14%)
/context:    28679 / 200000 tokens used (14%)
```

## JSON Structure Reference

The status line script receives this JSON structure:

```json
{
  "model": {
    "id": "global.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "display_name": "Sonnet 4.5"
  },
  "context_window": {
    "total_input_tokens": 7546,      // Cumulative across session
    "total_output_tokens": 1627,     // Cumulative across session
    "context_window_size": 200000,   // Total available
    "current_usage": {               // Current turn only
      "input_tokens": 12,                      // New tokens this turn
      "cache_read_input_tokens": 28667,        // Cached tokens in use
      "cache_creation_input_tokens": 291       // Tokens written to cache
    },
    "used_percentage": 14,           // Pre-calculated percentage
    "remaining_percentage": 86
  }
}
```

## Color Coding

The progress bar color changes based on usage:

- **Green** (< 50%) - Plenty of room
- **Yellow** (50-80%) - Getting full
- **Red** (> 80%) - Almost full

## Customization

### Change Colors

Modify these ANSI color codes in the script:

```bash
'\033[0;35m'  # Model name (purple)
'\033[0;90m'  # Separator (gray)
'\033[0;32m'  # Progress bar < 50% (green)
'\033[0;33m'  # Progress bar 50-80% (yellow)
'\033[0;31m'  # Progress bar > 80% (red)
```

### Change Progress Bar Length

Modify this line (default is 20 characters):
```bash
filled=$(printf "%.0f" "$(echo "$used_pct * 20 / 100" | bc -l)")
empty=$((20 - filled))
```

Change `20` to your desired width.

### Change Abbreviation Thresholds

Modify the `abbreviate()` function:
```bash
if [ "$num" -ge 1000000 ]; then  # Use M for millions
  printf "%.1fM" ...
elif [ "$num" -ge 1000 ]; then   # Use K for thousands
  printf "%.1fK" ...
```

## Requirements

- `jq` - JSON processor (install with `brew install jq` on macOS)
- `bc` - Calculator for floating point math (usually pre-installed)

## Troubleshooting

### Status line shows "Unknown"
- Check that jq is installed: `which jq`
- Verify the script has execute permissions: `ls -l ~/.claude/statusline.sh`

### Token counts don't match /context
- Enable debug mode (see Debugging section)
- Check `~/.claude/statusline-debug-pretty.json` for available fields
- Verify you're using `cache_read_input_tokens + input_tokens`

### No progress bar appears
- Check that all required fields are in the JSON
- Verify bc is installed: `which bc`
- Look for errors in the debug output

### Colors don't show
- Your terminal may not support ANSI colors
- Try a different terminal emulator
- Remove color codes if needed (search for `\033[` and remove those printf statements)

## Additional Notes

- The status line updates after each tool use or message
- Token counts are real-time and reflect current context usage
- Cache reads are included because they occupy context space, even though they're cheaper
- The formula matches Claude Code's internal `/context` calculation

## Related Commands

- `/context` - View detailed token usage breakdown
- `/status` - View session status and connection info

---

**Created:** 2026-02-04
**Last Updated:** 2026-02-04
**Compatible with:** Claude Code 2.x+
