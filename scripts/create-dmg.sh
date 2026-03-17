#!/bin/bash
set -e

APP_NAME="Look Ma No Hands"
BUNDLE_ID="com.lookmanohands.app"
VERSION="${1:-1.0}"
DMG_NAME="Look Ma No Hands ${VERSION}.dmg"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
ENTITLEMENTS="Resources/LookMaNoHands.entitlements"

echo "Building ${APP_NAME} v${VERSION}..."
swift build -c release

echo "Creating app bundle..."
[ -d "${APP_PATH}" ] && rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

# Copy binary
cp ".build/release/LookMaNoHands" "${APP_PATH}/Contents/MacOS/LookMaNoHands"
chmod +x "${APP_PATH}/Contents/MacOS/LookMaNoHands"

# Copy Info.plist and inject version from build argument
cp "Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${VERSION}" "${APP_PATH}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${VERSION}" "${APP_PATH}/Contents/Info.plist"

# Copy icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"
fi

# Code sign: Developer ID (release) or ad-hoc (local dev)
if [ -n "${DEVELOPER_ID_APPLICATION}" ]; then
    echo "Signing with Developer ID: ${DEVELOPER_ID_APPLICATION}"
    codesign --force --options runtime \
        --sign "${DEVELOPER_ID_APPLICATION}" \
        --entitlements "${ENTITLEMENTS}" \
        "${APP_PATH}"
    # Verify signature
    codesign --verify --deep --strict "${APP_PATH}"
    echo "✅ Developer ID signature verified"
else
    echo "No DEVELOPER_ID_APPLICATION set — using ad-hoc signing"
    codesign --force --sign - "${APP_PATH}"
fi

echo "Creating DMG..."
[ -f "${BUILD_DIR}/${DMG_NAME}" ] && rm -f "${BUILD_DIR}/${DMG_NAME}"

# Create temporary DMG directory
DMG_TEMP="${BUILD_DIR}/dmg-temp"
[ -d "${DMG_TEMP}" ] && rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"
cp -R "${APP_PATH}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

# Phase A — Create read-write DMG
TEMP_DMG="${BUILD_DIR}/temp.dmg"
[ -f "${TEMP_DMG}" ] && rm -f "${TEMP_DMG}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDRW \
    "${TEMP_DMG}"

# Clean up temp dir
[ -d "${DMG_TEMP}" ] && rm -rf "${DMG_TEMP}"

# Phase B — Mount, copy background, style via AppleScript
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "${TEMP_DMG}" | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
echo "Mounted at: ${MOUNT_DIR}"

mkdir -p "${MOUNT_DIR}/.background"
cp Resources/dmg-background@2x.png "${MOUNT_DIR}/.background/background@2x.png"
cp Resources/dmg-background.png "${MOUNT_DIR}/.background/background.png"

# Style the DMG window with AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 760, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {170, 200}
        set position of item "Applications" of container window to {490, 200}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Phase C — Detach and convert to compressed read-only
sync
hdiutil detach "${MOUNT_DIR}"
hdiutil convert "${TEMP_DMG}" -format UDZO -o "${BUILD_DIR}/${DMG_NAME}"
rm -f "${TEMP_DMG}"

# Sign the DMG with Developer ID if available
if [ -n "${DEVELOPER_ID_APPLICATION}" ]; then
    echo "Signing DMG with Developer ID..."
    codesign --force --sign "${DEVELOPER_ID_APPLICATION}" "${BUILD_DIR}/${DMG_NAME}"
fi

# Notarization is handled separately (see notarize-dmg.sh or CI workflow)
if [ -n "${DEVELOPER_ID_APPLICATION}" ]; then
    echo "DMG is Developer ID signed. Run scripts/notarize-dmg.sh to notarize."
fi

echo "DMG created: ${BUILD_DIR}/${DMG_NAME}"
