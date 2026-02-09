# Workstream 3: Runtime Security Fixes - Testing Guide

## Overview

This workstream addresses two runtime security issues:
- **CODE-007:** Fix screen recording permission check in SystemAudioRecorder
- **CODE-008:** Remove character count from crash report PII redaction

## Changes Made

### 1. SystemAudioRecorder.swift (Lines 42-46)
**Before:**
```swift
static func hasPermission() -> Bool {
    if #available(macOS 14.0, *) {
        return true // Permission check simplified in macOS 14+
    } else {
        return true
    }
}
```

**After:**
```swift
static func hasPermission() -> Bool {
    // Use CGPreflightScreenCaptureAccess to check actual permission state
    // This returns true if permission is already granted, false otherwise
    return CGPreflightScreenCaptureAccess()
}
```

**Impact:** The function now accurately reflects the actual permission state instead of always returning `true`.

### 2. CrashReporter.swift (Lines 157-162)
**Before:**
```swift
if let lastTranscription = state.lastTranscription {
    report += """
    Last Transcription: [REDACTED - \(lastTranscription.count) characters]

    """
}
```

**After:**
```swift
if state.lastTranscription != nil {
    report += """
    Last Transcription: [REDACTED]

    """
}
```

**Impact:** Character count removed to prevent potential information leakage (e.g., distinguishing "yes" from sensitive data).

## Build Verification

✅ **Compilation Status:** Both files compile successfully
✅ **Build Time:** 1.81s (debug build)
✅ **No Warnings:** Clean build with no compiler warnings

## Testing Instructions

### Test 1: Screen Recording Permission Check (CODE-007)

#### Test 1.1: Fresh Install Behavior
```bash
# Prerequisites: Test on a clean user account or VM where app hasn't been run

1. Build and deploy the app:
   cd /Users/qaid/Code/look-ma-no-hands-ai-security-workstream-3
   ./deploy.sh

2. Launch the app (do NOT grant screen recording permission yet)

3. Try to start Meeting Mode

Expected Result:
- SystemAudioRecorder.hasPermission() should return false
- App should prompt user to grant Screen Recording permission
- Meeting mode should not start until permission granted
```

#### Test 1.2: Permission Grant Flow
```bash
1. With app running, go to:
   System Settings > Privacy & Security > Screen Recording

2. Enable permission for "LookMaNoHands"

3. Return to app and try Meeting Mode again

Expected Result:
- SystemAudioRecorder.hasPermission() should now return true
- Meeting mode should start successfully
- System audio capture should work
```

#### Test 1.3: Permission Revoke Flow
```bash
1. With Meeting Mode working, revoke permission:
   System Settings > Privacy & Security > Screen Recording
   Disable "LookMaNoHands"

2. Try to start Meeting Mode

Expected Result:
- SystemAudioRecorder.hasPermission() should return false
- App should detect permission loss
- Should prompt user to re-grant permission
```

#### Test 1.4: Integration Test
```bash
# Verify the fix integrates correctly with meeting mode

1. Start with NO screen recording permission
2. Click "Start Meeting" button
3. App should show permission prompt/guide
4. Grant permission in System Settings
5. Retry "Start Meeting"
6. Meeting should start successfully

Expected Result:
- Clear feedback about permission status
- No false positives (claiming permission when not granted)
- Meeting mode works after permission granted
```

### Test 2: Crash Report Privacy (CODE-008)

#### Test 2.1: Crash Report Format Verification
```bash
# Add temporary crash trigger for testing

1. Add debug crash button (if not already present):
   In SettingsView.swift or appropriate view, add:

   #if DEBUG
   Button("Test Crash Report") {
       fatalError("Test crash for CODE-008 verification")
   }
   #endif

2. Perform a transcription to populate lastTranscription:
   - Press trigger key (Caps Lock)
   - Say something (e.g., "This is a test transcription")
   - Verify text was transcribed

3. Trigger test crash

4. Check crash log:
   cat ~/Library/Logs/LookMaNoHands/crashes/*.txt

Expected Result:
- Should show: "Last Transcription: [REDACTED]"
- Should NOT show: "Last Transcription: [REDACTED - 29 characters]"
- No character count should be present
```

#### Test 2.2: No Transcription Case
```bash
1. Launch fresh app (no transcriptions yet)
2. Trigger test crash immediately
3. Check crash log

Expected Result:
- Should NOT include "Last Transcription" line at all
- No reference to transcription in crash report
```

