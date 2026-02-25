# Notarization Setup Guide

This document explains how to configure Apple notarization for Look Ma No Hands so that distributed DMGs install without Gatekeeper warnings.

## Prerequisites

- **Apple Developer Program** membership (paid, $99/year)
- **Developer ID Application** certificate in your keychain
- **App-specific password** for your Apple ID (for notarytool)
- Xcode Command Line Tools installed (`xcode-select --install`)

## How it Works

The release pipeline (`scripts/create-dmg.sh`) detects environment variables at build time:

| Env var set? | Behavior |
|---|---|
| No `DEVELOPER_ID_APPLICATION` | Ad-hoc signing (local dev, no Gatekeeper trust) |
| `DEVELOPER_ID_APPLICATION` only | Developer ID signing + hardened runtime, no notarization |
| All credentials set | Developer ID signing + notarization + stapling |

## GitHub Secrets Setup

Configure these 6 secrets in **Settings → Secrets and variables → Actions**:

### 1. Export your Developer ID certificate as a .p12

```bash
# In Keychain Access: right-click your "Developer ID Application: ..." cert → Export
# Save as certificate.p12 with a strong password
```

### 2. Base64-encode the .p12

```bash
base64 -i certificate.p12 | pbcopy   # copies to clipboard
```

Set this as `APPLE_DEVELOPER_ID_APPLICATION`.

### 3. Set remaining secrets

| Secret | Value |
|---|---|
| `APPLE_DEVELOPER_ID_APPLICATION` | Base64-encoded .p12 content |
| `APPLE_DEVELOPER_ID_APPLICATION_PASSWORD` | Password you set when exporting .p12 |
| `APPLE_ID` | Your Apple ID email address |
| `APPLE_TEAM_ID` | 10-character Team ID from [developer.apple.com/account](https://developer.apple.com/account) |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password from [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords |
| `KEYCHAIN_PASSWORD` | Any random string (used for the ephemeral CI keychain) |

### Finding your Team ID

```bash
# From command line (if cert is already in your keychain):
security find-identity -v -p codesigning | grep "Developer ID Application"
# Team ID is the 10-char string in parentheses at the end, e.g. (ABCD123456)
```

## Local Notarization Testing

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="ABCD123456"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

./scripts/create-dmg.sh 1.3.0
```

## Verification Commands

```bash
# Check Gatekeeper assessment
spctl --assess --type open --context context:primary-signature "build/Look Ma No Hands 1.3.0.dmg"

# Validate stapled notarization ticket
xcrun stapler validate "build/Look Ma No Hands 1.3.0.dmg"

# Inspect code signature
codesign -dv --verbose=4 "build/Look Ma No Hands.app"

# Check hardened runtime flag (release builds show "flags=0x10000(runtime)")
codesign -dv "build/Look Ma No Hands.app" 2>&1 | grep flags
```

## Troubleshooting

**`errSecInternalComponent` during import**
- Wrong keychain password or the keychain is locked. Check `KEYCHAIN_PASSWORD` matches what was used to create the keychain.

**`rejected` status from notarytool**
- Run `xcrun notarytool log <submission-id>` to get the full rejection reason.
- Common cause: missing hardened runtime flag (`--options runtime`) or a required entitlement.

**`spctl` returns "rejected"**
- The staple step may have failed, or the ticket hasn't propagated yet (Apple's CDN can take a few minutes).
- Re-run `xcrun stapler staple` after a few minutes.

**`codesign: object file format unrecognized` on deep signing**
- This can happen with some Swift build artifacts. The `--deep` flag is only used in `create-dmg.sh` (release); `deploy.sh` intentionally omits it.

**Notarization works locally but not in CI**
- Verify all 6 secrets are set and not empty.
- Check that the `APPLE_DEVELOPER_ID_APPLICATION` secret contains valid base64 (no line breaks).
- The certificate import step is skipped when `secrets.APPLE_DEVELOPER_ID_APPLICATION` is empty, so the DMG falls back to ad-hoc signing.
