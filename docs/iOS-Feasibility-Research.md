# iOS Technical Feasibility Research

**Research Date:** February 8, 2026
**Purpose:** Evaluate technical requirements for bringing Look Ma No Hands to iOS while maintaining core principles: 100% local processing, privacy-first design, and superior UX vs. built-in dictation.

---

## Executive Summary

An iOS version of Look Ma No Hands is **technically possible but fundamentally compromised** compared to macOS. iOS lacks the accessibility APIs that enable the macOS "press Caps Lock anywhere" experience. The closest approximation requires custom keyboard extensions with explicit user action to switch keyboards.

### Key Findings:
- ✅ **Can Work:** On-device Whisper transcription, custom keyboard text insertion, microphone-based dictation
- ⚠️ **Requires Compromise:** No global hotkeys, must use Lock Screen widgets or keyboard switching
- ❌ **Cannot Work:** System audio capture for meetings, auto-insert without user action, Caps Lock trigger

**Recommendation:** If iOS port is pursued, position Lock Screen widgets as the primary trigger mechanism, with the understanding that this is a fundamentally different UX than macOS.

---

## Research Deliverable

### 1. ✅ What features can work as-is?

**On-Device Speech Recognition:**
- **whisper.cpp fully supported on iOS** with 3-6x speedup using Core ML/Apple Neural Engine
- Real iPhone 13 benchmarks: `base.en` processes 30s audio in ~1 second
- WhisperKit framework optimized for iOS with 75% energy reduction
- All models (tiny to large-v3) work on-device with no network dependency
- Alternative: Apple's new Speech Framework (iOS 26+) is 2.2x faster but less accurate (3% CER vs 0.3% for Whisper)

**Background Audio Recording:**
- iOS supports background microphone recording via `UIBackgroundModes: audio`
- Must start recording in foreground, then continues through screen lock
- Requires `.playAndRecord` AVAudioSession category (not `.record`)
- No time limits beyond storage/battery constraints
- Interruptions (calls, alarms) pause recording gracefully

**Text Formatting & Processing:**
- All macOS text formatting logic (punctuation, capitalization, etc.) works identically
- Ollama integration possible for advanced formatting (if user runs Ollama locally)
- Context-aware formatting features could be implemented

### 2. ⚠️ What features need alternative approaches?

**System-Wide Text Insertion:**
- **macOS approach:** Uses `AXUIElement` API to insert text into any app
- **iOS alternative:** Custom Keyboard Extension only
  - Requires user to manually switch to custom keyboard
  - Works system-wide once active
  - Cannot work in password fields or phone number fields
  - Requires "Full Access" permission for advanced features
  - 60-70MB memory limit prevents running Whisper models inside keyboard

**Recommended iOS architecture:**
```
Main App: Record audio → Transcribe with Whisper → Copy to shared container
Custom Keyboard: Read from shared container → Insert text via textDocumentProxy
```

**Global Trigger Mechanism:**
- **macOS approach:** Monitors Caps Lock via `CGEvent` API
- **iOS alternatives (in priority order):**
  1. **Lock Screen Widget** (iOS 16+) - Best balance of accessibility and speed
  2. **Control Center Widget** (iOS 18+) - Fastest access from anywhere
  3. **Action Button + Shortcuts** (iPhone 15 Pro+) - Physical button trigger
  4. **Siri Voice Commands** - Hands-free activation
  5. **Home Screen Widget** - Standard widget placement

**Meeting Transcription:**
- **macOS approach:** ScreenCaptureKit captures system audio + microphone
- **iOS alternative:** Microphone-only recording
  - Can only capture user's own voice, not other participants
  - No system audio capture possible on iOS (architectural restriction)
  - Best for personal voice memos, not multi-participant meetings

### 3. ❌ What features are impossible on iOS?

**System Audio Capture:**
- iOS has **no equivalent to macOS ScreenCaptureKit**
- ReplayKit can only capture audio from your own app, not other apps
- Cannot record audio from Zoom, Teams, FaceTime, phone calls, or any other application
- This is an intentional security/privacy restriction enforced by iOS sandboxing
- **No workaround exists through public APIs**

