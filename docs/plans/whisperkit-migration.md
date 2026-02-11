# WhisperKit Migration Plan

## Overview

Migrate the transcription engine from **whisper.cpp** (via SwiftWhisper) to **WhisperKit** (by Argmax) for better performance on Apple Silicon. WhisperKit provides ~2.7x faster inference, 75% lower energy consumption, native streaming support, and a cleaner Swift async/await API.

**Closes:** #57 (meeting transcription accuracy)
**Scope:** 6 files modified, 0 new files

---

## Migration Phases

```
Phase 1: Package + WhisperService core     (foundation - must be first)
    │
    ├── Phase 2: Model management + download   (depends on Phase 1)
    │
    ├── Phase 3: Context awareness + vocabulary (depends on Phase 1)
    │
    └── Phase 4: Streaming for meetings        (depends on Phase 1)
          │
          Phase 5: UI updates + cleanup        (depends on all above)
```

---

## Phase 1: Replace Package Dependency and Core Transcription

**Files:** `Package.swift`, `WhisperService.swift`

### 1a. Swap SPM dependency

Replace in `Package.swift`:
```swift
// OLD
.package(url: "https://github.com/exPHAT/SwiftWhisper.git",
         revision: "a192004db08de7c6eaa169eede77f1625e7d23fb")
// ...
.product(name: "SwiftWhisper", package: "SwiftWhisper")

// NEW
.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
// ...
.product(name: "WhisperKit", package: "WhisperKit")
```

### 1b. Rewrite WhisperService core

Replace the `Whisper` instance and loading logic:

```swift
import WhisperKit

class WhisperService: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var tokenizer: (any WhisperTokenizer)?
    private(set) var isModelLoaded = false

    func loadModel(named modelName: String = "base") async throws {
        let config = WhisperKitConfig(
            model: modelName,
            verbose: false
        )
        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.tokenizer = kit.tokenizer
        isModelLoaded = true
    }
}
```

### 1c. Rewrite transcribe() method

Replace the current method that uses serial DispatchQueue + C string pointers:

```swift
func transcribe(samples: [Float], initialPrompt: String? = nil) async throws -> String {
    guard let whisperKit else { throw WhisperError.modelNotLoaded }
    guard !samples.isEmpty else { throw WhisperError.emptyAudio }

    var options = DecodingOptions(
        language: "en",
        temperature: 0.0,
        suppressBlank: false,
        noSpeechThreshold: 0.6,
        compressionRatioThreshold: 2.4
    )

    // Token-based prompt (see Phase 3 for full vocabulary strategy)
    if let prompt = initialPrompt, let tokenizer {
        options.promptTokens = tokenizePrompt(prompt, tokenizer: tokenizer)
    }

    let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
    let text = results.map { $0.text }.joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return text
}
```

**Removes:**
- Serial `transcriptionQueue` (WhisperKit handles concurrency internally)
- `initialPromptCString` / `strdup` / `free` (no C interop needed)
- `withCheckedThrowingContinuation` bridging (native async/await)

### 1d. Verify build

```bash
swift build -c release
```

If Xcode Command Line Tools alone don't suffice for Core ML compilation, install full Xcode.

---

## Phase 2: Model Management and Download

**Files:** `WhisperService.swift`, `Settings.swift`

### 2a. Update model naming and discovery

WhisperKit downloads models automatically from Hugging Face (`argmaxinc/whisperkit-coreml`). Update the model enum in `Settings.swift`:

```swift
enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3turbo = "large-v3-turbo"  // New: best speed/accuracy tradeoff

    var displayName: String { ... }
    // Remove modelFileName - WhisperKit manages its own files
}
```

### 2b. Simplify downloadModel()

WhisperKit handles model download internally. Replace the manual Hugging Face download + SHA256 verification + safe unzip logic:

```swift
static func downloadModel(named modelName: String, progress: @escaping (Double) -> Void) async throws {
    // WhisperKit downloads + caches models automatically on init
    // We just need to trigger a load to initiate the download
    let config = WhisperKitConfig(model: modelName, verbose: true)
    _ = try await WhisperKit(config)
    progress(1.0)
}
```

