# Testing the Neural Engine Warm-up Fix (Issue #161)

This guide walks you through testing the fix for the 10-second latency on first dictation after installation.

## Implementation Summary

**What was fixed:**
- Replaced silent audio samples (all zeros) with realistic synthetic audio containing multiple frequencies
- Warm-up now runs two passes to exercise different Whisper code paths:
  - Pass 1: Standard inference (without prompt)
  - Pass 2: Context-aware inference (with prompt)
- Expected warm-up duration: 2-3 seconds (during onboarding, transparent to user)
- Expected first dictation latency: <1 second (down from 10 seconds)

**Files Modified:**
- `Sources/LookMaNoHands/Services/WhisperService.swift` - Added `generateWarmupAudio()` and `warmUpNeuralEngine()`
- `Sources/LookMaNoHands/Views/OnboardingView.swift` - Updated to call new warm-up method

## Testing Procedure

### Step 1: Complete Clean Environment

```bash
./test-cleanup.sh
```

This removes:
- ✅ WhisperKit model cache
- ✅ App preferences and UserDefaults (both `com.qaid.LookMaNoHands` and `LookMaNoHands` variants)
- ✅ App support data
- ✅ Installed app bundle

### Step 2: Rebuild and Deploy

```bash
./deploy.sh
```

This builds the latest code and deploys to `~/Applications/Look Ma No Hands.app`

### Step 3: Launch App and Complete Onboarding

```bash
open ~/Applications/"Look Ma No Hands.app"
```

The app should immediately show the onboarding screen (first launch detected).

**During onboarding:**
1. Select a model (e.g., "Base" for fastest testing, or "Large v3 Turbo" for best accuracy)
2. Grant system permissions when prompted
3. **Wait for download to complete** - this is where the warm-up happens

### Step 4: Monitor Logs for Warm-up

**Option A: Terminal Real-time (Recommended)**

In a separate terminal, stream logs while onboarding runs:

```bash
# Terminal 1: Start log stream
log stream --predicate 'process == "LookMaNoHands"' --level debug

# Terminal 2: Launch app
open ~/Applications/"Look Ma No Hands.app"
```

**What to look for:**
```
🔥 Warming up Neural Engine...
✅ Neural Engine warm-up complete in X.XXs
```

The warm-up should take 2-3 seconds. You'll see two transcription passes logged:
- First pass: without prompt
- Second pass: with prompt "This is a test."

**Option B: Console.app**

1. Open Console.app
2. Select "LookMaNoHands" from the sidebar
3. Search for: `Warming up Neural Engine`
4. Watch as warm-up completes during onboarding

### Step 5: Test First Dictation

After onboarding completes and app returns to menu bar:

1. **Prepare to dictate:** Have something ready to say (any short phrase)
2. **Press Caps Lock** (or configured hotkey)
3. **Speak a phrase** (e.g., "Hello world")
4. **Release Caps Lock** to end recording
5. **Measure latency:**
   - Look at logs for transcription timing
   - Check RTF (Real-Time Factor) value:
     - Audio duration / Processing time = RTF
     - Example: If you spoke 2 seconds and it took 0.8s to process, RTF = 2 / 0.8 = 2.5x

**Expected Result:**
```
✅ Transcription complete in 0.XX s (RTF: X.XXx) - "your dictation"
```