#### Test 2.3: Sensitive Content Test
```bash
1. Perform transcription with varying content lengths:
   - Short: "Yes"
   - Medium: "My email is user@example.com"
   - Long: Full sentence with sensitive data

2. Trigger crash after each transcription
3. Verify ALL crash logs show identical redaction

Expected Result:
- All crash reports show: "Last Transcription: [REDACTED]"
- No way to distinguish content length from crash reports
- Complete PII protection
```

#### Test 2.4: Real Crash Scenario
```bash
# Verify privacy in actual crash situations

1. If app crashes naturally during testing
2. Check crash logs at ~/Library/Logs/LookMaNoHands/crashes/
3. Verify transcription redaction is complete

Expected Result:
- Real crashes also respect privacy
- No character count leakage
- Crash report still contains useful debugging info
```

## Automated Testing

### Unit Test Ideas (Optional)

```swift
// Tests for SystemAudioRecorder

func testHasPermissionReturnsBool() {
    let result = SystemAudioRecorder.hasPermission()
    XCTAssert(result is Bool, "Should return boolean value")
}

func testHasPermissionCallsCGPreflightScreenCaptureAccess() {
    // This test verifies the fix uses the correct API
    // Expected: Function calls CGPreflightScreenCaptureAccess()
    // Note: Hard to unit test without mocking, best tested manually
}

// Tests for CrashReporter

func testCrashReportRedactsWithoutCharacterCount() {
    var state = TranscriptionState()
    state.lastTranscription = "Sensitive data here"

    let report = CrashReporter.generateReport(state: state)

    XCTAssertTrue(report.contains("[REDACTED]"), "Should contain redacted marker")
    XCTAssertFalse(report.contains("characters"), "Should not include character count")
    XCTAssertFalse(report.contains("19 characters"), "Should not include specific count")
}

func testCrashReportWithNoTranscription() {
    let state = TranscriptionState()
    // lastTranscription is nil

    let report = CrashReporter.generateReport(state: state)

    XCTAssertFalse(report.contains("Last Transcription"), "Should not mention transcription if none exists")
}
```

## Success Criteria

### CODE-007: Screen Recording Permission Check
- ✅ `hasPermission()` returns `false` on fresh install (before permission granted)
- ✅ `hasPermission()` returns `true` after permission granted
- ✅ `hasPermission()` returns `false` after permission revoked
- ✅ Meeting mode properly detects and responds to permission state
- ✅ No false positives (claiming permission when not granted)
- ✅ Build compiles without errors or warnings

### CODE-008: Crash Report Privacy
- ✅ Crash reports show `[REDACTED]` for transcriptions
- ✅ No character count included in redaction
- ✅ Cannot distinguish content length from crash reports
- ✅ Crash reports without transcription don't mention it
- ✅ Crash reports still contain useful debugging information
- ✅ Build compiles without errors or warnings

## Known Limitations

1. **Permission Testing:** Requires clean user account or VM for fresh install testing
2. **Crash Testing:** Requires manual triggering or waiting for natural crashes
3. **System Integration:** Permission behavior depends on macOS version (13+)

## Regression Risks

### Low Risk
- **SystemAudioRecorder:** Only affects permission checking logic, not audio capture itself
- **CrashReporter:** Only affects crash report format, not crash detection or logging

### What to Watch For
1. Meeting mode failing to start due to incorrect permission detection
2. Permission prompts appearing when permission already granted
3. Crash reports missing important debugging information

## Related Files

- [Sources/LookMaNoHands/Services/SystemAudioRecorder.swift](../Sources/LookMaNoHands/Services/SystemAudioRecorder.swift#L42-L46)
- [Sources/LookMaNoHands/Services/CrashReporter.swift](../Sources/LookMaNoHands/Services/CrashReporter.swift#L157-L162)

## Integration with Other Workstreams

- **No conflicts** with Workstreams 1, 2, 4, or 5
- Can be merged independently
- No file overlap with other security workstreams

## Next Steps After Testing

1. ✅ Verify all tests pass
2. ✅ Build succeeds in both debug and release mode
3. ✅ Create commit with changes
4. ✅ Create PR to merge into main branch
5. ✅ Reference issue #125 in PR description

## Notes

- Build time: ~2 seconds (incremental), ~70 seconds (clean build)
- No new dependencies added
- No API changes (internal fixes only)
- Backward compatible with existing functionality
