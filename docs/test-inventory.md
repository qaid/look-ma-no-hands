# Test Inventory

This document summarizes the automated tests intended for CI/PR review workflows.

## How To Run

- `swift test`

## XCTest Suites And Files

- `Tests/LookMaNoHandsTests/CrashReporterTests.swift`
  - Crash report redaction and saved state round-trip.
- `Tests/LookMaNoHandsTests/HotkeyTests.swift`
  - Hotkey formatting, modifier flags, reserved keys, and predefined trigger checks.
- `Tests/LookMaNoHandsTests/MeetingRecordTests.swift`
  - MeetingRecord encoding/decoding and default values.
- `Tests/LookMaNoHandsTests/MeetingStoreTests.swift`
  - MeetingStore sorting, retention, pruning, and missing file behavior.
- `Tests/LookMaNoHandsTests/MeetingTypeTests.swift`
  - MeetingType display metadata and default prompt selection.
- `Tests/LookMaNoHandsTests/OperationWatchdogTests.swift`
  - Watchdog start/complete, timeout firing, and async timeout helper.
- `Tests/LookMaNoHandsTests/SettingsTests.swift`
  - TriggerKey mapping, Whisper model display names, and defaults reset.
- `Tests/LookMaNoHandsTests/TextFormatterTests.swift`
  - Common error corrections and vocabulary replacement behavior.
- `Tests/LookMaNoHandsTests/ViewStateTests.swift`
  - Accessibility strings and SettingsView model list behavior.
- `Tests/LookMaNoHandsTests/WhisperDictationTests.swift`
  - TranscriptionState transitions and Settings defaults.

## Notes For CI

- These tests are designed to run headless via `swift test` with no UI automation.
- Filesystem-based tests use temporary directories and should not rely on user data.
