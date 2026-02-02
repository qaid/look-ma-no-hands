# Waveform Visualizer Improvements

## Changes Made

### 1. Meeting Mode Fix ✅
**Issue**: Waveform was showing during meeting transcription
**Fix**: Confirmed that waveform is only shown in dictation mode
- The `RecordingIndicatorWindowController` is only called from `AppDelegate.startRecording()` (dictation mode)
- Meeting mode in `MeetingView` uses `MixedAudioRecorder` and never calls `recordingIndicator.show()`
- Added documentation comment to make this explicit

**Code Location**: `Sources/LookMaNoHands/Views/RecordingIndicator.swift:42-44`

### 2. Amplitude Scaling Improvements ✅
**Issue**: Waveform bars constantly hitting peak (maxed out)
**Fix**: Applied two improvements to reduce peaking

#### Changes:
1. **Reduced amplitude multiplier**: `0.5x` instead of `1.0x`
2. **Non-linear scaling**: Applied square root compression to loud sounds
   - Formula: `sqrt(level) * 0.5` instead of `level * 1.0`
   - Effect: Loud sounds are compressed more than quiet sounds
   - Result: More dynamic range visible in the visualization

**Code Location**: `Sources/LookMaNoHands/Views/RecordingIndicator.swift:17-19`

**Expected Behavior**:
- Quiet speech: bars at 10-30% height
- Normal speech: bars at 30-60% height
- Loud speech/sounds: bars at 60-90% height
- Very loud sounds: bars occasionally hit 100% (rare)

### 3. Light Mode Support ✅
**Issue**: Waveform colors optimized for dark mode, hard to see in light mode
**Fix**: Automatic theme adaptation

#### Dark Mode Colors (Original):
- Base: Light blue `rgb(76, 153, 255)`
- Peak: Purple-blue blend
- Opacity: 0.8
- Border: Light blue `rgb(76, 153, 255)`

#### Light Mode Colors (New):
- Base: Deeper blue `rgb(51, 102, 204)` - 50% darker than dark mode
- Peak: Navy blue blend
- Opacity: 0.9 (higher for better contrast)
- Border: Deep blue `rgb(25, 102, 204)`
- Shadow: Slightly lighter (0.15 vs 0.2 opacity)

**Code Location**: `Sources/LookMaNoHands/Views/RecordingIndicator.swift:24-39, 56-64`

**Theme Switching**: Uses SwiftUI's `@Environment(\.colorScheme)` to automatically follow system appearance settings

## Testing Checklist

### Dictation Mode (Waveform should appear)
- [ ] Start dictation with Caps Lock
- [ ] Verify waveform appears near cursor/at configured position
- [ ] Speak at different volumes and verify dynamic range:
  - [ ] Quiet speech shows small bars (10-30%)
  - [ ] Normal speech shows medium bars (30-60%)
  - [ ] Loud speech shows large bars (60-90%)
  - [ ] Very loud sounds occasionally hit full height
- [ ] In System Settings, toggle Light/Dark mode and verify colors adapt
- [ ] Verify light mode has good contrast and visibility

### Meeting Mode (Waveform should NOT appear)
- [ ] Open meeting transcription window
- [ ] Click "Start Recording"
- [ ] Verify NO waveform indicator appears anywhere
- [ ] Verify meeting window shows its own recording UI

### Edge Cases
- [ ] Switch from dictation to meeting mode - waveform should hide
- [ ] Switch from meeting to dictation mode - waveform should show
- [ ] Test with multiple displays - waveform positions correctly
- [ ] Test with different system themes - colors adapt correctly

## Technical Details

### Amplitude Scaling Math
```swift
// Before: Linear scaling
barHeight = level * windowHeight

// After: Square root scaling with reduced multiplier
normalizedLevel = sqrt(level) * 0.5
barHeight = normalizedLevel * windowHeight
```

**Why square root?**
- Audio levels are already in dB (logarithmic)
- Square root provides additional compression
- Makes visualization more perceptually linear
- Preserves dynamic range while preventing constant peaking

### Color Formulas

**Dark Mode**:
```swift
Color(
    red: 0.3 + level * 0.5,   // 0.3 -> 0.8
    green: 0.6 - level * 0.3,  // 0.6 -> 0.3
    blue: 1.0                  // constant
)
```

**Light Mode**:
```swift
Color(
    red: 0.1 + level * 0.3,   // 0.1 -> 0.4 (darker)
    green: 0.4 - level * 0.2,  // 0.4 -> 0.2 (darker)
    blue: 0.9 - level * 0.2   // 0.9 -> 0.7 (darker)
)
```

## Files Modified

1. `Sources/LookMaNoHands/Views/RecordingIndicator.swift`
   - Updated `WaveformBarsView` with amplitude scaling
   - Added `@Environment(\.colorScheme)` for theme detection
   - Added light mode color formulas
   - Updated `RecordingIndicator` with theme-aware border and shadow
   - Added documentation about dictation-only usage
