#!/bin/bash
# setup.sh — Session initialisation for Look Ma No Hands
# Run this at the start of a Conductor session to verify the workspace is ready.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Look Ma No Hands — Session Setup ==="
echo "Repo: $REPO_ROOT"
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo ""

# ── 1. Swift toolchain ────────────────────────────────────────────────────────
echo "► Checking Swift toolchain..."
if ! command -v swift &>/dev/null; then
    echo "  ERROR: swift not found. Install Xcode Command Line Tools."
    exit 1
fi
SWIFT_VER=$(swift --version 2>&1 | head -1)
echo "  OK: $SWIFT_VER"

# ── 2. SPM package graph ──────────────────────────────────────────────────────
echo ""
echo "► Resolving SPM dependencies..."
# swift package resolve exits 0 if already up to date, so this is safe to run
swift package resolve 2>&1 | tail -3
echo "  OK: dependencies resolved"

# ── 3. Working tree status ────────────────────────────────────────────────────
echo ""
echo "► Git status..."
UNCOMMITTED=$(git status --porcelain | wc -l | tr -d ' ')
if [[ "$UNCOMMITTED" -eq 0 ]]; then
    echo "  Clean working tree"
else
    echo "  $UNCOMMITTED uncommitted change(s):"
    git status --short | head -10
fi

# ── 4. Preview catalog ────────────────────────────────────────────────────────
echo ""
echo "► Preview catalog..."
PREVIEW_FILES=$(find preview/screens -name '*.html' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$PREVIEW_FILES" -eq 0 ]]; then
    echo "  WARNING: preview/screens/ is empty — run the HTML catalog generator"
else
    echo "  $PREVIEW_FILES screen(s) in preview/screens/"
    echo "  Serve: bash scripts/run.sh"
fi

# ── 5. Ollama (optional) ──────────────────────────────────────────────────────
echo ""
echo "► Ollama (optional)..."
if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    MODELS=$(curl -sf http://localhost:11434/api/tags | python3 -c "
import sys, json
data = json.load(sys.stdin)
names = [m['name'] for m in data.get('models', [])]
print(', '.join(names) if names else 'none')
" 2>/dev/null || echo "running (model list unavailable)")
    echo "  Connected — models: $MODELS"
else
    echo "  Not running (optional — needed for meeting note analysis)"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "=== Ready ==="
echo "  Build:   swift build -c release"
echo "  Test:    swift test"
echo "  Deploy:  bash scripts/deploy.sh"
echo "  Preview: bash scripts/run.sh"
echo ""
