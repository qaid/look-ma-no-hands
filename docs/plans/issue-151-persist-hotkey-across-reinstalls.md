# Issue #151: Persist Toggle Hotkey Shortcut Across App Reinstalls

## Overview

This plan addresses the issue where users' custom toggle hotkey shortcuts (default: Cmd+Shift+D) are lost when the app is reinstalled. Currently, the hotkey is stored in UserDefaults, which clears on reinstall. The solution is to migrate to file-based storage in Application Support, following the proven pattern already established by the `customVocabulary` feature.

**Status:** Ready to implement
**Complexity:** Low (single file, follows existing pattern)
**Files Modified:** 1 (`Settings.swift`)
**Dependencies:** None

---

## Problem Analysis

### Current Behavior
- Users customize their toggle hotkey (e.g., from Cmd+Shift+D to Cmd+Option+D)
- They uninstall or reinstall the app
- The toggle shortcut reverts to the default (Cmd+Shift+D)
- Custom vocabulary persists correctly (serves as reference pattern)

### Root Cause
- **Location:** `Sources/LookMaNoHands/Models/Settings.swift` (lines 396-407, 504-509)
- **Storage:** `UserDefaults.standard` (key: `toggleHotkeyShortcut`)
- **Problem:** UserDefaults are cleared on app reinstall
- **Reference:** `customVocabulary` uses file-based storage in Application Support and persists correctly

### Why This Matters
- **Consistency:** Users expect their preferences to survive reinstalls, like vocabulary does
- **User Experience:** Reconfiguring after each reinstall is frustrating
- **Data Persistence:** All user preferences should survive app deletion

---

## Solution Architecture

### Design Pattern
Follow the exact pattern established by `customVocabulary`:

1. **File Storage:** Store hotkey in `~/Library/Application Support/LookMaNoHands/toggleHotkey.json`
2. **Auto-Save:** Property `didSet` automatically saves to file
3. **Migration:** Load from UserDefaults on first launch (backward compatibility)
4. **Cleanup:** Remove old UserDefaults key after migration
5. **Logging:** Use consistent emoji-prefixed NSLog patterns

### Reference Implementation
```
customVocabulary pattern:
├── File path: vocabularyFileURL (lines 273-275)
├── Load: loadVocabularyFromFile() (lines 525-559) + UserDefaults migration
├── Save: saveVocabularyToFile() (lines 562-572)
├── Property: @Published var customVocabulary with didSet (lines 367-371)
└── Logging: Emoji prefixes (📚, 🔄, ✅, ❌)

toggleHotkeyShortcut target:
├── File path: toggleHotkeyFileURL (NEW)
├── Load: loadToggleHotkeyFromFile() (NEW) + UserDefaults migration
├── Save: saveToggleHotkeyToFile() (NEW)
├── Property: @Published var toggleHotkeyShortcut (MODIFY)
└── Logging: Emoji prefix (🔧)
```

---

## Implementation Plan

### Step 1: Add File Path Property
**Location:** After `vocabularyFileURL` (after line 275)

```swift
/// Path to the toggle hotkey JSON file in Application Support
private static var toggleHotkeyFileURL: URL {
    getApplicationSupportDirectory().appendingPathComponent("toggleHotkey.json")
}
```

**Rationale:** Separate file keeps concerns isolated; easier to debug and maintain.

---

### Step 2: Create Load Method
**Location:** After `loadVocabularyFromFile()` method (after line 559)

```swift
/// Load toggle hotkey from Application Support directory
/// Migrates from UserDefaults if file doesn't exist yet
private static func loadToggleHotkeyFromFile() -> Hotkey? {
    let fileURL = toggleHotkeyFileURL

    // Try loading from file first
    if FileManager.default.fileExists(atPath: fileURL.path) {
        do {
            let data = try Data(contentsOf: fileURL)
            let hotkey = try JSONDecoder().decode(Hotkey.self, from: data)
            NSLog("🔧 Loaded toggle hotkey from \(fileURL.path)")
            return hotkey
        } catch {
            NSLog("⚠️ Failed to load toggle hotkey from file: \(error.localizedDescription)")
        }
    }

    // Migration: Check UserDefaults for legacy data
    if let hotkeyData = UserDefaults.standard.data(forKey: Keys.toggleHotkeyShortcut),
       let hotkey = try? JSONDecoder().decode(Hotkey.self, from: hotkeyData) {
        NSLog("🔄 Migrating toggle hotkey from UserDefaults to file")

        // Save to file
        if let data = try? JSONEncoder().encode(hotkey) {
            try? data.write(to: fileURL, options: .atomic)
            NSLog("✅ Migration complete: toggle hotkey saved to \(fileURL.path)")
        }

        // Remove from UserDefaults after successful migration
        UserDefaults.standard.removeObject(forKey: Keys.toggleHotkeyShortcut)

        return hotkey
    }

    NSLog("🔧 No existing toggle hotkey found, will use default")
    return nil
}
```

