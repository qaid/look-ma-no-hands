#!/bin/bash

# Clean slate script for testing LookMaNoHands
# Removes all cached models, preferences, and app state
# Usage: ./test-cleanup.sh

set -e

echo "🧹 Cleaning Look Ma No Hands environment..."
echo ""

# Kill any running instances
if pgrep -x "LookMaNoHands" > /dev/null; then
    echo "⏹️  Stopping running LookMaNoHands instances..."
    killall LookMaNoHands
    sleep 1
fi

# Remove app cache
echo "🗑️  Removing WhisperKit model cache..."
rm -rf ~/Library/Caches/models/argmaxinc/whisperkit-coreml
echo "   ✓ Removed ~/Library/Caches/models/argmaxinc/whisperkit-coreml"

# Remove app preferences
echo "🗑️  Removing app preferences..."
rm -f ~/Library/Preferences/com.qaid.LookMaNoHands* 2>/dev/null || true
rm -f ~/Library/Preferences/LookMaNoHands.plist 2>/dev/null || true
# Clear UserDefaults via defaults command (more thorough)
defaults delete com.qaid.LookMaNoHands 2>/dev/null || true
defaults delete LookMaNoHands 2>/dev/null || true
# Also check for any sandbox container preferences
rm -rf ~/Library/Containers/com.qaid.LookMaNoHands 2>/dev/null || true
echo "   ✓ Removed app preferences and UserDefaults"

# Remove app support data
echo "🗑️  Removing app support data..."
rm -rf ~/Library/Application\ Support/LookMaNoHands
echo "   ✓ Removed app support data"

# Optional: Remove the app from Applications
if [ -d ~/Applications/LookMaNoHands.app ]; then
    echo "🗑️  Removing installed app from ~/Applications..."
    rm -rf ~/Applications/LookMaNoHands.app
    echo "   ✓ Removed ~/Applications/LookMaNoHands.app"
fi

echo ""
echo "✅ Clean-up complete!"
echo ""
echo "Next steps for testing:"
echo "  1. Rebuild and deploy:  ./deploy.sh"
echo "  2. Launch the app:       open ~/Applications/LookMaNoHands.app"
echo "  3. Complete onboarding - watch for:"
echo "     - Log: '🔥 Warming up Neural Engine...'"
echo "     - Log: '✅ Neural Engine warm-up complete in X.XXs'"
echo "  4. Test first dictation (should be <1 second latency)"
echo ""
