#!/bin/bash
set -e

echo "🔨 Building Look Ma No Hands..."
swift build -c release

echo "📦 Deploying to ~/Applications..."
killall LookMaNoHands 2>/dev/null || true
sleep 1

cp ".build/release/LookMaNoHands" ~/Applications/LookMaNoHands.app/Contents/MacOS/LookMaNoHands
chmod +x ~/Applications/LookMaNoHands.app/Contents/MacOS/LookMaNoHands

echo "✅ Deployed! Launching app..."
open ~/Applications/LookMaNoHands.app

echo "🎉 Done!"