**Key Features:**
- Tries file first (primary storage)
- Falls back to UserDefaults with automatic migration
- Removes old UserDefaults key to prevent confusion
- Logs all operations with emoji prefixes for debugging
- Returns `nil` if nothing found (caller handles default)

---

### Step 3: Create Save Method
**Location:** After `saveVocabularyToFile()` method (after line 572)

```swift
/// Save toggle hotkey to Application Support directory
private func saveToggleHotkeyToFile() {
    let fileURL = Self.toggleHotkeyFileURL

    if let hotkey = toggleHotkeyShortcut {
        do {
            let data = try JSONEncoder().encode(hotkey)
            try data.write(to: fileURL, options: .atomic)
            NSLog("🔧 Saved toggle hotkey to \(fileURL.path)")
        } catch {
            NSLog("❌ Failed to save toggle hotkey to file: \(error.localizedDescription)")
        }
    } else {
        // Remove file if hotkey is nil (cleanup)
        try? FileManager.default.removeItem(at: fileURL)
        NSLog("🔧 Removed toggle hotkey file")
    }
}
```

**Key Features:**
- Encodes hotkey as JSON and writes atomically (safe from corruption)
- Handles `nil` case by removing file
- Logs all operations
- Matches pattern used by `saveVocabularyToFile()`

---

### Step 4: Update @Published Property
**Location:** Lines 396-407 (the `toggleHotkeyShortcut` didSet block)

**Replace existing code:**
```swift
@Published var toggleHotkeyShortcut: Hotkey? {
    didSet {
        saveToggleHotkeyToFile()
        NotificationCenter.default.post(name: .toggleShortcutChanged, object: nil)
    }
}
```

**What Changed:**
- Removed UserDefaults save/remove logic (lines 398-404)
- Added `saveToggleHotkeyToFile()` call
- Kept notification post (no change)

**Why:**
- Cleaner code: single responsibility (file storage)
- Consistent with `customVocabulary` pattern
- UserDefaults access now only in `loadToggleHotkeyFromFile()` for backward compatibility

---

### Step 5: Update Initialization
**Location:** Lines 503-509 (init method)

**Replace existing code:**
```swift
// Toggle shortcut defaults to Cmd+Shift+D (keyCode 2 = D)
self.toggleHotkeyShortcut = Self.loadToggleHotkeyFromFile()

if let hotkey = self.toggleHotkeyShortcut {
    NSLog("🔧 Settings: Loaded toggle hotkey from file")
} else {
    NSLog("🔧 Settings: No saved toggle hotkey - defaulting to Cmd+Shift+D")
    self.toggleHotkeyShortcut = Hotkey(keyCode: 2, modifiers: .init(command: true, shift: true))
}
```

**What Changed:**
- Load from file instead of UserDefaults
- Add logging to match onboarding pattern (lines 514-518)
- Set default `Cmd+Shift+D` if nothing found

**Behavior:**
1. First launch: No file, no UserDefaults → defaults to Cmd+Shift+D
2. Existing user: No file, UserDefaults has data → migrates to file, sets value
3. After migration: File exists → loads from file
4. After reinstall: File gone, UserDefaults cleared → defaults to Cmd+Shift+D (NEW - problem solved!)
5. After using new version then reinstalling: File persists → loads from file (FIXED!)

---

### Step 6: Verify resetToDefaults()
**Location:** Line 590 (no changes needed)

The existing code will work automatically:
```swift
toggleHotkeyShortcut = Hotkey(keyCode: 2, modifiers: .init(command: true, shift: true))
```

**Why it works:**
- Assignment triggers `didSet`
- `didSet` calls `saveToggleHotkeyToFile()`
- File is updated with default hotkey
- No additional changes needed

---

## Key Design Decisions

### 1. File Name: `toggleHotkey.json`
- Separate file from `vocabulary.json` (clear separation of concerns)
- Single hotkey as JSON object (simpler than array)
- Easy to debug: inspect file directly with `cat`

### 2. Emoji Logging: `🔧`
- Distinct from `📚` (vocabulary) and `📖` (onboarding)
- Consistent with existing codebase patterns
- Makes logs readable and searchable

### 3. Default Behavior
- Return `nil` from load if nothing found
- Let initialization code set `Cmd+Shift+D` default
- Ensures consistent initialization flow
- Easier to test (load method has no side effects)

### 4. Nil Handling
- When `toggleHotkeyShortcut = nil`, file is removed
- Matches `customHotkey` pattern (lines 292-302)
- Keeps filesystem clean
- Users can "reset" by setting to nil

### 5. Backward Compatibility
- Automatic UserDefaults → file migration on first launch
- Old UserDefaults key cleaned up after migration
- Zero user action required
- Users upgrading won't notice any difference

