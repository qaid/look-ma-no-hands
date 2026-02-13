# Security Future Roadmap

This document outlines future security enhancements not included in the immediate CI/CD security automation plan. These items provide additional security value but require more design work, team collaboration, or manual processes.

---

## 1. PR Security Checklist

### Goal
Provide reviewers with a standardized checklist for evaluating security implications of code changes, particularly for security-sensitive areas identified in the codebase.

### Why This Matters
- Only 3 tests currently exist (<1% coverage)
- Manual review is the primary security control for code changes
- Security-sensitive code paths (network requests, file I/O, accessibility APIs) need careful scrutiny
- Prevents common security mistakes from reaching production

### Implementation Plan

#### Phase 1: Create Security Checklist Template

**File to create:** `.github/PULL_REQUEST_TEMPLATE/security_review.md`

**Template content:**
```markdown
# Security Review Checklist

Use this checklist when reviewing PRs that touch security-sensitive code areas.

## Trigger Conditions
Check this template if the PR modifies any of:
- [ ] Network request handling (UpdateService, OllamaService, MediaControlService)
- [ ] File I/O operations (Logger, CrashReporter, WhisperService model downloads)
- [ ] Shell command execution (UpdateService codesign verification)
- [ ] Accessibility APIs (TextInsertionService, AXUIElement operations)
- [ ] Permission checks (PermissionsChecker)
- [ ] Entitlements or Info.plist
- [ ] Build/deploy scripts (deploy.sh, create-dmg.sh)

## Security Review Questions

### Input Validation
- [ ] Are all external inputs validated (size limits, format checks, content-type verification)?
- [ ] Are file paths sanitized to prevent path traversal attacks?
- [ ] Are network responses validated before processing?

### Error Handling
- [ ] Do error messages avoid leaking sensitive information (paths, user data, system details)?
- [ ] Are errors logged safely without exposing secrets or PII?
- [ ] Does the code fail securely (default deny, safe fallback states)?

### Authentication & Authorization
- [ ] If downloading files, is signature verification enforced?
- [ ] Are permission checks performed before accessing restricted APIs?
- [ ] Are entitlements validated for new system API usage?

### Data Protection
- [ ] Is sensitive data (transcriptions, user input) handled securely?
- [ ] Are temporary files cleaned up properly?
- [ ] Is clipboard content restored after temporary use?
- [ ] Are logs redacted of sensitive information?

### Memory Safety
- [ ] Are force unwraps (`!`) avoided in critical code paths?
- [ ] Are forced casts (`as!`) replaced with safe alternatives (`as?`)?
- [ ] Is unsafe pointer usage properly guarded and lifetime-managed?
- [ ] Are optionals handled defensively?

### Network Security
- [ ] Are HTTPS URLs used (not HTTP)?
- [ ] Is certificate validation enforced (no custom trust stores)?
- [ ] Are download size limits enforced?
- [ ] Is localhost-only traffic properly isolated?

### Code Quality
- [ ] Are new dependencies necessary and from trusted sources?
- [ ] Does the code follow Swift concurrency best practices (@Sendable, actor isolation)?
- [ ] Are there race conditions or thread-safety issues?

### Testing
- [ ] Are security-critical code paths covered by tests?
- [ ] Do tests validate error handling and edge cases?
- [ ] Are tests added for any security fixes?

## Risk Assessment

**Impact if vulnerability exploited:**
- [ ] Low (minor inconvenience, no data exposure)
- [ ] Medium (app crash, local file access, temporary data leak)
- [ ] High (persistent data leak, remote code execution, privilege escalation)

**Likelihood of exploitation:**
- [ ] Low (requires physical access + user interaction + specific conditions)
- [ ] Medium (requires user interaction or specific configuration)
- [ ] High (easily triggered, no user interaction required)

**Overall Risk:** Low / Medium / High

## Additional Security Notes
<!-- Any security-specific observations, concerns, or recommendations -->

## Sign-off
- [ ] I have reviewed this PR for security issues using the checklist above
- [ ] All security concerns have been addressed or documented
- [ ] This PR does not introduce new security vulnerabilities

Reviewer: @___________
Date: YYYY-MM-DD
```

#### Phase 2: Document Security-Sensitive Code Areas

**File to create:** `docs/security-sensitive-areas.md`