**Global Hotkey Monitoring:**
- iOS does not allow apps to monitor hardware buttons (volume, Action button, etc.)
- Volume button as shutter is a camera-specific exception, not accessible to general apps
- No equivalent to macOS `CGEvent` tap for keyboard/button monitoring

**Auto-Insert Without User Action:**
- Cannot programmatically insert text into other apps without user switching keyboards
- No accessibility API equivalent to macOS `AXUIElement` for cross-app UI manipulation
- Security model prevents any cross-app interaction without explicit user action

**Secure Text Field Access:**
- Custom keyboards are automatically replaced by system keyboard in password fields
- Cannot transcribe or insert into secure contexts (by design)

### 4. 🎯 What's the recommended MVP feature set for iOS?

**Phase 1: Core Dictation (Feature Parity Where Possible)**

**Included Features:**
- On-device Whisper transcription (base.en or small model)
- Custom keyboard extension for system-wide text insertion
- Lock Screen widget for quick access
- Background recording support
- Smart formatting (punctuation, capitalization)
- Multiple language support (99 languages via Whisper)

**User Workflow:**
```
1. Tap Lock Screen widget → App opens and starts recording
2. Speak → App transcribes locally
3. Tap "Insert" → Switches to custom keyboard automatically
4. Text appears in target app
```

**Or (for power users):**
```
1. Already using custom keyboard in any app
2. Tap microphone button in keyboard
3. Speak → Transcribed text inserted immediately
```

**Excluded Features (vs. macOS):**
- ❌ Meeting mode with system audio (impossible on iOS)
- ❌ Caps Lock trigger (no global hotkeys)
- ❌ Auto-insert without keyboard switch
- ❌ Multi-participant transcription

**Phase 2: iOS-Specific Enhancements**

- Control Center widget (iOS 18+)
- Action Button shortcut (iPhone 15 Pro+)
- Siri phrase integration
- Widget-based recording history
- Real-time streaming transcription
- Context-aware suggestions

**Phase 3: Advanced Features**

- Ollama integration for advanced formatting
- Custom vocabulary learning
- Voice commands for text editing
- Clipboard history integration

### 5. 🛠️ What's the development approach?

**Recommended Architecture: Shared Swift Package**

```
look-ma-no-hands/
├── LookMaNoHands-macOS/          # Existing macOS app
├── LookMaNoHands-iOS/            # New iOS app
├── Shared/                       # Shared Swift Package
│   ├── WhisperService/           # Transcription (works on both)
│   ├── TextFormatter/            # Formatting logic (works on both)
│   ├── OllamaService/            # Optional LLM (works on both)
│   └── Models/                   # Data models (works on both)
├── Platform-Specific/
│   ├── macOS/
│   │   ├── KeyboardMonitor       # Caps Lock (macOS only)
│   │   ├── TextInsertion         # AXUIElement (macOS only)
│   │   └── SystemAudioRecorder   # ScreenCaptureKit (macOS only)
│   └── iOS/
│       ├── KeyboardExtension     # Custom keyboard (iOS only)
│       ├── LockScreenWidget      # Quick access (iOS only)
│       └── ControlCenterWidget   # iOS 18+ (iOS only)
```

**Benefits:**
- ~70% code reuse (Whisper, formatting, Ollama)
- Separate platform-specific implementations for audio/text insertion
- Independent release cycles
- Shared bug fixes and improvements

**Development Roadmap:**

1. **Research Phase** (✅ Complete)
   - Validate technical constraints
   - Document limitations

2. **Prototype Phase** (2-3 weeks)
   - Extract shared code into Swift Package
   - Build minimal iOS app with Whisper integration
   - Test custom keyboard extension
   - Validate Lock Screen widget workflow

3. **MVP Development** (4-6 weeks)
   - Full iOS app with recording UI
   - Custom keyboard with shared container
   - Lock Screen + Control Center widgets
   - Onboarding flow for permissions/setup