- ✅ **Success:** First dictation takes <1 second
- ❌ **Failure:** First dictation takes >5 seconds (warm-up didn't work)

### Step 6: Verify Subsequent Dictations

Perform 2-3 more dictations and verify they're consistently fast:
- Each should be <0.5 seconds
- RTF should be consistent (no regression from first dictation)

## Success Criteria

- ✅ Onboarding triggers on fresh install (clean state verified)
- ✅ Warm-up logs appear: `🔥 Warming up Neural Engine...`
- ✅ Warm-up completes without errors: `✅ Neural Engine warm-up complete in X.XXs`
- ✅ First real dictation: <1 second latency (or RTF < 1.0 for short audio)
- ✅ Subsequent dictations: <0.5 seconds (no regression)
- ✅ No user-visible changes to onboarding flow
- ✅ Warm-up failures don't block onboarding (graceful fallback)

## Edge Cases to Test

### 1. Model Already Cached
If you run the test twice without clearing cache:
- Second run should skip download but still run warm-up
- Warm-up should be slightly faster since model is cached

### 2. Different Model Sizes
Test with both:
- "Base" (150MB) - Fastest warm-up
- "Large v3 Turbo" (600MB) - More thorough GPU workout

Expected behavior: Larger models take slightly longer to warm up but still <3 seconds

### 3. Warm-up Failure (Intentional)
If warm-up fails for any reason:
- Onboarding should still complete
- First dictation will be slow (10s+) but still work
- Logs should show the error

## Performance Benchmarks

### Before Fix
- Warm-up: Silent samples (100ms)
- First dictation: 10-15 seconds (Neural Engine lazily initialized)
- Subsequent dictations: 0.5-1.0 seconds

### After Fix
- Warm-up: Realistic synthetic audio (2-3 seconds)
- First dictation: <1 second (Neural Engine pre-initialized)
- Subsequent dictations: 0.5 seconds (unchanged)

## Troubleshooting

### Issue: Onboarding doesn't show on fresh install
**Solution:** Run `./test-cleanup.sh` again - there may be stale preferences

### Issue: Warm-up logs don't appear
**Solution:**
1. Check that you're watching logs during download phase
2. Verify model is downloading (watch for "Downloading..." progress)
3. If download finishes quickly, model may have been cached

### Issue: First dictation still slow (>5 seconds)
**Solution:**
1. Check warm-up logs - did warm-up complete successfully?
2. Try a second dictation - should be faster
3. If second dictation is also slow, warm-up failed silently

### Issue: Log stream not working
**Solution:** Use Console.app instead:
```bash
open /Applications/Utilities/Console.app
# Search for "LookMaNoHands" and "Neural Engine"
```

## Log Examples

### Successful Warm-up Sequence

```
📖 Settings: No saved onboarding status - defaulting to false (first launch)
🔍 Onboarding check: hasCompletedOnboarding=false, justCompletedOnboarding=false
🆕 First launch detected - showing onboarding
🎬 showOnboarding() - Creating onboarding window

[User selects model and grants permissions]

Downloading WhisperKit model 'base'...
✅ Model 'base' downloaded successfully

🔥 Warming up Neural Engine...
🎤 Starting transcription: 48000 samples (3.0s of audio)
📋 Initial prompt set (15 chars, 4 tokens): "This is a test."
✅ Transcription complete in 1.23s (RTF: 0.41x) - ""

🎤 Starting transcription: 48000 samples (3.0s of audio)
📋 Initial prompt set (15 chars, 4 tokens): "This is a test."
✅ Transcription complete in 0.89s (RTF: 0.30x) - ""

✅ Neural Engine warm-up complete in 2.15s

[Onboarding completes, user returns to menu bar]

[User presses Caps Lock and dictates]

🎤 Starting transcription: 32000 samples (2.0s of audio)
✅ Transcription complete in 0.45s (RTF: 0.23x) - "hello world"
```

### Synthetic Audio Characteristics

The warm-up audio contains:
- **120 Hz** (fundamental, typical male voice)
- **240 Hz** (2nd harmonic, octave)
- **480 Hz** (4th harmonic)
- **960 Hz** (8th harmonic)
- **Decreasing amplitudes** (0.3, 0.15, 0.1, 0.05) for realistic voice characteristics
- **Fade in/out envelopes** to prevent clicks

This exercises the full Whisper pipeline:
- Mel-spectrogram computation (frequency analysis)
- Encoder processing (speech feature extraction)
- Decoder beam search (with and without prompt)
- VAD (Voice Activity Detection) with real signal, not silence

## Questions?

Check the implementation details in the plan file:
```bash
cat .context/attachments/plan.md
```

Or examine the code:
```bash
# View warm-up methods
rg "warmUpNeuralEngine|generateWarmupAudio" Sources/

# View updated onboarding call
rg "warmUpNeuralEngine" Sources/LookMaNoHands/Views/OnboardingView.swift -B 2 -A 2
```
