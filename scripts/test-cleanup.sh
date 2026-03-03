#!/bin/bash

# Clean slate script for testing Look Ma No Hands
# Removes all cached models, preferences, permissions, and app state
# Usage: ./test-cleanup.sh

set -e

BUNDLE_ID="com.lookmanohands.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "🧹 Cleaning Look Ma No Hands environment..."
echo ""

# Kill any running instances
APP_PID=$(pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null || true)
if [ -n "$APP_PID" ]; then
    echo "⏹️  Stopping running instance..."
    osascript -e 'tell application "Look Ma No Hands" to quit' 2>/dev/null || true
    sleep 2
    if kill -0 "$APP_PID" 2>/dev/null; then
        kill -9 "$APP_PID" 2>/dev/null || true
        sleep 1
    fi
fi

# Remove app cache
echo "🗑️  Removing WhisperKit model cache..."
rm -rf ~/Library/Caches/models/argmaxinc/whisperkit-coreml
echo "   ✓ Removed ~/Library/Caches/models/argmaxinc/whisperkit-coreml"

# Remove app preferences
echo "🗑️  Removing app preferences..."
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f ~/Library/Preferences/"${BUNDLE_ID}.plist" 2>/dev/null || true
# Legacy bundle IDs from earlier development
defaults delete com.qaid.LookMaNoHands 2>/dev/null || true
rm -f ~/Library/Preferences/com.qaid.LookMaNoHands* 2>/dev/null || true
rm -f ~/Library/Preferences/LookMaNoHands.plist 2>/dev/null || true
defaults delete LookMaNoHands 2>/dev/null || true
rm -rf ~/Library/Containers/com.qaid.LookMaNoHands 2>/dev/null || true
echo "   ✓ Removed app preferences and UserDefaults"

# Remove app support data (vocabulary, hotkey config, etc.)
echo "🗑️  Removing app support data..."
rm -rf ~/Library/Application\ Support/LookMaNoHands
echo "   ✓ Removed app support data"

# Reset TCC privacy permissions (removes ghost entries from System Settings)
echo "🗑️  Clearing privacy permissions..."
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
echo "   ✓ Cleared Microphone, Accessibility, and Screen Recording entries"

# Remove app bundles and unregister from Launch Services
for APP in ~/Applications/"Look Ma No Hands.app" ~/Applications/LookMaNoHands.app; do
    if [ -d "$APP" ]; then
        echo "🗑️  Removing $APP..."
        "$LSREGISTER" -u "$APP" 2>/dev/null || true
        rm -rf "$APP"
        echo "   ✓ Removed"
    fi
done

echo ""
echo "✅ Clean-up complete!"
echo ""
echo "Next steps for testing:"
echo "  1. Rebuild and deploy:  ./scripts/deploy.sh"
echo "  2. Launch the app:       open ~/Applications/\"Look Ma No Hands.app\""
echo "  3. Complete onboarding - watch for:"
echo "     - Log: '🔥 Warming up Neural Engine...'"
echo "     - Log: '✅ Neural Engine warm-up complete in X.XXs'"
echo "  4. Test first dictation (should be <1 second latency)"
echo ""
