#!/bin/bash
# Shared helper: injects real git metadata into BuildInfo.swift before building.
# Source this script (don't execute it) — it sets a trap to restore the placeholder on exit.
#
# Usage: source "$(dirname "$0")/inject-build-info.sh"

BUILD_INFO_FILE="Sources/LookMaNoHands/Services/BuildInfo.swift"
COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "development")
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Backup the placeholder BuildInfo.swift
cp "$BUILD_INFO_FILE" "$BUILD_INFO_FILE.backup"

# Set up trap to restore BuildInfo.swift on any exit (success or failure)
cleanup_build_info() {
    if [ -f "$BUILD_INFO_FILE.backup" ]; then
        echo "🔄 Restoring BuildInfo.swift placeholder..."
        mv "$BUILD_INFO_FILE.backup" "$BUILD_INFO_FILE"
    fi
}
trap cleanup_build_info EXIT

# Inject real build information
cat > "$BUILD_INFO_FILE" <<EOF
import Foundation

/// Build information injected by deploy.sh at build time.
/// This file is checked in with placeholder values for development builds.
struct BuildInfo {
    static let commitSHA = "$COMMIT_SHA"
    static let commitShortSHA = "$COMMIT_SHORT"
    static let buildDate = "$BUILD_DATE"
    static let branch = "$BRANCH"
}
EOF

echo "📝 Injected build info: commit $COMMIT_SHORT on $BRANCH"