**Content outline:**
```markdown
# Security-Sensitive Code Areas

This document identifies code areas that require extra security scrutiny during code review.

## Network Request Handlers

### UpdateService.swift
- **Lines 130-246**: DMG download and signature verification
- **Security controls**: Size validation (500MB limit), content-type check, codesign verification
- **Risks**: Malicious DMG installation if signature check bypassed
- **Review focus**: Ensure signature verification cannot be skipped

### OllamaService.swift
- **Lines 1-313**: Local HTTP API communication
- **Security controls**: Hardcoded localhost URL, no external network access
- **Risks**: If localhost-only constraint removed, potential SSRF
- **Review focus**: Ensure base URL remains localhost-only

## File I/O Operations

### Logger.swift
- **Lines 97-252**: Log file writing and rotation
- **Security controls**: 7-day automatic cleanup, user library directory
- **Risks**: Log files may contain transcribed text (user data)
- **Review focus**: Verify no sensitive data logged without redaction

### CrashReporter.swift
- **Lines 1-301**: Crash dump generation
- **Security controls**: Redacts lastTranscription (line 159)
- **Risks**: Crash dumps could leak app state or user data
- **Review focus**: Ensure all sensitive fields are redacted

## Accessibility APIs (Highest Risk)

### TextInsertionService.swift
- **Lines 1-560**: AXUIElement operations, text insertion, clipboard manipulation
- **Force unwraps**: Lines 99, 133, 143, 316, 360, 424 (CRITICAL PATHS)
- **Security controls**: 200-character context limit, 0.5s clipboard restoration
- **Risks**: Force unwraps can crash during text insertion; clipboard leak if restoration fails
- **Review focus**: Replace force unwraps with safe alternatives; test clipboard edge cases

## Shell Command Execution

### UpdateService.swift
- **Lines 224-244**: codesign verification subprocess
- **Security controls**: Hardcoded /usr/bin/codesign path, safe argument passing
- **Risks**: Command injection if arguments not properly escaped
- **Review focus**: Verify no user-controlled data in arguments

## Permission Checks

### PermissionsChecker.swift
- **All functions**: Microphone, Accessibility, Screen Recording permission checks
- **Security controls**: Uses native macOS APIs (AVCaptureDevice, AXIsProcessTrusted, CGPreflightScreenCaptureAccess)
- **Risks**: False positive permission checks bypass security controls
- **Review focus**: Ensure checks use correct APIs and cannot be mocked/bypassed

## Build and Deploy Scripts

### deploy.sh
- **Lines 16-34**: App process termination
- **Security controls**: Graceful shutdown via AppleScript, 2s timeout before force kill
- **Risks**: Destructive rm -rf operations (lines 38-39)
- **Review focus**: Verify paths are validated before deletion

### create-dmg.sh
- **Lines 35-48**: DMG creation and cleanup
- **Security controls**: Temporary directory isolation
- **Risks**: rm -rf of temporary directories
- **Review focus**: Ensure temp paths don't traverse to system directories

## Entitlements and Permissions

### Resources/Info.plist
- **Required entitlements**:
  - com.apple.security.device.microphone (dictation)
  - com.apple.security.automation.apple-events (accessibility)
  - com.apple.security.cs.allow-unsigned-executable-memory (WhisperKit)
- **Risks**: Removing required entitlements breaks functionality; adding unnecessary entitlements expands attack surface
- **Review focus**: Validate entitlement changes against security requirements
```

#### Phase 3: Integrate Checklist into Workflow

**Update `.github/PULL_REQUEST_TEMPLATE.md` (or create if missing):**
```markdown
## Description
<!-- Brief description of changes -->

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Security fix or enhancement

## Security Review
**Does this PR touch security-sensitive code areas?** (See [security-sensitive-areas.md](../docs/security-sensitive-areas.md))
- [ ] No - Standard review process
- [ ] Yes - Please use the [Security Review Checklist](?template=security_review.md)

Security-sensitive areas include:
- Network request handling
- File I/O operations
- Shell command execution
- Accessibility APIs
- Permission checks
- Entitlements or build scripts

## Testing
- [ ] Tests added/updated for changes
- [ ] All tests passing locally
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated (if needed)
- [ ] No new compiler warnings
```

### Verification Plan
1. Create test PR that modifies TextInsertionService.swift
2. Verify PR template prompts for security checklist
3. Fill out security checklist and validate all sections are relevant
4. Update checklist based on reviewer feedback

### Success Criteria
- [ ] Security review checklist template exists
- [ ] Security-sensitive code areas documented with line numbers
- [ ] PR template links to security checklist for relevant changes
- [ ] At least 2 PRs reviewed using the checklist (validation iteration)

---

## 2. Threat Model

