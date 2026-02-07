#!/bin/bash
set -e

APP_NAME="Look Ma No Hands"
BUNDLE_ID="com.lookmanohands.app"
VERSION="${1:-1.0}"
DMG_NAME="LookMaNoHands-${VERSION}.dmg"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "Building ${APP_NAME} v${VERSION}..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

# Copy binary
cp ".build/release/LookMaNoHands" "${APP_PATH}/Contents/MacOS/LookMaNoHands"
chmod +x "${APP_PATH}/Contents/MacOS/LookMaNoHands"

# Copy Info.plist
cp "Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

# Copy icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code sign
codesign --force --sign - "${APP_PATH}"

echo "Creating DMG..."
rm -f "${BUILD_DIR}/${DMG_NAME}"

# Create temporary DMG directory
DMG_TEMP="${BUILD_DIR}/dmg-temp"
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"
cp -R "${APP_PATH}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

# Create DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}"

# Clean up
rm -rf "${DMG_TEMP}"

echo "DMG created: ${BUILD_DIR}/${DMG_NAME}"