**Note:** The current SHA256 checksum verification and zip bomb protection can be removed. WhisperKit manages model integrity through its own Hugging Face integration. The checksums in the current code are placeholder values anyway.

### 2c. Update modelExists()

```swift
static func modelExists(named modelName: String) -> Bool {
    // Check WhisperKit's model cache directory
    let modelDir = WhisperKit.modelDirectoryURL
    // Check if model folder exists in cache
    ...
}
```

### 2d. Add large-v3-turbo as recommended model

For meeting transcription (issue #57), `large-v3-turbo` offers the best accuracy at 6x faster inference than `large-v3`. Update the onboarding default recommendation.

---

## Phase 3: Context Awareness and Custom Vocabulary Strategy

**Files:** `WhisperService.swift`, `AppDelegate.swift`

This is the most nuanced phase. WhisperKit uses token-based prompts (`promptTokens: [Int]?`) instead of whisper.cpp's string-based `initial_prompt`. The migration strategy preserves the existing two-tier vocabulary system while adapting to the token API.

### Current Architecture (unchanged)

The app has a **dual-layer** approach to custom vocabulary:

1. **Pre-transcription biasing** (Whisper prompt) — nudges the model toward correct spellings
2. **Post-transcription replacement** (TextFormatter) — deterministic find/replace on output text

Both layers remain. Only the pre-transcription mechanism changes.

### 3a. Add tokenization helper to WhisperService

```swift
/// Tokenize a prompt string for WhisperKit's DecodingOptions.promptTokens
/// Filters out special tokens that would confuse the decoder
private func tokenizePrompt(_ text: String, tokenizer: any WhisperTokenizer) -> [Int] {
    let tokens = tokenizer.encode(text: text)
    return tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
}
```

### 3b. Keep AppDelegate.buildInitialPrompt() as-is

The existing `buildInitialPrompt()` method (AppDelegate.swift:713-740) already produces a clean string combining:
- App-context style hints (email, chat, code, document styles)
- Custom vocabulary terms ("Technical terms: Xcode, SwiftUI, Ollama, ...")

This string is passed to `whisperService.transcribe(samples:initialPrompt:)`. The only change is internal to WhisperService — it tokenizes the string before passing to WhisperKit instead of setting a C pointer.

### 3c. Handle the promptTokens known bug

WhisperKit issue [#372](https://github.com/argmaxinc/WhisperKit/issues/372): `promptTokens` can cause empty transcription with compressed model variants.

**Mitigation strategy:**
1. Use full-size (non-compressed) Core ML models — WhisperKit's Neural Engine acceleration means full-size models are still fast
2. Add fallback: if transcription returns empty and `promptTokens` was set, retry without tokens
3. Cap token count: limit `promptTokens` to ~100 tokens (the current 890-char cap maps to ~224 tokens, which may be aggressive — test and tune)

```swift
func transcribe(samples: [Float], initialPrompt: String? = nil) async throws -> String {
    // ... build options with promptTokens ...

    let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
    let text = results.map { $0.text }.joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // Fallback: retry without prompt if we got empty output (WhisperKit #372)
    if text.isEmpty, options.promptTokens != nil {
        Logger.shared.warning("Empty result with promptTokens, retrying without prompt", category: .transcription)
        var fallbackOptions = options
        fallbackOptions.promptTokens = nil
        let fallbackResults = try await whisperKit.transcribe(audioArray: samples, decodeOptions: fallbackOptions)
        return fallbackResults.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return text
}
```

### 3d. Post-transcription replacements (no changes needed)

`TextFormatter.applyVocabularyReplacements()` operates on the final text string and is completely independent of the transcription engine. No changes required.

### 3e. Vocabulary entry dual-purpose structure (no changes needed)

`Settings.VocabularyEntry` with `phrase` (what Whisper produces) and `replacement` (correct form) continues to work:
- `replacement` values are included in the prompt to bias transcription
- `phrase` → `replacement` mapping is applied post-transcription by TextFormatter

---

## Phase 4: Streaming Transcription for Meetings

**Files:** `ContinuousTranscriber.swift`

### 4a. Evaluate replacing ContinuousTranscriber with WhisperKit streaming

WhisperKit has native streaming with:
- 15-second chunks (vs current 5-second chunks with 1-second overlap)
- Built-in VAD (vs current RMS < 0.01 threshold)
- Hypothesis + confirmed text dual output

**Option A — Minimal change:** Keep `ContinuousTranscriber` as-is, just swap the `whisperService.transcribe()` call. This works because the interface is unchanged.

**Option B — Full rewrite:** Replace `ContinuousTranscriber` with WhisperKit's streaming API for better latency and accuracy. This addresses issue #57 directly.

**Recommendation:** Start with Option A to get the migration working, then iterate to Option B for meeting mode improvements.

### 4b. Audio format compatibility

WhisperKit expects the same 16kHz mono Float32 format that the current `AudioRecorder`, `SystemAudioRecorder`, and `MixedAudioRecorder` already produce. No changes needed to audio recording services.

---

## Phase 5: UI Updates and Cleanup

**Files:** `OnboardingView.swift`, `SettingsView.swift`

### 5a. Update OnboardingView model step

- Update model size display for Core ML models (sizes differ from GGML)
- Add `large-v3-turbo` as an option
- Update download progress (WhisperKit may not expose granular progress)

### 5b. Update SettingsView model tab

- Reflect new model options
- Remove references to Core ML as optional (it's always used with WhisperKit)

### 5c. Remove dead code

- Remove `modelChecksums` dictionary
- Remove `modelSizes` dictionary
- Remove `safeUnzip()` method
- Remove `verifyChecksum()` method
- Remove `validateSize()` method
- Remove `coreMLAvailableModels` set
- Remove `initialPromptCString` and all `strdup`/`free` calls

---

## Files Changed Summary

| File | Phase | Change Type |
|------|-------|-------------|
| `Package.swift` | 1 | Swap dependency |
| `WhisperService.swift` | 1, 2, 3 | Major rewrite |
| `Settings.swift` | 2 | Update model enum |
| `ContinuousTranscriber.swift` | 4 | Minimal (interface unchanged) |
| `OnboardingView.swift` | 5 | Update model UI |
| `SettingsView.swift` | 5 | Update model UI |

**Files NOT changed** (interface insulated by WhisperService):
- `AppDelegate.swift` — calls `whisperService.transcribe()` which keeps the same signature
- `TextFormatter.swift` — operates on output text, engine-agnostic
- `AudioRecorder.swift` — produces 16kHz Float32, same format needed
- `SystemAudioRecorder.swift` — same
- `MixedAudioRecorder.swift` — same
- `MeetingView.swift` — passes WhisperService to ContinuousTranscriber, unchanged

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `promptTokens` empty output bug (#372) | Medium | Fallback retry without tokens; use full-size models |
| SPM build fails without full Xcode | Medium | Install Xcode 15+; user has agreed to this |
| Model download size increase (Core ML) | Low | WhisperKit uses compressed models (~0.6GB for large-v3-turbo) |
| Intel Mac users broken | Low | Project targets macOS 14+ which is Apple Silicon era |
| WhisperKit API breaking changes | Low | Pin to specific version in Package.swift |

---

## Validation Checklist

- [ ] `swift build -c release` succeeds
- [ ] Model download works (tiny model for quick test)
- [ ] Basic dictation: press Caps Lock → speak → text inserted
- [ ] Custom vocabulary terms appear correctly in output
- [ ] App-context prompts work (test in email app vs IDE)
- [ ] Meeting mode: continuous transcription produces output
- [ ] Onboarding flow: model download + first transcription
- [ ] Performance: measure RTF and compare to whisper.cpp baseline