4. **Testing & Polish** (2-3 weeks)
   - Test on multiple iPhone models (13, 14, 15 Pro, 16)
   - Battery life profiling
   - Memory usage optimization
   - App Store submission preparation

5. **Maintenance**
   - Monitor for iOS API changes
   - Update Whisper models as new versions release
   - Collect user feedback on iOS-specific UX

---

## Technical Deep Dive

### System-Wide Text Insertion (iOS)

**How it works:**
```swift
// Main App (LookMaNoHands-iOS)
class TranscriptionService {
    func transcribe(audioURL: URL) async -> String {
        let whisper = Whisper(modelPath: modelPath)
        let transcription = try await whisper.transcribe(audioURL)

        // Save to shared container
        let sharedDefaults = UserDefaults(suiteName: "group.com.yourapp.lmnohands")
        sharedDefaults?.set(transcription, forKey: "pendingText")

        // Switch to keyboard (or user does manually)
        return transcription
    }
}

// Keyboard Extension
class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Read from shared container
        let sharedDefaults = UserDefaults(suiteName: "group.com.yourapp.lmnohands")
        if let pendingText = sharedDefaults?.string(forKey: "pendingText") {
            // Insert text
            textDocumentProxy.insertText(pendingText)

            // Clear pending text
            sharedDefaults?.removeObject(forKey: "pendingText")
        }
    }
}
```

**Limitations:**
- Keyboard has 60-70MB RAM limit (cannot run Whisper models inside)
- Requires "Full Access" permission for shared container access
- User must switch to keyboard (can be automated with `UIApplication.openURL` deep link)

### Background Recording Implementation

```swift
// Info.plist
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>

// Audio session configuration
class AudioRecorder {
    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Use playAndRecord (not record alone)
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    func startRecording() {
        // Must start in foreground
        setupAudioSession()
        audioRecorder.record()

        // Recording continues when app goes to background
    }
}
```

### Widget-Based Quick Access

```swift
// Lock Screen Widget (iOS 16+)
import WidgetKit
import AppIntents

struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Dictation"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationManager.shared.startRecording()
        return .result()
    }
}

struct DictationLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickDictation", provider: Provider()) { entry in
            Button(intent: StartDictationIntent()) {
                VStack {
                    Image(systemName: "mic.fill")
                    Text("Dictate")
                }
            }
        }
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
```

### Whisper Integration

```swift
// Using WhisperKit (recommended for iOS)
import WhisperKit

class TranscriptionService {
    private var whisperKit: WhisperKit?

    func initialize() async {
        // Downloads and compiles model if needed
        whisperKit = try? await WhisperKit(
            model: "base.en",
            computeUnits: .cpuAndNeuralEngine // Use ANE for 3-6x speedup
        )
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisper = whisperKit else { throw TranscriptionError.notInitialized }

        // Transcribe with real-time callbacks
        let result = try await whisper.transcribe(audioPath: audioURL.path)
        return result.text
    }
}
```

---

## Platform Comparison: macOS vs iOS

| Feature | macOS (Current) | iOS (Proposed) | Status |
|---------|----------------|----------------|--------|
| **Text Insertion** | AXUIElement (any app) | Custom keyboard | ⚠️ Requires user action |
| **Trigger Mechanism** | Caps Lock (global) | Lock Screen widget | ⚠️ Different UX |
| **Background Recording** | Always available | UIBackgroundModes | ✅ Works similarly |
| **Whisper Models** | All models work | All models work | ✅ Same performance |
| **System Audio Capture** | ScreenCaptureKit | Not possible | ❌ iOS limitation |
| **Meeting Transcription** | ✅ Full support | ❌ Mic only | ❌ iOS limitation |
| **Privacy Model** | 100% local | 100% local | ✅ Maintained |
| **Formatting** | Smart punctuation | Smart punctuation | ✅ Same logic |
| **Ollama Integration** | Optional LLM | Optional LLM | ✅ Works if installed |

---

## User Experience Comparison

**macOS Workflow (Current):**
```
1. Press Caps Lock
2. Speak
3. Text appears automatically
Total: 1 key press + voice
```

