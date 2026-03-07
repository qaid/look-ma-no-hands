#!/bin/bash
set -e

DMG_PATH="${1:?Usage: notarize-dmg.sh <path-to-dmg>}"

if [ ! -f "${DMG_PATH}" ]; then
    echo "Error: DMG not found at ${DMG_PATH}"
    exit 1
fi

if [ -z "${APPLE_ID}" ] || [ -z "${APPLE_TEAM_ID}" ] || [ -z "${APPLE_APP_SPECIFIC_PASSWORD}" ]; then
    echo "Skipping notarization: APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD must be set"
    exit 0
fi

echo "Submitting DMG for notarization: ${DMG_PATH}"
NOTARY_OUTPUT=$(xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --wait \
    --timeout 30m 2>&1) || {
    echo "Notarization failed or timed out"
    echo "${NOTARY_OUTPUT}"
    SUBMISSION_ID=$(echo "${NOTARY_OUTPUT}" | grep -o 'id: [0-9a-f-]*' | head -1 | cut -d' ' -f2)
    if [ -n "${SUBMISSION_ID}" ]; then
        echo "Fetching notarization log for submission ${SUBMISSION_ID}..."
        xcrun notarytool log "${SUBMISSION_ID}" \
            --apple-id "${APPLE_ID}" \
            --team-id "${APPLE_TEAM_ID}" \
            --password "${APPLE_APP_SPECIFIC_PASSWORD}" 2>&1 || true
    fi
    exit 1
}
echo "${NOTARY_OUTPUT}"

echo "Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "Notarization complete and stapled."
