#!/bin/bash
set -e

echo "🔨 Building Look Ma No Hands..."
swift build -c release

echo "📦 Deploying to ~/Applications..."
killall LookMaNoHands 2>/dev/null || true
killall "Look Ma No Hands" 2>/dev/null || true
sleep 1

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

# Clear icon cache to show new icon
echo "🔄 Clearing icon cache..."
rm -rf ~/Library/Caches/com.apple.iconservices.store
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

# Reset app settings so onboarding shows on launch
echo "🧹 Clearing app defaults..."
defaults delete com.lookmanohands.app 2>/dev/null || true

echo "✅ Deployed! Launching app..."
open "$APP_PATH"

echo "🎉 Done!"