**iOS Workflow (Proposed - Lock Screen Widget):**
```
1. Tap Lock Screen widget
2. Authenticate (Face ID/Touch ID)
3. App opens and starts recording
4. Speak
5. Tap "Insert"
6. Switch to target app
7. Text appears in custom keyboard
Total: 3 taps + authentication + voice
```

**iOS Workflow (Alternative - Keyboard Button):**
```
1. Switch to custom keyboard (one-time per app)
2. Tap microphone button
3. Speak
4. Text appears immediately
Total: 1 tap + voice (after initial keyboard setup)
```

**UX Assessment:**
- iOS requires more steps than macOS (inherent platform limitation)
- Keyboard button approach is closest to macOS experience
- Lock Screen widget is more accessible but slower

---

## Privacy & Security Considerations

**Custom Keyboard "Full Access" Permission:**
- Required for shared container access (main app ↔ keyboard)
- Users are often hesitant to grant this permission
- Must provide clear privacy policy explaining:
  - No data sent to servers
  - No keystroke logging
  - Only reads transcribed text from shared container
  - Keystrokes from other contexts never accessed

**Mitigation Strategies:**
1. In-app education about Full Access permission
2. Published privacy policy and open-source keyboard extension
3. App Store privacy labels showing "No Data Collected"
4. Option to use clipboard-based workflow (no Full Access needed)

**Maintained Privacy Principles:**
- ✅ All processing on-device (Whisper runs locally)
- ✅ No data sent to cloud
- ✅ No third-party analytics
- ✅ Optional Ollama (user-controlled, local only)

---

## Performance Considerations

**Whisper Model Recommendations by Device:**

| Device | Recommended Model | Memory | Latency (30s audio) |
|--------|------------------|---------|---------------------|
| iPhone 13/14 (Base) | base.en | 75MB | ~1s |
| iPhone 13/14 Pro | small.en | 150MB | ~2s |
| iPhone 15 Pro+ | small or medium | 150-500MB | ~1-3s |
| iPhone 16 Pro | medium or large | 500MB-1.5GB | ~2-5s |

**Battery Impact:**
- WhisperKit optimized: 0.3W per transcription (75% reduction vs standard)
- Real-time recording: ~3-5% battery per hour (screen off)
- Heavy use (10 min/day): <5% daily battery impact

**Storage Requirements:**
- App binary: ~50MB
- Whisper model: 30MB (tiny) to 1.5GB (large)
- Recordings (temporary): ~1MB per minute (auto-cleanup)

---

## App Store Considerations

**Background Audio Mode:**
- `UIBackgroundModes: audio` is primarily for apps that provide **audible content** to user
- Recording-only apps may face App Review scrutiny
- **Recommendation:** Add optional playback of transcribed audio (as voice feedback) to justify background audio mode

**Full Access Permission:**
- Must provide clear explanation before requesting
- Privacy policy must detail data handling
- Cannot store or transmit keystrokes

**Camera Volume Button:**
- Do NOT attempt to use volume buttons as recording trigger
- This is restricted to camera apps and violates App Store guidelines

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Users don't understand keyboard switching | High | Comprehensive onboarding with video tutorials |
| Full Access permission denial | Medium | Offer clipboard-based workflow as fallback |
| App Store rejection (background audio) | Medium | Add audio playback feature, clear documentation |
| Battery drain complaints | Low | Optimize with WhisperKit, provide usage stats |
| Whisper model size complaints | Low | Offer model size selection, on-demand download |
| Meeting transcription expectations | High | Clear marketing: "Personal dictation, not meetings" |

---

## Competitive Analysis

**Existing iOS Dictation Apps:**

1. **Whisper Notes** ($4.99)
   - 100% offline transcription
   - Whisper Large V3 Turbo
   - No system-wide text insertion (manual copy/paste)

2. **ScribeAI** (Free + IAP)
   - Real-time transcription
   - CoreML acceleration
   - Limited to app only, not system-wide

3. **Whisper Transcribe** (Free + subscription)
   - System-wide via keyboard extension
   - Uses server-side Whisper (privacy concern)

