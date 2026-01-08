#!/bin/bash
set -e

echo "🔨 Building Look Ma No Hands..."
swift build -c release

echo "📦 Deploying to ~/Applications..."
killall LookMaNoHands 2>/dev/null || true
sleep 1

# Create app bundle structure if it doesn't exist
mkdir -p ~/Applications/LookMaNoHands.app/Contents/MacOS
mkdir -p ~/Applications/LookMaNoHands.app/Contents/Resources

# Copy Info.plist if it exists
if [ -f "Resources/Info.plist" ]; then
    cp "Resources/Info.plist" ~/Applications/LookMaNoHands.app/Contents/Info.plist
fi

# Copy icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" ~/Applications/LookMaNoHands.app/Contents/Resources/AppIcon.icns
fi

cp ".build/release/LookMaNoHands" ~/Applications/LookMaNoHands.app/Contents/MacOS/LookMaNoHands
chmod +x ~/Applications/LookMaNoHands.app/Contents/MacOS/LookMaNoHands

# Code sign the app to bind Info.plist (without --deep to avoid invalidating the signature)
codesign --force --sign - ~/Applications/LookMaNoHands.app

echo "✅ Deployed! Launching app..."
open ~/Applications/LookMaNoHands.app

echo "🎉 Done!"
