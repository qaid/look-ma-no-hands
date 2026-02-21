---
name: test-runner
description: Run Swift tests, filter by class, and report results
model: haiku
triggers:
  - run tests
  - swift test
  - check tests
  - failing tests
  - test coverage
  - run the test suite
  - which tests are failing
invocation_patterns:
  - "When user asks to run tests or check test status"
  - "When user wants to see which tests are failing"
  - "When user asks for test coverage"
  - "When user references a specific test class or test file"
---

# Run All Tests

Run the full test suite.

## Instructions

```bash
swift test 2>&1
```

Report pass/fail counts and list any failures with their error messages.

# Run Tests With Coverage

Run tests and generate a coverage report.

## Instructions

```bash
swift test --enable-code-coverage 2>&1
```

After the run, find and summarize coverage:

```bash
BINARY=$(swift build --show-bin-path 2>/dev/null)/LookMaNoHandsPackageTests.xctest/Contents/MacOS/LookMaNoHandsPackageTests
PROFDATA=$(find .build -name '*.profdata' | head -1)
if [ -n "$PROFDATA" ] && [ -f "$BINARY" ]; then
  xcrun llvm-cov report "$BINARY" --instr-profile="$PROFDATA" --ignore-filename-regex='.build|Tests'
fi
```

# Run a Specific Test Class

Run only one test class by name.

## Instructions

Replace `<ClassName>` with the class to run (e.g. `MeetingStoreTests`):

```bash
swift test --filter <ClassName> 2>&1
```

Available test classes (see `docs/test-inventory.md`):
- `CrashReporterTests`
- `HotkeyTests`
- `MeetingRecordTests`
- `MeetingStoreTests`
- `MeetingTypeTests`
- `OperationWatchdogTests`
- `SettingsTests`
- `TextFormatterTests`
- `ViewStateTests`
- `WhisperDictationTests`

# Run a Specific Test Method

Run a single test method.

## Instructions

```bash
swift test --filter <ClassName>/<methodName> 2>&1
```

Example: `swift test --filter MeetingStoreTests/testRetentionPolicyRemovesOldAndExcessMeetings`
