#!/bin/bash
set -e

BUNDLE_ID="com.lookmanohands.app"

# Parse command-line flags
RESET_DEFAULTS=false
if [[ "$1" == "--reset-defaults" ]]; then
    RESET_DEFAULTS=true
    echo "🧹 Will reset app defaults (--reset-defaults flag provided)"
fi

echo "🔨 Preparing build..."
source "$(dirname "$0")/inject-build-info.sh"

# Build the release
echo "🔨 Building Look Ma No Hands..."
swift build -c release

echo "📦 Deploying to ~/Applications..."

# Backup user data files before killing the app (vocabulary, hotkey config)
# These live in Application Support and must survive deploy + --reset-defaults
APP_SUPPORT_DIR=~/Library/Application\ Support/LookMaNoHands
BACKUP_DIR=$(mktemp -d)
if [ -d "$APP_SUPPORT_DIR" ]; then
    for f in vocabulary.json toggleHotkey.json; do
        if [ -f "$APP_SUPPORT_DIR/$f" ]; then
            cp "$APP_SUPPORT_DIR/$f" "$BACKUP_DIR/$f"
        fi
    done
fi

# Graceful shutdown instead of killall (Security Fix: BUILD-002)
echo "🛑 Attempting graceful app shutdown..."
APP_PID=$(pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null || true)
if [ -n "$APP_PID" ]; then
    echo "   Found running instance (PID: $APP_PID), requesting quit..."
    osascript -e 'tell application "Look Ma No Hands" to quit' 2>/dev/null || true
    sleep 2

    # Re-check that the PID is still our app before force-killing
    if kill -0 "$APP_PID" 2>/dev/null && pgrep -f "Look Ma No Hands.app/Contents/MacOS" 2>/dev/null | grep -q "^${APP_PID}$"; then
        echo "   ⚠️  App still running, force terminating..."
        kill -9 "$APP_PID" 2>/dev/null || true
        sleep 1
    else
        echo "   ✅ App quit gracefully"
    fi
else
    echo "   ℹ️  App not currently running"
fi

# Restore user data files after app shutdown (protects against wipe during quit)
if [ -d "$BACKUP_DIR" ]; then
    for f in vocabulary.json toggleHotkey.json; do
        if [ -f "$BACKUP_DIR/$f" ]; then
            # Only restore if the backup has actual data (not just "[]")
            CONTENT=$(cat "$BACKUP_DIR/$f" 2>/dev/null || true)
            if [ -n "$CONTENT" ] && [ "$CONTENT" != "[]" ]; then
                mkdir -p "$APP_SUPPORT_DIR"
                cp "$BACKUP_DIR/$f" "$APP_SUPPORT_DIR/$f"
            fi
        fi
    done
    rm -rf "$BACKUP_DIR"
fi

# Reset Accessibility TCC entry to force clean permission state for new binary
# Ad-hoc signing changes binary identity each build, causing stale TCC entries
echo "🔐 Resetting Accessibility permission for clean re-grant..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

# Remove old app bundle if it exists (legacy name without spaces)
if [ -d ~/Applications/LookMaNoHands.app ]; then
    echo "🗑️ Removing old app bundle..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u ~/Applications/LookMaNoHands.app 2>/dev/null || true
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

# Copy SPM resource bundles so Bundle.module resolves correctly in the deployed app.
# Without these, resources (models, tokenizer configs) are unavailable at runtime
# and Bundle.main context differs from the development build.
for bundle in .build/release/*.bundle; do
    if [ -d "$bundle" ]; then
        bundle_name=$(basename "$bundle")
        echo "📦 Copying resource bundle: $bundle_name"
        cp -R "$bundle" "$APP_PATH/Contents/Resources/$bundle_name"
    fi
done

# Code sign the app to bind Info.plist (without --deep to avoid invalidating the signature)
codesign --force --sign - --entitlements Resources/LookMaNoHands.entitlements "$APP_PATH"

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
    echo "🧹 Resetting app preferences (preserving vocabulary & user data)..."
    # Delete all preference keys EXCEPT user data worth preserving
    # Note: vocabulary and toggleHotkey now live in Application Support files,
    # but legacy UserDefaults keys (customVocabulary, toggleHotkeyShortcut) must
    # also be preserved for users who haven't yet launched the app to trigger migration.
    # hasCompletedOnboarding is preserved to avoid forcing full re-onboarding.
    PRESERVE_KEYS="hasCompletedOnboarding|meetingTypePrompts|customVocabulary|toggleHotkeyShortcut"
    ALL_KEYS=$(defaults read com.lookmanohands.app 2>/dev/null | grep -oE '^\s{4}[a-zA-Z][a-zA-Z0-9]*' | sed 's/^ *//' || true)
    for key in $ALL_KEYS; do
        if ! echo "$key" | grep -qE "^($PRESERVE_KEYS)$"; then
            defaults delete com.lookmanohands.app "$key" 2>/dev/null || true
        fi
    done
    defaults write com.lookmanohands.app triggerKey "Right Option"
    echo "   ✅ App preferences reset to factory settings"
    echo "   ℹ️  Vocabulary, custom prompts, and onboarding state preserved"
else
    echo "ℹ️  Preserving existing app defaults"
    echo "   (use './deploy.sh --reset-defaults' to reset)"
fi

echo "✅ Deployed! Launching app..."
open "$APP_PATH"

echo "🎉 Done!"
