#!/bin/bash
set -e

# Uninstall Look Ma No Hands
# Removes the app, preferences, privacy permissions, and support data.
# Usage: ./scripts/uninstall.sh

BUNDLE_ID="com.lookmanohands.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Uninstalling Look Ma No Hands..."
echo ""

# Graceful shutdown
echo "Stopping app..."
APP_PID=$(pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null || true)
if [ -n "$APP_PID" ]; then
    osascript -e 'tell application "Look Ma No Hands" to quit' 2>/dev/null || true
    sleep 2
    if kill -0 "$APP_PID" 2>/dev/null; then
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
echo "Clearing privacy permissions..."
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
echo "   Cleared Microphone, Accessibility, and Screen Recording entries"

# Remove UserDefaults
echo "Removing preferences..."
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f ~/Library/Preferences/"${BUNDLE_ID}.plist" 2>/dev/null || true
echo "   Removed app preferences"

# Remove Application Support data (vocabulary, hotkey config, etc.)
echo "Removing app data..."
rm -rf ~/Library/Application\ Support/LookMaNoHands
echo "   Removed ~/Library/Application Support/LookMaNoHands"

# Clear icon cache
if [ -d ~/Library/Caches/com.apple.iconservices.store ]; then
    rm -rf ~/Library/Caches/com.apple.iconservices.store
    killall Dock 2>/dev/null || true
fi

echo ""
echo "Uninstall complete. Look Ma No Hands has been fully removed."
