# Plan: Meeting Transcription Reorganization

## Context
The current `MeetingView.swift` (1,770 lines) is a monolithic UI that bundles recording, transcript display, LLM analysis, and export into a single window with no persistence. Users lose transcripts on window close unless they manually export. There's no way to import external audio/transcripts, no meeting type system, and no library of past meetings. The goal is to reorganize meeting transcription into three clear, focused chunks of functionality exposed as tabs in a single window: **Record**, **Library**, and **Analyze**.

---

## Architecture Overview

```
MeetingView (TabView container)
├── Tab 1: MeetingRecordTab    — live recording, waveform, real-time transcript
├── Tab 2: MeetingLibraryTab   — saved meetings list, import, retention settings
└── Tab 3: MeetingAnalyzeTab   — transcript viewer, meeting type, LLM processing

New Services:
  MeetingStore    — file system persistence (auto-save, retention policy)
  AudioFileImporter — decode/transcribe imported audio via WhisperService

New Models:
  MeetingType     — enum: standup, oneOnOne, allHands, customerCall, general, custom
  MeetingRecord   — persisted meeting metadata + file paths
```

---

## Implementation Phases

### Phase 1 — Foundation Models (no UI dependencies)

**New file: `Sources/LookMaNoHands/Models/MeetingType.swift`**
- `enum MeetingType: String, CaseIterable, Codable, Identifiable`
- Cases: `.standup`, `.oneOnOne`, `.allHands`, `.customerCall`, `.general`, `.custom`
- Each case provides `displayName`, `icon` (SF Symbol), and `defaultPrompt`
  - `.general` reuses the existing `Settings.defaultMeetingPrompt` constant
  - `.custom` has an empty default (user supplies their own)
  - The four named types get concise, role-specific templates (standup: blockers/done/next; 1:1: feedback/growth/actions; allHands: announcements/Q&A; customerCall: pain points/commitments/next steps)

**New file: `Sources/LookMaNoHands/Models/MeetingRecord.swift`**
```swift
struct MeetingRecord: Identifiable, Codable {
    let id: UUID
    var title: String           // "Standup - Feb 21, 2026 2:30 PM"
    var createdAt: Date
    var duration: TimeInterval
    var meetingType: MeetingType
    var source: MeetingSource   // .recorded | .importedTranscript | .importedAudio
    var transcriptFilename: String   // always "transcript.txt"
    var notesFilename: String?       // "notes.md" — nil until LLM run
    var audioFilename: String?       // for imported audio copy
    var segmentCount: Int
}
```
Paths are relative filenames (not absolute URLs) for portability.

**Modify: `Sources/LookMaNoHands/Models/Settings.swift`**
Follow existing `@Published` + `didSet` + `Keys` pattern to add:
```swift
// Keys: "meetingRetentionDays", "meetingRetentionCount", "meetingTypePrompts"
@Published var meetingRetentionDays: Int     // default 90; 0 = forever
@Published var meetingRetentionCount: Int    // default 0 = unlimited
@Published var meetingTypePrompts: [String: String]  // type.rawValue → custom override
```
`meetingTypePrompts` encodes natively in UserDefaults as a dict. The old `meetingPrompt` string stays in place (backwards compat — `general` type resolves it as fallback).

---

### Phase 2 — Storage Service

**New file: `Sources/LookMaNoHands/Services/MeetingStore.swift`**
```
@Observable class MeetingStore {
    private(set) var meetings: [MeetingRecord]  // sorted newest-first
    var isRecording: Bool = false               // set by RecordTab
    var isImportingAudio: Bool = false          // set during import
}
```
Storage location: `~/Library/Application Support/LookMaNoHands/Meetings/{uuid}/`
Each meeting folder contains:
- `metadata.json` — full `MeetingRecord`
- `transcript.txt` — plain text
- `notes.md` — optional, written after LLM processing
- `audio.{ext}` — optional copy of imported audio

Write order on save: (1) create folder, (2) write transcript.txt, (3) write metadata.json.
A crash between steps 2 and 3 leaves an orphan folder; `loadAllMeetings()` skips folders missing `metadata.json`. A `pruneOrphans()` call at launch cleans these up.

