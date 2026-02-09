# Security Overview

This document summarises the security posture of Look Ma No Hands, the measures in place to protect users, and the audit work completed to date.

## Design Philosophy

Look Ma No Hands is built on a simple principle: **your data never leaves your Mac**.

All audio recording, speech-to-text transcription, text formatting, and meeting analysis happen entirely on-device. There are no cloud services, no telemetry, no analytics, and no accounts. The only outbound network requests the app ever makes are to download Whisper models from Hugging Face and to check for app updates on GitHub — both initiated explicitly by the user.

Because the app requires powerful system permissions (Accessibility, Microphone, Screen Recording), we treat security as a first-class concern rather than an afterthought.

## Completed Security Work

The following sections summarise findings from a comprehensive security audit ([#108](https://github.com/qaid/look-ma-no-hands/issues/108)) and the hardening work that followed across three pull requests.

### PR #126 — Compiler Safety & Dangerous Script Removal

| Finding | Severity | Status |
|---------|----------|--------|
| **BUILD-001**: Dangerous system-wide toolchain deletion script (`fix_toolchain.sh`) | Critical | Resolved |
| **CODE-002**: `WhisperService` missing Sendable conformance — potential data races | Medium | Resolved |
| **CODE-004**: Unsafe pointer usage in Core Audio integration | Medium | Resolved |

**Key changes:**
- Removed `fix_toolchain.sh`, which ran `sudo rm -rf` against system developer tools
- Added `@unchecked Sendable` conformance to `WhisperService` with documented thread-safety guarantees via serial `DispatchQueue`
- Replaced bare `&name` pointer to `CFString` with proper `withUnsafeMutablePointer` lifetime management
- Achieved clean release build with zero compiler warnings

### PR #127 — Update Verification & Graceful Shutdown

| Finding | Severity | Status |
|---------|----------|--------|
| **CODE-010**: Update mechanism downloads and installs without cryptographic verification | Critical | Resolved |
| **BUILD-002** (partial): `deploy.sh` uses `killall` — abrupt termination risks data loss | Critical | Resolved |

**Key changes:**
- Added `codesign --verify --deep --strict` signature verification before installing downloaded updates
- Added download size validation (500 MB limit) and content-type checks
- Replaced `killall` with graceful AppleScript-based shutdown and a 2-second fallback

### PR #131 — Security Hardening (Workstreams 1–4)

This PR addressed 10 findings across four parallel workstreams.

#### Workstream 1 — Model Download Security (HIGH)

| Finding | Description | Status |
|---------|-------------|--------|
| **DEP-002** | SHA-256 checksum verification for downloaded Whisper models | Resolved |
| **CODE-011** | Download size validation against known model size ranges | Resolved |
| **CODE-004** | Safe unzip with path-traversal detection and zip-bomb timeout | Resolved |

#### Workstream 2 — Build Script Security (MEDIUM)

| Finding | Description | Status |
|---------|-------------|--------|
| **BUILD-004** | `deploy.sh` unconditionally reset user preferences — now requires `--reset-defaults` flag | Resolved |
| **BUILD-002** | Destructive `rm -rf` calls in `deploy.sh` and `create-dmg.sh` now guarded by existence checks | Resolved |

#### Workstream 3 — Runtime Security (MEDIUM)

| Finding | Description | Status |
|---------|-------------|--------|
| **CODE-007** | Screen recording permission check always returned `true` — now uses `CGPreflightScreenCaptureAccess()` | Resolved |
| **CODE-008** | Crash reports leaked transcription character count — now fully redacted | Resolved |

#### Workstream 4 — CI/CD Security (LOW)

| Finding | Description | Status |
|---------|-------------|--------|
| **DEP-001** | SwiftWhisper pinned to exact Git revision instead of semver range | Resolved |
| **CICD-001** | Added Dependabot for weekly dependency scanning and a `Package.resolved` integrity verification workflow | Resolved |
| **CICD-002** | Release artifacts now include SHA-256 checksums and a Software Bill of Materials (SBOM) | Resolved |

## Current Security Posture

### What is in place

- **No network data exfiltration** — all processing is local; no telemetry, no analytics
- **Verified model downloads** — SHA-256 checksums and size-range validation before any model is loaded
- **Verified app updates** — cryptographic signature verification before installation
- **Safe archive extraction** — path-traversal detection and timeout-based zip-bomb protection
- **Accurate permission reporting** — screen recording permission state reflects reality
- **Privacy-safe crash reports** — transcription content fully redacted, no metadata leakage
- **Pinned dependencies** — SwiftWhisper locked to a specific commit; `Package.resolved` integrity verified in CI
- **Automated dependency scanning** — Dependabot monitors for vulnerabilities weekly
- **Release provenance** — every release ships with SHA-256 checksums and an SBOM
- **Safe build scripts** — destructive operations guarded, user settings preserved by default

### Known limitations / future work

| Item | Issue | Notes |
|------|-------|-------|
| App notarization and hardened runtime | [#124](https://github.com/qaid/look-ma-no-hands/issues/124) | Requires Apple Developer Program membership; ad-hoc signing works for local use |
| Update signature checks accept ad-hoc signatures | — | Production distribution should verify a specific Developer ID |
| No App Sandbox | — | Disabled because Accessibility and ScreenCaptureKit APIs require it; entitlements file is prepared for when hardened runtime is enabled |

## Reporting a Vulnerability

If you discover a security issue, please open a GitHub issue with the `security` label or contact the maintainer directly. We take all reports seriously and aim to respond within 48 hours.
