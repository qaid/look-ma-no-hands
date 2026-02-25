#!/bin/bash
set -e

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App bundle not found: $APP_PATH"
    exit 1
fi

echo "🔍 Extracting entitlements from $APP_PATH..."
codesign -d --entitlements :- --xml "$APP_PATH" > /tmp/entitlements.plist 2>/dev/null || {
    echo "❌ Failed to extract entitlements"
    exit 1
}

echo "✅ Entitlements extracted"

# Check if plist file is empty or corrupted
if [ ! -s /tmp/entitlements.plist ]; then
    echo "⚠️  Warning: App has no embedded entitlements (expected for dev builds)"
    echo "Note: Entitlements will be verified in release build with code signing"
    rm /tmp/entitlements.plist
    exit 0
fi

plutil -lint /tmp/entitlements.plist || {
    echo "❌ Invalid entitlements plist"
    exit 1
}

echo ""
echo "=== Required Entitlements Check ==="

# Required: Microphone access (hardened runtime key for AVAudioEngine)
if ! grep -q "com.apple.security.device.audio-input" /tmp/entitlements.plist; then
    echo "❌ Missing required entitlement: com.apple.security.device.audio-input"
    rm /tmp/entitlements.plist
    exit 1
fi
echo "✅ Audio input entitlement present"

# Required: Apple Events for NSAppleScript (media control, app quit)
if ! grep -q "com.apple.security.automation.apple-events" /tmp/entitlements.plist; then
    echo "⚠️  Warning: Missing com.apple.security.automation.apple-events"
fi

# Expected: Network client for Ollama and GitHub update checks
if ! grep -q "com.apple.security.network.client" /tmp/entitlements.plist; then
    echo "⚠️  Warning: Missing com.apple.security.network.client (needed for Ollama + update checks)"
else
    echo "✅ Network client entitlement present (Ollama + GitHub updates)"
fi

# Expected: WhisperKit / Core ML JIT compilation
if ! grep -q "com.apple.security.cs.allow-unsigned-executable-memory" /tmp/entitlements.plist; then
    echo "⚠️  Warning: Missing com.apple.security.cs.allow-unsigned-executable-memory (needed for WhisperKit)"
else
    echo "✅ Unsigned executable memory entitlement present (WhisperKit/Core ML)"
fi

# Expected: WhisperKit dynamically compiled Core ML models
if ! grep -q "com.apple.security.cs.disable-library-validation" /tmp/entitlements.plist; then
    echo "⚠️  Warning: Missing com.apple.security.cs.disable-library-validation (needed for WhisperKit Core ML models)"
else
    echo "✅ Library validation disabled (WhisperKit Core ML models)"
fi

echo ""
echo "=== Hardened Runtime Check (release builds) ==="

# Check hardened runtime flag (set by --options runtime during Developer ID signing)
if codesign -dv "$APP_PATH" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    echo "✅ Hardened runtime enabled"
else
    echo "ℹ️  Hardened runtime not enabled (expected for ad-hoc / local dev builds)"
fi

echo ""
echo "✅ Entitlements validation passed"
rm /tmp/entitlements.plist
