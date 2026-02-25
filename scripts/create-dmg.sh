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

# Copy Info.plist
cp "Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

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
        --deep \
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

# Create DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}"

# Clean up temp dir
[ -d "${DMG_TEMP}" ] && rm -rf "${DMG_TEMP}"

# Sign the DMG with Developer ID if available
if [ -n "${DEVELOPER_ID_APPLICATION}" ]; then
    echo "Signing DMG with Developer ID..."
    codesign --force --sign "${DEVELOPER_ID_APPLICATION}" "${BUILD_DIR}/${DMG_NAME}"
fi

# Notarize and staple if credentials are provided
if [ -n "${DEVELOPER_ID_APPLICATION}" ] && [ -n "${APPLE_ID}" ] && [ -n "${APPLE_TEAM_ID}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD}" ]; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "${BUILD_DIR}/${DMG_NAME}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
        --wait \
        --timeout 30m

    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "${BUILD_DIR}/${DMG_NAME}"

    echo "Verifying notarization..."
    spctl --assess --type open --context context:primary-signature "${BUILD_DIR}/${DMG_NAME}"
    echo "✅ Notarization verified"
else
    if [ -n "${DEVELOPER_ID_APPLICATION}" ]; then
        echo "Notarization credentials not set — skipping notarization (APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD required)"
    fi
fi

echo "DMG created: ${BUILD_DIR}/${DMG_NAME}"