### Goal
Document the app's attack surface, threat actors, and mitigations specific to a local-only macOS accessibility app. Provides security context for design decisions and helps prioritize security work.

### Why This Matters
- App requires powerful permissions (Accessibility, Microphone, Screen Recording)
- "Local-only" architecture is key security property that needs protection
- Understanding threats helps prioritize security investments
- Provides security justification for architecture decisions

### Implementation Plan

#### Phase 1: Threat Modeling Workshop

**Participants:**
- Project maintainer(s)
- 1-2 security-minded contributors (if available)
- Can be async via GitHub Discussions

**Approach:**
Use lightweight STRIDE methodology adapted for desktop apps:
- **Spoofing**: Can attacker impersonate the app or its data sources?
- **Tampering**: Can attacker modify app behavior or data in transit/at rest?
- **Repudiation**: Can attacker deny malicious actions?
- **Information Disclosure**: Can attacker access user data or system information?
- **Denial of Service**: Can attacker prevent legitimate app usage?
- **Elevation of Privilege**: Can attacker gain permissions beyond intended scope?

#### Phase 2: Document Threat Model

**File to create:** `docs/THREAT-MODEL.md`

**Template content:**
```markdown
# Look Ma No Hands - Threat Model

**Last Updated:** YYYY-MM-DD
**Version:** 1.0

## Overview

This document analyzes the security threats facing Look Ma No Hands, a privacy-focused macOS menu bar app for voice dictation and meeting transcription. The threat model guides security design decisions and prioritization of security work.

## Security Objectives

### Primary Objectives
1. **Privacy-first architecture**: All processing remains on-device; no data leaves user's Mac
2. **Minimize attack surface**: Request only essential permissions
3. **Secure by default**: Safe configuration out-of-box, no user security decisions required
4. **Fail securely**: Errors do not compromise user data or system security

### Security Properties to Protect
- **Confidentiality**: Transcribed text, meeting notes, system audio never transmitted externally
- **Integrity**: Downloaded models and updates are authentic and unmodified
- **Availability**: App functions reliably without external dependencies (except optional Ollama)

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                         User's Mac                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Look Ma No Hands.app                    │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐    │   │
│  │  │  Whisper   │  │   Text     │  │   Logger   │    │   │
│  │  │  Service   │  │ Insertion  │  │  (Logs)    │    │   │
│  │  └────────────┘  └────────────┘  └────────────┘    │   │
│  │                                                      │   │
│  │  Trust Boundary: System Permissions                 │   │
│  │  - Microphone Access (AVFoundation)                 │   │
│  │  - Accessibility (AXUIElement)                      │   │
│  │  - Screen Recording (ScreenCaptureKit)              │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↕                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │        Localhost-Only Services (Optional)            │   │
│  │        - Ollama (http://localhost:11434)             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          ↕ HTTPS Only
        ┌─────────────────────────────────────────┐
        │         External Services               │
        │  - HuggingFace (Whisper models)         │
        │  - GitHub (app updates, releases)       │
        └─────────────────────────────────────────┘
```

## Assets

### Critical Assets (High Value, Must Protect)
1. **User transcriptions** - Dictated text and meeting transcripts
2. **System audio capture** - Audio from meetings/calls
3. **Accessibility API access** - Ability to read/write any app's text fields
4. **User's installed app** - Trust in application authenticity

### Supporting Assets
1. **Downloaded Whisper models** - Integrity ensures correct transcription
2. **App settings** - User preferences (trigger key, model selection)
3. **Log files** - May contain user data or system information

## Threat Actors

### 1. Network Attacker (Remote)
**Capability**: Man-in-the-middle on network traffic
**Motivation**: Steal transcriptions, inject malicious updates/models
**Access**: No physical access; remote network position

**Threats:**
- Intercept Whisper model downloads (supply chain attack)
- Serve malicious app updates
- Downgrade HTTPS to HTTP for model/update downloads

