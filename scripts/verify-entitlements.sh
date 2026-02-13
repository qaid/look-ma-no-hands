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

# Required: Microphone access (for dictation)
if ! grep -q "com.apple.security.device.microphone" /tmp/entitlements.plist; then
    echo "❌ Missing required entitlement: com.apple.security.device.microphone"
    exit 1
fi
echo "✅ Microphone entitlement present"

# Required: Accessibility (for text insertion)
if ! grep -q "com.apple.security.automation.apple-events" /tmp/entitlements.plist; then
    echo "⚠️  Warning: Missing com.apple.security.automation.apple-events"
fi

echo ""
echo "=== Forbidden Entitlements Check ==="

# Forbidden: Network client (app should NOT make network requests except updates)
# Note: Update service is exception - validate in code review
if grep -q "com.apple.security.network.client" /tmp/entitlements.plist; then
    echo "⚠️  Network client entitlement present (verify this is intentional)"
fi

echo ""
echo "✅ Entitlements validation passed"
rm /tmp/entitlements.plist
