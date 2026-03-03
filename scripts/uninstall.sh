#!/bin/bash
set -e

# Uninstall Look Ma No Hands
# Removes the app, preferences, privacy permissions, and support data.
# Usage: ./scripts/uninstall.sh [-y]

BUNDLE_ID="com.lookmanohands.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Confirmation prompt (skip with -y flag)
if [[ "$1" != "-y" ]]; then
    echo "This will completely remove Look Ma No Hands, including all preferences and data."
    read -p "Are you sure? (y/N) " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""
fi

echo "Uninstalling Look Ma No Hands..."
echo ""

# Graceful shutdown
echo "Stopping app..."
APP_PID=$(pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null || true)
if [ -n "$APP_PID" ]; then
    osascript -e 'tell application "Look Ma No Hands" to quit' 2>/dev/null || true
    sleep 2
    # Re-check that the PID is still our app before force-killing
    if kill -0 "$APP_PID" 2>/dev/null && pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null | grep -q "^${APP_PID}$"; then
        kill -9 "$APP_PID" 2>/dev/null || true
        sleep 1
    fi
    echo "   Stopped running instance"
else
    echo "   App not running"
fi

# Remove app bundles and unregister from Launch Services
echo "Removing app bundles..."
for APP in ~/Applications/"Look Ma No Hands.app" ~/Applications/LookMaNoHands.app; do
    if [ -d "$APP" ]; then
        "$LSREGISTER" -u "$APP" 2>/dev/null || true
        rm -rf "$APP"
        echo "   Removed $APP"
    fi
done

# Reset TCC privacy permissions (removes ghost entries from System Settings)
# Note: tccutil reset may silently fail on macOS 15+ for Accessibility.
echo "Clearing privacy permissions..."

# Try broad reset first (may work better on some macOS versions)
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true

# Then per-service resets as fallback
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true

# Verify Accessibility entry was actually removed
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
ACCESSIBILITY_CLEARED=true
if [ -f "$TCC_DB" ]; then
    REMAINING=$(sqlite3 "$TCC_DB" "SELECT COUNT(*) FROM access WHERE client='$BUNDLE_ID' AND service='kTCCServiceAccessibility'" 2>/dev/null || echo "error")
    if [ "$REMAINING" = "error" ]; then
        # sqlite3 query failed (SIP-protected or schema changed) — can't verify
        ACCESSIBILITY_CLEARED=unknown
    elif [ "$REMAINING" -gt 0 ] 2>/dev/null; then
        ACCESSIBILITY_CLEARED=false
    fi
fi

if [ "$ACCESSIBILITY_CLEARED" = "false" ] || [ "$ACCESSIBILITY_CLEARED" = "unknown" ]; then
    echo "   Cleared Microphone and Screen Recording entries"
    echo ""
    echo "   ⚠️  Could not automatically remove Accessibility permission."
    echo "   Please manually remove \"Look Ma No Hands\" from:"
    echo "   System Settings > Privacy & Security > Accessibility"
else
    echo "   Cleared Microphone, Accessibility, and Screen Recording entries"
fi

# Remove UserDefaults (current and legacy bundle IDs)
echo "Removing preferences..."
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f ~/Library/Preferences/"${BUNDLE_ID}.plist" 2>/dev/null || true
# Legacy bundle IDs from earlier development
defaults delete com.qaid.LookMaNoHands 2>/dev/null || true
rm -f ~/Library/Preferences/com.qaid.LookMaNoHands* 2>/dev/null || true
rm -f ~/Library/Preferences/LookMaNoHands.plist 2>/dev/null || true
defaults delete LookMaNoHands 2>/dev/null || true
rm -rf ~/Library/Containers/com.qaid.LookMaNoHands 2>/dev/null || true
echo "   Removed app preferences"

# Remove Application Support data (vocabulary, hotkey config, etc.)
echo "Removing app data..."
rm -rf ~/Library/Application\ Support/LookMaNoHands
echo "   Removed ~/Library/Application Support/LookMaNoHands"

echo ""
echo "Uninstall complete. Look Ma No Hands has been fully removed."