**Mitigations:**
- ✅ HTTPS-only downloads (enforced in URLSession)
- ✅ Code signature verification for updates (PR #127)
- ✅ SHA-256 checksum verification for models (PR #131)
- ✅ Content-type and size validation
- ❌ **Gap**: Model checksums not yet verified (planned)

### 2. Malicious App on User's Mac (Local)
**Capability**: Run arbitrary code in user context
**Motivation**: Exfiltrate transcriptions, capture microphone, impersonate app
**Access**: User installed malware or compromised app

**Threats:**
- Read log files containing transcriptions
- Monitor clipboard for dictated text
- Impersonate app to steal accessibility permissions
- Inject malicious code into app bundle

**Mitigations:**
- ✅ App bundle code-signed (prevents tampering detection)
- ✅ Crash reports redact sensitive data (PR #131)
- ✅ Log files in user Library (standard macOS sandboxing)
- ⚠️ **Partial**: Clipboard exposure window limited to 0.5s
- ❌ **Gap**: App not notarized (requires Apple Developer Program)
- ❌ **Gap**: Logs not encrypted at rest

**Risk Acceptance:**
- If user's Mac is compromised, attacker has same privileges as app
- Full filesystem access means log files are accessible to malware
- Clipboard monitoring is inherent macOS limitation
- Mitigating malware is OS responsibility, not app responsibility

### 3. Compromised Dependency (Supply Chain)
**Capability**: Inject malicious code via WhisperKit or transitive dependencies
**Motivation**: Distribute malware to all users of the app
**Access**: Compromise upstream Swift package

**Threats:**
- Malicious code in WhisperKit dependency
- Backdoor in transitive dependencies (swift-transformers, etc.)
- Dependency substitution attack during build

**Mitigations:**
- ✅ WhisperKit pinned to exact Git SHA (not version range)
- ✅ Package.resolved integrity verified in CI (PR #131)
- ✅ Dependabot monitors for known vulnerabilities
- ✅ **NEW**: OSV-Scanner checks dependencies for CVEs
- ❌ **Gap**: No SBOM verification for reproducible builds

### 4. Malicious Ollama Instance (If Used)
**Capability**: Run arbitrary code on localhost:11434
**Motivation**: Intercept meeting transcripts, inject malicious prompts
**Access**: User-installed Ollama (optional dependency)

**Threats:**
- Capture meeting transcripts sent to Ollama
- Return malicious structured notes (XSS, injection attacks)
- DoS via slow/hanging responses

**Mitigations:**
- ✅ Ollama is optional (app works without it)
- ✅ Localhost-only communication (no remote Ollama servers)
- ✅ User controls Ollama installation (not bundled)
- ⚠️ **Partial**: JSON parsing validates structure but not content
- ❌ **Gap**: No input sanitization of Ollama responses

**Risk Acceptance:**
- If user's localhost Ollama is compromised, attacker controls analysis
- User is responsible for Ollama security (not app's threat model)
- App does not rely on Ollama for core functionality

### 5. Physical Attacker (Local Access)
**Capability**: Physical access to unlocked Mac
**Motivation**: Steal transcription data, install keylogger
**Access**: Direct keyboard/mouse/display access

**Threats:**
- Read log files from filesystem
- Modify app settings (e.g., disable security checks)
- Observe dictation in real-time
- Install malicious app version

**Mitigations:**
- ⚠️ **Partial**: macOS FileVault encryption (user responsibility)
- ⚠️ **Partial**: macOS Gatekeeper prevents unsigned app installation
- ❌ **Gap**: No app-level encryption of logs

**Risk Acceptance:**
- Physical access = full compromise (industry standard assumption)
- macOS system security is defense (screen lock, FileVault)
- App cannot protect against physical attacker with unlocked Mac

## Attack Scenarios

### Scenario 1: Supply Chain Attack via Model Download
**Attacker**: Network adversary
**Attack Path**:
1. Attacker compromises HuggingFace CDN or performs MITM
2. User downloads Whisper model (e.g., "base" model ~150MB)
3. Attacker serves malicious model file with embedded exploit
4. App loads malicious model, triggering vulnerability in WhisperKit

**Impact**: Remote code execution in app context (microphone + accessibility access)

**Likelihood**: Low (HTTPS + CDN security)

**Current Mitigations**:
- HTTPS-enforced downloads
- Content-type validation (application/octet-stream)
- Size range validation (models between 50MB-2GB)

**Residual Risk**: Model file integrity not cryptographically verified

**Recommendation**:
- **Priority: HIGH** - Add SHA-256 checksum verification for downloaded models
- Implement in WhisperService.swift download handler
- Store known-good checksums in app or fetch from trusted source

### Scenario 2: Malicious Update Installation
**Attacker**: Network adversary
**Attack Path**:
1. Attacker compromises GitHub releases or performs MITM
2. User checks for updates via UpdateService
3. Attacker serves malicious DMG signed with stolen/fake certificate
4. App downloads and attempts to install malicious update

**Impact**: Full system compromise (app has accessibility + microphone permissions)

**Likelihood**: Very Low (GitHub security + signature verification)

**Current Mitigations**:
- ✅ HTTPS-only downloads
- ✅ DMG size limit (500MB)
- ✅ Code signature verification before installation
- ✅ Content-type validation

**Residual Risk**: Ad-hoc signatures accepted (production should verify specific Developer ID)

**Recommendation**:
- **Priority: MEDIUM** - Notarize releases via Apple Developer Program
- Verify specific Developer ID (not just any valid signature)
- Tracked in issue #124

### Scenario 3: Accessibility API Abuse
**Attacker**: Malicious app on user's Mac
**Attack Path**:
1. User grants Look Ma No Hands accessibility permissions
2. Malicious app monitors AXUIElement usage or impersonates app
3. Attacker reads text fields from password managers, browsers, etc.
4. Attacker exfiltrates sensitive data

**Impact**: Credential theft, data exfiltration

**Likelihood**: Medium (if user's Mac is compromised)

**Current Mitigations**:
- App only reads text fields when actively inserting transcription
- 200-character context limit reduces exposure
- User controls when recording happens (Caps Lock trigger)

**Residual Risk**: Any app with accessibility permissions can read all text fields

**Recommendation**:
- **Priority: LOW** - macOS system limitation, not app vulnerability
- Document risk in README/security docs
- Advise users to audit accessibility-granted apps in System Settings

### Scenario 4: Clipboard Leak
**Attacker**: Malicious app monitoring clipboard
**Attack Path**:
1. User dictates sensitive text (password, API key, personal info)
2. App temporarily copies transcription to clipboard (for paste simulation)
3. Malicious app reads clipboard during 0.5s exposure window
4. Attacker exfiltrates sensitive data

**Impact**: Credential/secret leakage

**Likelihood**: Low (requires fast polling + precise timing)

**Current Mitigations**:
- Clipboard content restored after 0.5s (line 246, TextInsertionService.swift)
- Only used when direct AXUIElement insertion fails

**Residual Risk**: 0.5s window is enough for fast clipboard monitors

**Recommendation**:
- **Priority: MEDIUM** - Reduce clipboard exposure window to 100ms
- Add user setting to disable clipboard fallback entirely
- Consider NSPasteboard.clearContents() before restoration (defense in depth)

### Scenario 5: Log File Data Leakage
**Attacker**: Malicious app or physical attacker
**Attack Path**:
1. User dictates sensitive information over multiple sessions
2. Logger writes unredacted data to ~/Library/Logs/LookMaNoHands/
3. Attacker reads log files from filesystem
4. Attacker extracts transcribed text, API keys, personal info

**Impact**: Privacy violation, potential credential leak

**Likelihood**: Medium (if Mac is compromised or unlocked)

**Current Mitigations**:
- Logs auto-delete after 7 days
- Standard macOS file permissions (user-only readable)
- Crash reports redact transcriptions

**Residual Risk**: Logs may contain transcription text or sensitive data

**Recommendation**:
- **Priority: LOW** - Logs are diagnostic tool, not permanent storage
- Document log location and retention in privacy policy
- Consider adding opt-in log encryption (FileVault is primary defense)

## Security Controls Summary

### Preventive Controls (Stop attacks before they happen)
- ✅ HTTPS-enforced downloads
- ✅ Code signature verification for updates
- ✅ Content-type and size validation
- ✅ Localhost-only Ollama communication
- ✅ Package.resolved integrity checks in CI
- ✅ Dependency pinning to exact Git SHA

### Detective Controls (Identify attacks in progress)
- ✅ CodeQL SAST scanning (force unwraps, unsafe casts)
- ✅ Gitleaks secret scanning
- ✅ Dependabot vulnerability alerts
- ✅ OSV-Scanner dependency CVE checks

### Corrective Controls (Recover from attacks)
- ✅ Log rotation (7-day cleanup)
- ✅ Graceful shutdown on redeploy (prevents data loss)
- ⚠️ Partial: Crash reports (redacted but not encrypted)

### Compensating Controls (Reduce impact when primary controls fail)
- ✅ Clipboard restoration after 0.5s
- ✅ 200-character context limit for text field reads
- ⚠️ Partial: User must grant permissions (macOS Gatekeeper)

## Residual Risks (Accepted)

### High Confidence Acceptance
1. **Compromised macOS installation** - If OS is malicious, app cannot defend itself
2. **Physical access with unlocked Mac** - Industry standard: physical access = full compromise
3. **User-installed malware** - App cannot prevent user from installing other malicious apps
4. **Clipboard monitoring** - macOS system limitation, no app-level mitigation exists

### Medium Confidence Acceptance
1. **Unencrypted log files** - FileVault is primary defense; app-level encryption adds complexity
2. **Ad-hoc code signatures** - Acceptable for free/open-source distribution; notarization requires paid developer account

### Requires Mitigation
1. **Model download integrity** - HIGH PRIORITY - Add SHA-256 verification
2. **Clipboard exposure window** - MEDIUM PRIORITY - Reduce to 100ms or add disable option
3. **Force unwrapping in critical paths** - MEDIUM PRIORITY - CodeQL will flag, requires code refactoring

## Recommendations Priority Matrix

| Priority | Recommendation | Effort | Impact | Timeline |
|----------|---------------|--------|--------|----------|
| **HIGH** | Add SHA-256 verification for Whisper model downloads | Medium | High | Next release |
| **MEDIUM** | Reduce clipboard exposure window to 100ms | Low | Medium | Next release |
| **MEDIUM** | Refactor force unwraps flagged by CodeQL | Medium | Medium | 3 months |
| **MEDIUM** | Notarize releases (requires Apple Developer Program) | High | Medium | 6 months |
| **LOW** | Add opt-in log encryption | High | Low | Future |
| **LOW** | Document accessibility API risks in README | Low | Low | Next release |

## Review Schedule
- **Quarterly**: Review threat model for new attack vectors
- **On architecture changes**: Update trust boundaries and attack surface
- **Post-incident**: Update based on security findings
- **Annual**: Full threat model refresh with external security review

## References
- OWASP Threat Modeling Cheat Sheet: https://cheats.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html
- STRIDE Threat Modeling: https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats
- Apple Platform Security Guide: https://support.apple.com/guide/security/welcome/web
```

### Verification Plan
1. Review threat model with project maintainer
2. Validate attack scenarios against codebase
3. Cross-reference mitigations with docs/SECURITY.md
4. Create GitHub issues for HIGH/MEDIUM priority recommendations
5. Link threat model from README.md security section

### Success Criteria
- [ ] Threat model document exists with STRIDE analysis
- [ ] All 5 threat actors documented with mitigations
- [ ] Attack scenarios include likelihood/impact assessment
- [ ] Residual risks explicitly accepted or mitigated
- [ ] Priority matrix created for security recommendations
- [ ] Quarterly review process established

---

## Timeline

### Immediate (Within 1 Month)
- [ ] Create PR security checklist template
- [ ] Document security-sensitive code areas
- [ ] Update PR template to link security checklist

### Short-term (1-3 Months)
- [ ] Conduct threat modeling workshop (async via GitHub Discussions)
- [ ] Draft THREAT-MODEL.md document
- [ ] Review and refine threat model with maintainers
- [ ] Publish threat model to docs/

### Medium-term (3-6 Months)
- [ ] Validate security checklist with 5+ PR reviews
- [ ] Refine checklist based on reviewer feedback
- [ ] Create GitHub issues for HIGH priority threat model recommendations
- [ ] Begin implementing top security recommendations

### Long-term (6-12 Months)
- [ ] Quarterly threat model review
- [ ] Track metrics: # PRs using security checklist, # security issues found
- [ ] Update threat model based on new attack vectors or mitigations

---

## Success Metrics

### Security Checklist
- **Adoption**: >50% of PRs touching security-sensitive areas use checklist within 3 months
- **Effectiveness**: At least 2 security issues caught via checklist in first 6 months
- **Feedback**: Reviewers report checklist is helpful (survey after 10 uses)

### Threat Model
- **Completeness**: All 5 threat actors analyzed, all critical assets identified
- **Actionability**: At least 3 HIGH/MEDIUM priority recommendations tracked as GitHub issues
- **Maintenance**: Threat model reviewed quarterly, updated after major architecture changes

---

## Resources

### Threat Modeling Guides
- [OWASP Threat Modeling Cheat Sheet](https://cheats.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [Microsoft STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [Practical Threat Modeling for macOS Apps](https://www.youtube.com/watch?v=example) <!-- Placeholder -->

### Security Checklist Examples
- [Security Code Review Checklist](https://github.com/OWASP/wstg/blob/master/document/4-Web_Application_Security_Testing/07-Input_Validation_Testing/README.md)
- [iOS Security Testing Checklist](https://mas.owasp.org/checklists/MASVS-CODE/)

### macOS Security
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web)
- [macOS Hardening Guide](https://book.hacktricks.xyz/macos-hardening/macos-security-and-privilege-escalation)
