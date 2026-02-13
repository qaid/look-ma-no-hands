#!/bin/bash
set -e

# Parse command-line flags
RESET_DEFAULTS=false
if [[ "$1" == "--reset-defaults" ]]; then
    RESET_DEFAULTS=true
    echo "🧹 Will reset app defaults (--reset-defaults flag provided)"
fi

echo "🔨 Building Look Ma No Hands..."
swift build -c release

echo "📦 Deploying to ~/Applications..."

# Graceful shutdown instead of killall (Security Fix: BUILD-002)
echo "🛑 Attempting graceful app shutdown..."
APP_PID=$(pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null || true)
if [ -n "$APP_PID" ]; then
    echo "   Found running instance (PID: $APP_PID), requesting quit..."
    osascript -e 'tell application "Look Ma No Hands" to quit' 2>/dev/null || true
    sleep 2

    # Check if app is still running
    if kill -0 "$APP_PID" 2>/dev/null; then
        echo "   ⚠️  App still running, force terminating..."
        kill -9 "$APP_PID" 2>/dev/null || true
        sleep 1
    else
        echo "   ✅ App quit gracefully"
    fi
else
    echo "   ℹ️  App not currently running"
fi

# Remove old app bundle if it exists
if [ -d ~/Applications/LookMaNoHands.app ]; then
    echo "🗑️ Removing old app bundle..."
    rm -rf ~/Applications/LookMaNoHands.app
fi

# Create app bundle structure with proper name (with spaces)
APP_PATH=~/Applications/"Look Ma No Hands.app"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy Info.plist if it exists
if [ -f "Resources/Info.plist" ]; then
    cp "Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
fi

# Copy icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

cp ".build/release/LookMaNoHands" "$APP_PATH/Contents/MacOS/LookMaNoHands"
chmod +x "$APP_PATH/Contents/MacOS/LookMaNoHands"

# Code sign the app to bind Info.plist (without --deep to avoid invalidating the signature)
codesign --force --sign - "$APP_PATH"

# Update Launch Services to recognize the new bundle name
echo "🔄 Updating Launch Services database..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_PATH"

# Clear icon cache to show new icon (safe system cache operation)
echo ""
echo "=== Icon Cache & App Defaults ==="
if [ -d ~/Library/Caches/com.apple.iconservices.store ]; then
    echo "🔄 Clearing icon cache..."
    rm -rf ~/Library/Caches/com.apple.iconservices.store
    killall Dock 2>/dev/null || true
    killall Finder 2>/dev/null || true
fi

# App defaults (conditional based on flag)
if [ "$RESET_DEFAULTS" = true ]; then
    echo "🧹 Resetting app defaults..."
    defaults delete com.lookmanohands.app 2>/dev/null || true
    defaults write com.lookmanohands.app triggerKey "Right Option"
    echo "   ✅ App defaults reset to factory settings"
else
    echo "ℹ️  Preserving existing app defaults"
    echo "   (use './deploy.sh --reset-defaults' to reset)"
fi

echo "✅ Deployed! Launching app..."
open "$APP_PATH"

echo "🎉 Done!"