Public API:
```swift
func saveRecordedMeeting(segments, duration, type) async throws -> MeetingRecord
func importTranscript(from url: URL, type: MeetingType) async throws -> MeetingRecord
func importAudio(from url: URL, type: MeetingType, whisperService: WhisperService,
                 onProgress: (Double, String) -> Void) async throws -> MeetingRecord
func saveNotes(_ notes: String, for record: MeetingRecord) async throws
func delete(_ record: MeetingRecord) throws
func transcriptText(for record: MeetingRecord) throws -> String
func notesText(for record: MeetingRecord) throws -> String?
func applyRetentionPolicy()  // called at init + after each save
```

Retention policy: sorts by `createdAt`, deletes meetings beyond `meetingRetentionCount` limit OR older than `meetingRetentionDays`. Calls `delete()` for each.

---

### Phase 3 — Audio File Import Service

**New file: `Sources/LookMaNoHands/Services/AudioFileImporter.swift`**

Decodes audio using `AVAssetReader` requesting 16kHz mono Linear PCM directly (matching Whisper's required format). Operates in streaming fashion — yields 30-second chunks (480,000 samples) directly to transcription to avoid loading large files fully into memory.

Supported formats (via `NSOpenPanel` filter):
`UTType` for: `.wav`, `.aiff`, `.mp3`, `.mpeg4Audio`, `com.apple.m4a-audio`

Transcription: calls `WhisperService.transcribe(samples: [Float], initialPrompt: String?)` per 30s chunk, collecting returned `String` results into `TranscriptSegment` structs with corrected time offsets.

**Concurrency safety**: `WhisperService` is single-instance and non-reentrant. The UI prevents overlap via:
- Library tab disables "Import Audio..." when `MeetingStore.isRecording == true`
- Record tab disables recording start when `MeetingStore.isImportingAudio == true`

---

### Phase 4 — View Decomposition

> **Design requirement**: Before writing any new SwiftUI view, invoke the `swiftui-expert-skill` and `macos-app-design` skills to ensure each tab follows native macOS patterns, proper state management, and Liquid Glass/macOS Tahoe design conventions. These skills should be consulted at the start of each view file, not after the fact.

**New file: `Sources/LookMaNoHands/Views/MeetingRecordTab.swift`**
Extracted from current `MeetingView.swift`. Owns:
- `@State private var meetingState: LiveMeetingState` (renamed from `MeetingState`)
- `MixedAudioRecorder` + `ContinuousTranscriber` instances (private)
- Meeting type picker (user sets type *before* recording starts — affects auto-title)
- Recording controls, waveform, timer, live transcript, clear/confirm

Key change from current: after `stopRecording()` completes, call a closure:
```swift
var onRecordingFinished: (MeetingRecord) -> Void
```
which triggers auto-save via `MeetingStore` and navigates parent to Analyze tab.

**New file: `Sources/LookMaNoHands/Views/MeetingLibraryTab.swift`**
Reads from `MeetingStore` passed from parent. UI:
- Toolbar: search field + MeetingType filter picker + date range filter
- Scrollable list of `MeetingLibraryRow` items (date, type badge, duration, transcript preview, notes indicator)
- Per-row contextual menu: Delete, Export Transcript, Export Notes
- Import buttons: "Import Transcript..." (plain text / .md / .srt) and "Import Audio..." (shows progress sheet during transcription)
- Storage settings section: retention policy pickers (days + count)
- Empty state view when no meetings
- Selection calls `onMeetingSelected: (MeetingRecord) -> Void` → parent switches to Analyze tab

SRT import: simple line parser (~30 lines) strips sequence numbers and timestamps, extracts text content only.

**New file: `Sources/LookMaNoHands/Views/MeetingAnalyzeTab.swift`**
Layout:
- Empty state when `selectedMeeting == nil`: "Select a meeting from the Library tab"
- Header: editable inline title + `MeetingType` picker
- Prompt area (expandable): `TextEditor` pre-filled from `Settings.meetingTypePrompts[type] ?? type.defaultPrompt`; "Reset to default" button; confirmation dialog if user has edited and changes type
- "Process with Ollama" / "Cancel" button + progress bar
- Transcript section (collapsible, read-only)
- Notes section (streams during generation, persists after)
- Export bar: Copy Notes, Save Notes..., Copy Transcript

On "Process":
1. Save edited prompt to `Settings.shared.meetingTypePrompts[type.rawValue]` (persists as new default for that type)
2. Call `meetingAnalyzer.analyzeMeetingStreaming(transcript:customPrompt:onProgress:)` — no changes to `MeetingAnalyzer.swift` needed
3. On completion, call `store.saveNotes(notes, for: record)`

**Replace: `Sources/LookMaNoHands/Views/MeetingView.swift`**
Becomes a thin container:
```swift
struct MeetingView: View {
    let whisperService: WhisperService
    let recordingIndicator: RecordingIndicatorWindowController?
    weak var appDelegate: AppDelegate?

    @State private var store = MeetingStore()
    @State private var selectedTab: MeetingTab = .record   // always starts on Record
    @State private var selectedMeeting: MeetingRecord?
    @State private var meetingAnalyzer = MeetingAnalyzer()
}
enum MeetingTab { case record, library, analyze }
```
Window title changes from "Look Ma No Hands - Meeting Transcription" → "Meetings".

**Rename in-place: `MeetingState` → `LiveMeetingState`**
Move to `Sources/LookMaNoHands/Models/LiveMeetingState.swift`. No functional changes — it manages only in-flight recording state, not persistence.

---

### Phase 5 — Integration

**Modify: `Sources/LookMaNoHands/App/AppDelegate.swift`**
- `openMeetingTranscription()` — update window title only; no structural changes
- `isMeetingRecording` flag mechanism — unchanged; `MeetingRecordTab` still sets `appDelegate?.isMeetingRecording`
- `windowShouldClose` guard — unchanged

---

## Build Order

```
1. MeetingType.swift              (new — no deps)
2. MeetingRecord.swift            (new — depends on MeetingType)
3. Settings.swift                 (modify — add 3 properties)
4. AudioFileImporter.swift        (new — depends on WhisperService)
5. MeetingStore.swift             (new — depends on MeetingRecord, AudioFileImporter)
6. LiveMeetingState.swift         (rename/extract from MeetingView.swift)
7. MeetingRecordTab.swift         (new — extract from MeetingView)
8. MeetingLibraryTab.swift        (new — depends on MeetingStore)
9. MeetingAnalyzeTab.swift        (new — depends on MeetingStore, MeetingAnalyzer)
10. MeetingView.swift             (replace entirely — depends on all tabs)
11. AppDelegate.swift             (minor update — window title)
```
The existing `MeetingView.swift` stays intact through steps 1–6 — the first build break happens at step 7.

---

## Data Migration
None required. Current transcripts are in-memory only, nothing to migrate. Library starts empty on first launch — expected behavior.

The old `Settings.meetingPrompt` string key is preserved as-is. `MeetingType.general` resolves to `Settings.defaultMeetingPrompt` (same value), and user edits to the general type's prompt get stored in `meetingTypePrompts["general"]` on first use.

---

## Critical Files

| File | Change |
|------|--------|
| `Views/MeetingView.swift` | Replace entirely — source of extraction for all sub-views |
| `Services/WhisperService.swift` | Read-only reference — `transcribe(samples:[Float], initialPrompt:)` is the integration point for `AudioFileImporter` |
| `Models/Settings.swift` | Add 3 new `@Published` properties following existing pattern |
| `App/AppDelegate.swift` | Window title update + `openMeetingTranscription()` constructor args |
| `Services/MeetingAnalyzer.swift` | No changes needed — `analyzeMeetingStreaming(transcript:customPrompt:onProgress:)` is called as-is |

---

## Verification

1. **Build**: `swift build -c release` — must compile with no errors
2. **Record tab**: Open Meetings window → Record tab → start/stop recording → confirm meeting appears in Library tab automatically
3. **Library tab**: Confirm meeting shows title, type badge, duration, segment count; select it → switches to Analyze tab
4. **Import transcript**: Library → Import Transcript... → select a .txt file → appears in Library
5. **Import audio**: Library → Import Audio... → select an .m4a → progress sheet appears → transcription completes → appears in Library
6. **Analyze tab**: Select meeting → change meeting type → prompt updates → click Process → notes stream in → notes persist in Library row after completion
7. **Retention policy**: Set retention to 1 day → relaunch app → old meetings deleted
8. **Concurrency guard**: Start recording → verify "Import Audio..." is disabled
