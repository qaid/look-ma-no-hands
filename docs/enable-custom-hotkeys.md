# Custom Hotkey Support Implementation Plan

## Overview

Add Raycast-style custom hotkey recording to Look Ma No Hands, allowing users to configure any key or key combination as their dictation trigger.

## Current State

- `KeyboardMonitor.swift` uses CGEvent APIs but only detects Caps Lock (keycode 57)
- `Settings.swift` has a `TriggerKey` enum with 3 predefined options that don't actually affect monitoring
- Menu bar shows hardcoded "Caps Lock" text

## Implementation

### 1. Create Hotkey Data Model

**New file:** `Sources/LookMaNoHands/Models/Hotkey.swift`

- `Hotkey` struct with `keyCode: UInt16` and `modifiers: ModifierFlags`
- `ModifierFlags` nested struct (command, shift, option, control booleans)
- Codable for UserDefaults persistence
- `displayString` computed property (e.g., "Cmd+Shift+R")
- `cgEventFlags` conversion for event matching
- Static presets: `.capsLock`, `.rightOption`, `.fn`
- Key code to string mapping dictionary

### 2. Update Settings.swift

- Add `customHotkey: Hotkey?` published property with UserDefaults persistence
- Add `"customHotkey"` to Keys enum
- Add `.custom` case to `TriggerKey` enum
- Add `effectiveHotkey: Hotkey` computed property that returns the active hotkey
- Add `toHotkey()` method on TriggerKey to convert enum to Hotkey

### 3. Create HotkeyRecorderView

**New file:** `Sources/LookMaNoHands/Views/HotkeyRecorderView.swift`

UI Component (Raycast-style):
- Displays current hotkey as styled key caps
- Click to enter recording mode ("Press hotkey...")
- Uses `NSEvent.addLocalMonitorForEvents` for key capture
- Escape cancels recording
- Click outside cancels recording
- Visual states: idle (gray border), recording (blue border), invalid (red border)

Validation:
- **2-3 Keypress Rule**: Custom hotkeys must use 2-3 keypresses total
  - Valid: 1 modifier + 1 key (Cmd+D) or 2 modifiers + 1 key (Cmd+Shift+D)
  - Invalid: Single keys (A), single modifiers (Caps Lock), or 3+ modifiers
  - Predefined triggers (Caps Lock, Fn, Right Option) are exempt from this rule
- Block system-reserved shortcuts (Cmd+Q, Cmd+W, Cmd+Tab, Cmd+Space, etc.)
- Require modifier for non-modifier keys (prevent accidental "A" as hotkey)
- Show error message briefly before returning to recording state

### 4. Update KeyboardMonitor.swift

- Add `hotkey: Hotkey` property with thread-safe getter/setter
- Add `setHotkey(_ newHotkey: Hotkey)` method for runtime updates
- Update `startMonitoring()` to accept a `Hotkey` parameter
- Modify event mask: monitor both `flagsChanged` AND `keyDown` events
- Update `handleEvent()`:
  - For single modifier keys (Caps Lock): check keycode on flagsChanged
  - For key+modifier combos: check keycode AND modifier flags on keyDown
  - Use `CGEventFlags` intersection to match only relevant modifiers

### 5. Update SettingsView.swift Recording Tab

- Change trigger key picker to use updated TriggerKey enum
- Add conditional `HotkeyRecorderView` when `.custom` is selected
- Add `onChange` handlers to post `hotkeyConfigurationChanged` notification
- Add `Notification.Name.hotkeyConfigurationChanged` extension

### 6. Update AppDelegate.swift

- Modify `setupKeyboardMonitoring()` to use `Settings.shared.effectiveHotkey`
- Add observer for `hotkeyConfigurationChanged` notification
- Add `hotkeyConfigurationDidChange()` handler that calls `keyboardMonitor.setHotkey()`
- Update menu item text dynamically based on `effectiveHotkey.displayString`

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/LookMaNoHands/Models/Hotkey.swift` | **NEW** - Data model |
| `Sources/LookMaNoHands/Models/Settings.swift` | Add customHotkey, effectiveHotkey |
| `Sources/LookMaNoHands/Views/HotkeyRecorderView.swift` | **NEW** - UI component |
| `Sources/LookMaNoHands/Views/SettingsView.swift` | Integrate recorder |
| `Sources/LookMaNoHands/Services/KeyboardMonitor.swift` | Dynamic hotkey support |
| `Sources/LookMaNoHands/App/AppDelegate.swift` | Wire up notifications |

## Verification

1. Build: `./deploy.sh`
2. Open Settings > Recording tab
3. Test predefined options (Caps Lock, Right Option, Fn)
4. Select "Custom..." and record a hotkey (e.g., Cmd+Shift+D)
5. Verify the custom hotkey triggers recording
6. Verify menu bar shows correct hotkey name
7. Quit and relaunch - verify setting persists
8. Test validation: try reserved shortcuts (Cmd+Q), verify rejection
9. Test cancel: press Escape during recording, verify it cancels
