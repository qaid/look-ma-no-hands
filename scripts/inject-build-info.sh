#!/bin/bash
# Shared helper: injects real git metadata into BuildInfo.swift before building.
# Source this script (don't execute it) — it sets a trap to restore the placeholder on exit.
#
# Usage: source "$(dirname "$0")/inject-build-info.sh"

# Guard: abort if executed directly instead of sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed directly." >&2
    echo "Usage: source \"$(dirname "$0")/inject-build-info.sh\"" >&2
    exit 1
fi

# Resolve paths relative to the git repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo "ERROR: Not inside a git repository." >&2
    return 1
fi
BUILD_INFO_FILE="$REPO_ROOT/Sources/LookMaNoHands/Services/BuildInfo.swift"

COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "development")
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Backup the placeholder BuildInfo.swift outside Sources/ so SPM doesn't warn
BUILD_INFO_BACKUP="$REPO_ROOT/.build/BuildInfo.swift.backup"
mkdir -p "$(dirname "$BUILD_INFO_BACKUP")"
if ! cp "$BUILD_INFO_FILE" "$BUILD_INFO_BACKUP"; then
    echo "ERROR: Failed to backup BuildInfo.swift" >&2
    return 1
fi

# Set up trap to restore BuildInfo.swift on any exit (success or failure)
# Chain with any existing EXIT trap to avoid clobbering callers' cleanup logic
cleanup_build_info() {
    if [ -f "$BUILD_INFO_BACKUP" ]; then
        echo "🔄 Restoring BuildInfo.swift placeholder..."
        mv "$BUILD_INFO_BACKUP" "$BUILD_INFO_FILE"
    fi
}
_existing_exit_trap=$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//")
if [ -n "$_existing_exit_trap" ]; then
    eval "cleanup_build_info_chained() { cleanup_build_info; $_existing_exit_trap; }"
    trap cleanup_build_info_chained EXIT
else
    trap cleanup_build_info EXIT
fi
unset _existing_exit_trap

# Inject real build information
cat > "$BUILD_INFO_FILE" <<EOF
import Foundation

/// Build information injected at build time by inject-build-info.sh.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "$COMMIT_SHA"
    static let commitShortSHA = "$COMMIT_SHORT"
    static let buildDate = "$BUILD_DATE"
    static let branch = "$BRANCH"
}
EOF

echo "📝 Injected build info: commit $COMMIT_SHORT on $BRANCH"
