#!/bin/bash
# run.sh — Start the HTML preview catalog dev server
# Opens http://localhost:8420 in the default browser.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREVIEW_DIR="$REPO_ROOT/preview"
PORT=8420

if [[ ! -d "$PREVIEW_DIR" ]]; then
    echo "ERROR: preview/ directory not found at $PREVIEW_DIR"
    exit 1
fi

# Kill any existing server on this port
if lsof -ti tcp:"$PORT" &>/dev/null; then
    echo "Stopping existing server on port $PORT..."
    lsof -ti tcp:"$PORT" | grep -E '^[0-9]+$' | xargs kill 2>/dev/null || true
    sleep 0.3
    # Force-kill if still running
    lsof -ti tcp:"$PORT" | grep -E '^[0-9]+$' | xargs kill -9 2>/dev/null || true
fi

echo "Starting preview server on http://localhost:$PORT"
echo "Press Ctrl-C to stop."
echo ""

# Open browser after a short delay so the server is up first
(sleep 0.4 && open "http://localhost:$PORT") &

cd "$PREVIEW_DIR"
exec python3 -m http.server $PORT