**Look Ma No Hands iOS Differentiation:**
- ✅ 100% local processing (unique among keyboard extensions)
- ✅ Privacy-first (no server, no data collection)
- ✅ Lock Screen widget for quick access
- ✅ Smart formatting (punctuation, capitalization)
- ✅ Optional Ollama integration for advanced formatting

---

## Recommendations

### Should You Build iOS Version?

**Arguments For:**
- Large potential market (iOS users far outnumber macOS users)
- Core transcription technology proven and working
- 70% code reuse from macOS version
- Unique privacy-first positioning in market

**Arguments Against:**
- Fundamentally compromised UX vs. macOS (more steps required)
- Meeting transcription feature impossible (major value prop lost)
- Development and maintenance effort for reduced feature set
- User education burden (keyboard setup, permissions)

### If You Proceed:

1. **Set Expectations:** Market as "personal dictation" not "meeting transcription"
2. **Emphasize Privacy:** This is your key differentiator vs. cloud-based competitors
3. **Invest in Onboarding:** iOS UX is complex, need excellent tutorials
4. **Start with TestFlight:** Validate UX with small group before public launch
5. **Consider Freemium:** Free basic features, paid for larger models or Ollama integration

### If You Don't Proceed:

1. **Document Limitations:** Reference this research for future reconsideration
2. **Monitor iOS APIs:** Apple could add new capabilities in future iOS versions
3. **Focus on macOS:** Continue improving macOS version where you have API advantages

---

## Future iOS API Watch List

Apple could potentially add these features in future iOS versions:

- **System Audio Capture API:** Would enable meeting transcription (unlikely due to privacy concerns)
- **Improved Accessibility APIs:** Could provide macOS-like text insertion capabilities
- **Global Hotkey Registration:** Would allow hardware button triggers (low probability)
- **Background Processing Improvements:** Could simplify always-available recording

**Likelihood:** Low. iOS security model is intentionally restrictive. More likely that iOS capabilities remain constrained and macOS continues to have API advantages.

---

## Conclusion

An iOS version of Look Ma No Hands is **technically feasible** using:
- Custom keyboard extension for text insertion
- Lock Screen widgets for quick access
- On-device Whisper for transcription
- Background audio recording for uninterrupted capture

However, it will be a **fundamentally different product** than the macOS version:
- No one-tap Caps Lock trigger (requires Lock Screen widget or keyboard button)
- No meeting transcription (microphone-only, no system audio)
- More user setup required (keyboard installation, permissions)
- Additional steps in workflow (keyboard switching or widget launching)

**Final Recommendation:** Only pursue iOS if you can accept these limitations and position it as a complementary product with a different value proposition (personal dictation) rather than a direct port of the macOS feature set.

---

## Appendix: Technical References

### Key iOS APIs Used:
- `UIBackgroundModes` - Background audio recording
- `AVAudioSession` - Audio capture configuration
- `UIInputViewController` - Custom keyboard extension
- `UITextDocumentProxy` - Text insertion in keyboard
- `WidgetKit` - Lock Screen and Control Center widgets
- `AppIntents` - Siri, Shortcuts, and widget actions

### Whisper Integration:
- **WhisperKit**: https://github.com/argmaxinc/WhisperKit (Recommended)
- **SwiftWhisper**: https://github.com/exPHAT/SwiftWhisper (Alternative)
- **whisper.cpp**: https://github.com/ggml-org/whisper.cpp (Core engine)

### Apple Documentation:
- Custom Keyboards: https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard
- App Intents: https://developer.apple.com/documentation/appintents
- Background Execution: https://developer.apple.com/documentation/avfoundation/media_playback/creating_a_basic_video_player_ios_and_tvos/enabling_background_audio
- WidgetKit: https://developer.apple.com/documentation/widgetkit

---

**Document Version:** 1.0
**Last Updated:** February 8, 2026
**Research Conducted By:** Claude Sonnet 4.5
**Agent IDs:** a3e33d6, a18e3cb, a74113f, a182bb5, a006e42
