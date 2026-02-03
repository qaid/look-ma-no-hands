---
name: security-review
description: Comprehensive security audit and vulnerability analysis
model: sonnet
triggers:
  - security review
  - security audit
  - vulnerability scan
  - security analysis
  - check security
  - security vulnerabilities
  - privacy review
  - security issues
invocation_patterns:
  - "When user requests a security audit or security review"
  - "When user asks about vulnerabilities, privacy concerns, or security issues"
  - "When user wants to check for security best practices"
  - "When user mentions OWASP, CVE, or security standards"
  - "When user asks about data handling, permissions, or sensitive information"
---

# Security Review

Perform a comprehensive security audit of Look Ma No Hands.

This agent analyzes the codebase for vulnerabilities specific to macOS apps handling sensitive permissions (Accessibility, Microphone) and local audio/text processing.

## Instructions

Conduct a thorough security review covering all categories below. For each finding, provide:
- **Severity**: Critical / High / Medium / Low / Informational
- **Location**: File path and line number
- **Description**: What the vulnerability is
- **Recommendation**: How to fix it

### 1. Privacy & Data Handling

This app processes voice audio and transcribed text. Check for:

- [ ] Audio data is processed in memory only, never written to disk unencrypted
- [ ] Transcribed text is not logged or persisted beyond immediate use
- [ ] No telemetry, analytics, or network calls that could leak user data
- [ ] Temporary files (if any) are securely deleted after use
- [ ] No hardcoded API keys, tokens, or credentials

### 2. Accessibility API Security

The app uses Accessibility APIs for keyboard monitoring and text insertion:

- [ ] Minimal scope of accessibility permissions requested
- [ ] No unnecessary system-wide event monitoring
- [ ] Text insertion targets only the intended input field
- [ ] No logging of keystrokes or input from other applications
- [ ] Proper cleanup of event taps and observers

### 3. Microphone & Audio Security

- [ ] Microphone access is only active during explicit recording
- [ ] Audio buffers are cleared after transcription completes
- [ ] No audio data transmitted over network
- [ ] Recording indicator accurately reflects microphone state
- [ ] Proper handling of microphone permission denial

### 4. macOS Platform Security

- [ ] App Sandbox considerations (currently unsigned, but review for future)
- [ ] Hardened Runtime compatibility
- [ ] Proper entitlements for required permissions only
- [ ] No shell command execution with user-controlled input
- [ ] Secure handling of file paths (no path traversal)

### 5. Input Validation & Injection

- [ ] Transcribed text is sanitized before insertion
- [ ] No command injection via text formatting
- [ ] Safe string handling (no buffer overflows, proper bounds checking)
- [ ] Unicode and special character handling

### 6. Dependency Security

Review SwiftWhisper and whisper.cpp dependencies:

- [ ] Check for known CVEs in dependencies
- [ ] Verify dependency integrity (package checksums)
- [ ] Review what system access dependencies require
- [ ] Ensure dependencies are from trusted sources

### 7. Memory Safety

Swift provides memory safety, but check for:

- [ ] Proper use of `Unsafe*` APIs if any
- [ ] No force unwrapping that could cause crashes with malicious input
- [ ] Secure clearing of sensitive data from memory
- [ ] No retain cycles that could leak sensitive data

### 8. Code Quality & Logic Flaws

- [ ] Race conditions in async audio/transcription pipeline
- [ ] Proper error handling that doesn't expose sensitive info
- [ ] No debug code or verbose logging in production
- [ ] State machine integrity (recording states)

## Output Format

After analysis, provide:

1. **Executive Summary**: Overall security posture (Good/Needs Attention/Concerning)
2. **Findings Table**: All issues sorted by severity
3. **Positive Observations**: Security measures already in place
4. **Recommendations**: Prioritized list of improvements

## Focus Areas for This App

Given this is a voice dictation app with system-wide keyboard hooks:

1. **Highest Priority**: Ensure no audio or keystroke data leaks
2. **High Priority**: Verify accessibility APIs are used minimally and correctly
3. **Medium Priority**: Review text insertion for injection risks
4. **Lower Priority**: Future-proof for App Store sandboxing requirements

## References

- [OWASP Mobile Application Security](https://mas.owasp.org/)
- [Apple Platform Security Guide](https://support.apple.com/guide/security/)
- [Swift Security Best Practices](https://www.preemptive.com/blog/security-checklist-for-swift-and-objective-c-developers/)