---

## Testing Strategy

### Test 1: Fresh Install (New User)
```
1. Delete app and ~/Library/Application Support/LookMaNoHands/
2. Install app
3. Verify default Cmd+Shift+D is used
4. Verify file ~/Library/Application Support/LookMaNoHands/toggleHotkey.json exists
```

### Test 2: Custom Hotkey Persists (Same Session)
```
1. Set custom hotkey (e.g., Cmd+Option+D)
2. Verify file contains the custom hotkey
3. Restart app
4. Verify custom hotkey is loaded and active
```

### Test 3: Reinstall Scenario (Key Test)
```
1. Set custom hotkey
2. Verify file exists and contains custom hotkey
3. Uninstall app (delete ~/Applications/LookMaNoHands.app)
4. Reinstall app
5. Verify custom hotkey persists!
6. Toggle hotkey should use custom setting (NOT default)
```

### Test 4: Migration from UserDefaults
```
1. Manually set UserDefaults for old version:
   defaults write com.lookmanohands.app toggleHotkeyShortcut <data>
2. Delete file (simulate old version)
3. Launch app
4. Verify app loads from UserDefaults
5. Verify file is created with value
6. Verify UserDefaults key is removed
7. Check logs show "🔄 Migrating toggle hotkey from UserDefaults to file"
```

### Test 5: Reset to Defaults
```
1. Set custom hotkey
2. Click "Reset to Defaults" in settings
3. Verify hotkey is set to Cmd+Shift+D
4. Verify file is updated with default value
5. Restart app
6. Verify default is still active
```

### Test 6: Null/None Handling
```
1. Programmatically set toggleHotkeyShortcut = nil
2. Verify file is removed (if it existed)
3. Verify no errors in logs
4. Restart app
5. Verify defaults to Cmd+Shift+D
```

### Test 7: File Corruption Resilience
```
1. Manually corrupt toggleHotkey.json (invalid JSON)
2. Launch app
3. Verify app handles error gracefully
4. Verify default is used (fallback behavior)
5. Verify error logged with ⚠️ prefix
```

---

## Implementation Checklist

- [ ] Add `toggleHotkeyFileURL` property (line 276)
- [ ] Add `loadToggleHotkeyFromFile()` method (after line 559)
- [ ] Add `saveToggleHotkeyToFile()` method (after line 572)
- [ ] Update `toggleHotkeyShortcut` property `didSet` (lines 396-407)
- [ ] Update initialization in `init()` (lines 503-509)
- [ ] Verify `resetToDefaults()` works (no changes needed)
- [ ] Compile and run locally
- [ ] Run all 7 tests above
- [ ] Check logs contain proper emoji prefixes
- [ ] Verify no errors or warnings
- [ ] Test with actual app usage (toggle hotkey works)

---

## Files Modified

| File | Lines | Changes |
|------|-------|---------|
| `Sources/LookMaNoHands/Models/Settings.swift` | 275-276 (new) | Add `toggleHotkeyFileURL` property |
| | 560-586 (new) | Add `loadToggleHotkeyFromFile()` method |
| | 574-591 (new) | Add `saveToggleHotkeyToFile()` method |
| | 396-407 (modify) | Update property `didSet` to use file storage |
| | 503-513 (modify) | Update initialization to load from file |

**Total: 1 file, ~60 lines of new/modified code**

---

## Success Criteria

✅ Users' custom toggle hotkeys persist across app reinstalls
✅ Backward compatibility: Existing UserDefaults data auto-migrates
✅ No breaking changes to public API
✅ Logging consistent with codebase patterns
✅ Follows established `customVocabulary` pattern
✅ All 7 tests pass
✅ No errors or warnings in logs

---

## Related Issues & Context

- **Similar Pattern:** `customVocabulary` (vocabulary.json) - implemented in same file
- **Reference Code:** `loadVocabularyFromFile()` (lines 525-559), `saveVocabularyToFile()` (lines 562-572)
- **GitHub Issue:** #151
- **Priority:** Medium (affects users with custom shortcuts)

---

## Notes for Implementation

1. **No Swift version constraints:** This uses standard Foundation APIs (`FileManager`, `Codable`, `JSONEncoder`/`JSONDecoder`)
2. **No new dependencies:** Everything is in-module, no new SPM packages
3. **Safe operations:** Atomic writes prevent corruption even if app crashes during save
4. **Zero configuration:** Works out of the box, no user action needed
5. **Testable:** Each component (load, save) can be tested independently

---

## Future Enhancements (Out of Scope)

- [ ] Store other preferences in the same file (general settings.json)
- [ ] Add preference export/import UI
- [ ] Add preference sync between machines
- [ ] Add preference version migration logic

These are out of scope for issue #151 but could be added later following the same pattern.
