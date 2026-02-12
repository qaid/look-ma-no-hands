import Foundation

/// Available trigger keys for starting/stopping recording
enum TriggerKey: String, CaseIterable, Identifiable {
    case capsLock = "Caps Lock"
    case rightOption = "Right Option"
    case fn = "Fn (Double-tap)"
    case custom = "Custom..."

    var id: String { rawValue }

    /// Get the Hotkey for this trigger key
    func toHotkey(customHotkey: Hotkey?) -> Hotkey? {
        switch self {
        case .capsLock: return .capsLock
        case .rightOption: return .rightOption
        case .fn: return .fn
        case .custom: return customHotkey
        }
    }
}

/// Notification posted when hotkey configuration changes
extension Notification.Name {
    static let hotkeyConfigurationChanged = Notification.Name("hotkeyConfigurationChanged")
    static let hotkeyEnabledChanged = Notification.Name("hotkeyEnabledChanged")
    static let toggleShortcutChanged = Notification.Name("toggleShortcutChanged")
}

/// Available Whisper model sizes (WhisperKit format)
enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3turbo = "large-v3-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (fastest, lowest accuracy)"
        case .base: return "Base (balanced)"
        case .small: return "Small (better accuracy)"
        case .medium: return "Medium (high accuracy)"
        case .largev3turbo: return "Large v3 Turbo (best accuracy, recommended)"
        }
    }
}

/// A custom vocabulary entry for biasing Whisper and post-transcription replacement
struct VocabularyEntry: Codable, Identifiable, Hashable {
    let id: UUID
    /// What Whisper tends to produce (e.g. "swift ui"). Blank = prompt-bias only.
    var phrase: String
    /// Correct form (e.g. "SwiftUI"). Used for both prompt biasing and replacement.
    var replacement: String
    /// Whether this entry is active
    var enabled: Bool

    init(id: UUID = UUID(), phrase: String = "", replacement: String = "", enabled: Bool = true) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement
        self.enabled = enabled
    }
}

/// Recording indicator position
enum IndicatorPosition: String, CaseIterable, Identifiable {
    case followCursor = "Follow Cursor"
    case top = "Top"
    case bottom = "Bottom"

    var id: String { rawValue }
}

/// Appearance theme for the recording indicator
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

/// User preferences and settings
/// Persisted to UserDefaults
class Settings: ObservableObject {

    // MARK: - Singleton

    static let shared = Settings()

    // MARK: - Default Values

    static let defaultMeetingPrompt = """
/no_think

Role: You are an expert Technical Project Manager and Executive Assistant. Your task is to transform a raw meeting transcript into a clean, organized, and highly actionable document that helps participants stay productive.

## Core Processing Rules

Before generating output, apply these rules to the transcript:

1. **Filter Noise**: Ignore small talk, filler words (um, uh, like, you know), false starts, and irrelevant tangents. Focus only on business value, decisions, and technical substance.

2. **Group by Theme**: Do NOT summarize in the order things were discussed. Instead, group related points under logical themes.

3. **Capture Technical Specifics**: When tools, software, workflows, code, configurations, or methodologies are mentioned, preserve exact names and details.

4. **Identify All Actions**: Look for both explicit commitments ("I will do X by Friday") and implied tasks ("someone should look into Y"). Always assign an owner when identifiable.

5. **Attribute Carefully**: When someone makes a decision or commitment, connect it to their name. If the speaker is unclear, mark it as [Speaker Unclear].

6. **Never Invent**: Only include information actually present in the transcript. If something is ambiguous, note it as [Unclear] rather than guessing.

---

## Required Output Format

Generate the following sections in this exact order using Markdown formatting:

---

# Meeting Notes: [Main Topic]
**Date**: [Extract from transcript or write "Not specified"]  
**Participants**: [List all identifiable speakers]

---

## Executive Summary

Write a concise 3-5 sentence paragraph that answers:
- What was this meeting about?
- What was the most significant decision or outcome?
- What is the immediate next priority?

---

## Key Discussion Points

Create 3-5 thematic sections based on what was discussed. Use headers that describe the theme (not generic labels).

Good header examples:
- "Database Migration Approach"
- "Customer Onboarding Concerns"
- "Q2 Budget Constraints"

Bad header examples:
- "Discussion Point 1"
- "Topic A"
- "Miscellaneous"

Under each theme:
- Use bullet points to detail the discussion
- **Bold** key terms, tool names, and important figures
- Keep each bullet to 1-2 sentences maximum

---

## Decisions Made

List each decision that was clearly agreed upon. If no decisions were finalized, write "No decisions were finalized during this meeting."

Format:
- **Decision**: [What was decided]
- **Rationale**: [Why, if discussed]
- **Owner**: [Who is responsible for executing, if identified]

---

## Action Items

Present all tasks and commitments in this table format:

| Priority | Owner | Action Item | Deadline | Context |
|----------|-------|-------------|----------|---------|
| [High/Medium/Low or "—" if unclear] | [Name or "Unassigned"] | [Specific task] | [Date or "Not specified"] | [Brief relevant detail] |

Priority Guide:
- **High**: Blocking other work, or deadline within 48 hours
- **Medium**: Important but not immediately blocking
- **Low**: Nice-to-have or long-term task

---

## Open Questions

List any questions raised but not answered, disagreements not resolved, or items needing further discussion.

Format:
- **Question**: [The unresolved item]
- **Why It Matters**: [Impact if not resolved]
- **Suggested Next Step**: [How to resolve, if discussed]

If none, write "No open questions remain from this meeting."

---

## Notable Quotes

Extract 2-3 verbatim quotes that capture:
- A major decision rationale
- A key insight or realization
- The overall sentiment or tone

Format:
> "[Exact quote]"  
> — [Speaker name], regarding [brief context]

If the transcript quality makes verbatim quotes unreliable, write "Transcript quality insufficient for reliable quote extraction."

---

## Follow-Up Meeting

If a follow-up was scheduled or suggested, note:
- **When**: [Date/time]
- **Purpose**: [What will be covered]
- **Preparation Required**: [What participants should do before]

If not discussed, write "No follow-up meeting was scheduled."

---

## Transcript to Process

[TRANSCRIPTION_PLACEHOLDER]

---

Now produce the complete meeting notes following the format above. Ensure every section is included, even if the content is "None identified" or "Not discussed."
"""

    // MARK: - Keys

    private enum Keys {
        static let triggerKey = "triggerKey"
        static let customHotkey = "customHotkey"
        static let whisperModel = "whisperModel"
        static let ollamaModel = "ollamaModel"
        static let meetingPrompt = "meetingPrompt"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        // Note: enableFormatting removed - formatting is always enabled for dictation
        // Ollama integration reserved for future meeting transcription feature
        static let showIndicator = "showIndicator"
        static let indicatorPosition = "indicatorPosition"
        static let appearanceTheme = "appearanceTheme"
        static let showLaunchConfirmation = "showLaunchConfirmation"
        static let customVocabulary = "customVocabulary" // Legacy UserDefaults key (for migration)
        static let checkForUpdatesOnLaunch = "checkForUpdatesOnLaunch"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let pauseMediaDuringDictation = "pauseMediaDuringDictation"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let toggleHotkeyShortcut = "toggleHotkeyShortcut"
    }

    // MARK: - File Paths

    /// Get the Application Support directory for persistent storage
    private static func getApplicationSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("LookMaNoHands")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir
    }

    /// Path to the vocabulary JSON file in Application Support
    private static var vocabularyFileURL: URL {
        getApplicationSupportDirectory().appendingPathComponent("vocabulary.json")
    }

    /// Path to the toggle hotkey JSON file in Application Support
    private static var toggleHotkeyFileURL: URL {
        getApplicationSupportDirectory().appendingPathComponent("toggleHotkey.json")
    }

    // MARK: - Audio Device Manager

    /// Manager for audio input devices
    let audioDeviceManager = AudioDeviceManager()

    // MARK: - Published Properties

    /// The key used to trigger recording
    @Published var triggerKey: TriggerKey {
        didSet {
            UserDefaults.standard.set(triggerKey.rawValue, forKey: Keys.triggerKey)
        }
    }

    /// Custom hotkey when triggerKey is .custom
    @Published var customHotkey: Hotkey? {
        didSet {
            if let hotkey = customHotkey {
                if let data = try? JSONEncoder().encode(hotkey) {
                    UserDefaults.standard.set(data, forKey: Keys.customHotkey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.customHotkey)
            }
        }
    }

    /// Get the effective hotkey based on current settings
    var effectiveHotkey: Hotkey {
        triggerKey.toHotkey(customHotkey: customHotkey) ?? .capsLock
    }
    
    /// The Whisper model to use for transcription
    @Published var whisperModel: WhisperModel {
        didSet {
            UserDefaults.standard.set(whisperModel.rawValue, forKey: Keys.whisperModel)
        }
    }
    
    /// The Ollama model to use for formatting (reserved for meeting transcription)
    @Published var ollamaModel: String {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel)
        }
    }

    /// Custom prompt for meeting notes processing
    @Published var meetingPrompt: String {
        didSet {
            UserDefaults.standard.set(meetingPrompt, forKey: Keys.meetingPrompt)
        }
    }

    /// Whether to show the floating recording indicator
    @Published var showIndicator: Bool {
        didSet {
            UserDefaults.standard.set(showIndicator, forKey: Keys.showIndicator)
        }
    }

    /// Position of the recording indicator (top or bottom of screen)
    @Published var indicatorPosition: IndicatorPosition {
        didSet {
            UserDefaults.standard.set(indicatorPosition.rawValue, forKey: Keys.indicatorPosition)
        }
    }

    /// Appearance theme for the recording indicator
    @Published var appearanceTheme: AppearanceTheme {
        didSet {
            UserDefaults.standard.set(appearanceTheme.rawValue, forKey: Keys.appearanceTheme)
        }
    }

    /// Whether the user has completed the onboarding wizard
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// Whether to show launch confirmation splash screen
    @Published var showLaunchConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(showLaunchConfirmation, forKey: Keys.showLaunchConfirmation)
        }
    }

    /// Custom vocabulary entries for Whisper prompt biasing and post-transcription replacement
    /// Stored in Application Support for persistence across reinstalls
    @Published var customVocabulary: [VocabularyEntry] {
        didSet {
            saveVocabularyToFile()
        }
    }

    /// Whether to automatically check for updates on launch (opt-in, default off)
    @Published var checkForUpdatesOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(checkForUpdatesOnLaunch, forKey: Keys.checkForUpdatesOnLaunch)
        }
    }

    /// Whether to automatically pause media playback when dictation starts
    @Published var pauseMediaDuringDictation: Bool {
        didSet {
            UserDefaults.standard.set(pauseMediaDuringDictation, forKey: Keys.pauseMediaDuringDictation)
        }
    }

    /// Whether dictation hotkey monitoring is enabled
    @Published var hotkeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled)
            NotificationCenter.default.post(name: .hotkeyEnabledChanged, object: nil)
        }
    }

    /// Global shortcut to toggle hotkey enabled/disabled state
    @Published var toggleHotkeyShortcut: Hotkey? {
        didSet {
            saveToggleHotkeyToFile()
            NotificationCenter.default.post(name: .toggleShortcutChanged, object: nil)
        }
    }

    /// Date of the last successful update check
    var lastUpdateCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastUpdateCheckDate) as? Date }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date, forKey: Keys.lastUpdateCheckDate)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastUpdateCheckDate)
            }
        }
    }

    // MARK: - Initialization
    
    private init() {
        // Load saved values or use defaults
        
        if let savedTriggerKey = UserDefaults.standard.string(forKey: Keys.triggerKey),
           let key = TriggerKey(rawValue: savedTriggerKey) {
            self.triggerKey = key
        } else {
            self.triggerKey = .capsLock
        }

        // Load custom hotkey if saved
        if let hotkeyData = UserDefaults.standard.data(forKey: Keys.customHotkey),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: hotkeyData) {
            self.customHotkey = hotkey
        } else {
            self.customHotkey = nil
        }

        if let savedWhisperModel = UserDefaults.standard.string(forKey: Keys.whisperModel),
           let model = WhisperModel(rawValue: savedWhisperModel) {
            self.whisperModel = model
        } else {
            self.whisperModel = .base
        }
        
        self.ollamaModel = UserDefaults.standard.string(forKey: Keys.ollamaModel) ?? "qwen3:8b"

        self.meetingPrompt = UserDefaults.standard.string(forKey: Keys.meetingPrompt) ?? Settings.defaultMeetingPrompt

        if UserDefaults.standard.object(forKey: Keys.showIndicator) != nil {
            self.showIndicator = UserDefaults.standard.bool(forKey: Keys.showIndicator)
        } else {
            self.showIndicator = true
        }

        if let savedPosition = UserDefaults.standard.string(forKey: Keys.indicatorPosition),
           let position = IndicatorPosition(rawValue: savedPosition) {
            self.indicatorPosition = position
        } else {
            self.indicatorPosition = .followCursor  // Default to follow cursor
        }

        if let savedTheme = UserDefaults.standard.string(forKey: Keys.appearanceTheme),
           let theme = AppearanceTheme(rawValue: savedTheme) {
            self.appearanceTheme = theme
        } else {
            self.appearanceTheme = .system  // Default to system theme
        }

        // Launch confirmation defaults to true (enabled by default)
        if UserDefaults.standard.object(forKey: Keys.showLaunchConfirmation) != nil {
            self.showLaunchConfirmation = UserDefaults.standard.bool(forKey: Keys.showLaunchConfirmation)
        } else {
            self.showLaunchConfirmation = true
        }

        // Load custom vocabulary from file (with migration from UserDefaults if needed)
        self.customVocabulary = Self.loadVocabularyFromFile()

        // Auto-update check defaults to false (opt-in)
        if UserDefaults.standard.object(forKey: Keys.checkForUpdatesOnLaunch) != nil {
            self.checkForUpdatesOnLaunch = UserDefaults.standard.bool(forKey: Keys.checkForUpdatesOnLaunch)
        } else {
            self.checkForUpdatesOnLaunch = false
        }

        // Pause media during dictation defaults to true (enabled by default)
        if UserDefaults.standard.object(forKey: Keys.pauseMediaDuringDictation) != nil {
            self.pauseMediaDuringDictation = UserDefaults.standard.bool(forKey: Keys.pauseMediaDuringDictation)
        } else {
            self.pauseMediaDuringDictation = true
        }

        // Hotkey enabled defaults to true (enabled by default)
        if UserDefaults.standard.object(forKey: Keys.hotkeyEnabled) != nil {
            self.hotkeyEnabled = UserDefaults.standard.bool(forKey: Keys.hotkeyEnabled)
        } else {
            self.hotkeyEnabled = true
        }

        // Onboarding completion defaults to false for new users
        if UserDefaults.standard.object(forKey: Keys.hasCompletedOnboarding) != nil {
            self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
            NSLog("📖 Settings: Loaded hasCompletedOnboarding from UserDefaults: %@", self.hasCompletedOnboarding ? "true" : "false")
        } else {
            self.hasCompletedOnboarding = false
            NSLog("📖 Settings: No saved onboarding status - defaulting to false (first launch)")
        }

        // Toggle shortcut defaults to Cmd+Shift+D (keyCode 2 = D)
        self.toggleHotkeyShortcut = Self.loadToggleHotkeyFromFile()

        if self.toggleHotkeyShortcut != nil {
            NSLog("🔧 Settings: Loaded toggle hotkey from file")
        } else {
            NSLog("🔧 Settings: No saved toggle hotkey - defaulting to Cmd+Shift+D")
            self.toggleHotkeyShortcut = Hotkey(keyCode: 2, modifiers: .init(command: true, shift: true))
        }
    }
    
    // MARK: - Methods

    /// Load custom vocabulary from Application Support directory
    /// Migrates from UserDefaults if file doesn't exist yet
    private static func loadVocabularyFromFile() -> [VocabularyEntry] {
        let fileURL = vocabularyFileURL

        // Try loading from file first
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let vocabulary = try JSONDecoder().decode([VocabularyEntry].self, from: data)
                NSLog("📚 Loaded \(vocabulary.count) vocabulary entries from \(fileURL.path)")
                return vocabulary
            } catch {
                NSLog("⚠️ Failed to load vocabulary from file: \(error.localizedDescription)")
            }
        }

        // Migration: Check UserDefaults for legacy data
        if let vocabData = UserDefaults.standard.data(forKey: Keys.customVocabulary),
           let vocab = try? JSONDecoder().decode([VocabularyEntry].self, from: vocabData) {
            NSLog("🔄 Migrating \(vocab.count) vocabulary entries from UserDefaults to file")

            // Save to file
            if let data = try? JSONEncoder().encode(vocab) {
                try? data.write(to: fileURL, options: .atomic)
                NSLog("✅ Migration complete: vocabulary saved to \(fileURL.path)")
            }

            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: Keys.customVocabulary)

            return vocab
        }

        NSLog("📚 No existing vocabulary found, starting with empty list")
        return []
    }

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

    /// Save custom vocabulary to Application Support directory
    private func saveVocabularyToFile() {
        let fileURL = Self.vocabularyFileURL

        do {
            let data = try JSONEncoder().encode(customVocabulary)
            try data.write(to: fileURL, options: .atomic)
            NSLog("💾 Saved \(customVocabulary.count) vocabulary entries to \(fileURL.path)")
        } catch {
            NSLog("❌ Failed to save vocabulary to file: \(error.localizedDescription)")
        }
    }

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

    /// Reset all settings to defaults
    func resetToDefaults() {
        triggerKey = .capsLock
        customHotkey = nil
        whisperModel = .base
        ollamaModel = "qwen3:8b"
        meetingPrompt = Settings.defaultMeetingPrompt
        showIndicator = true
        indicatorPosition = .followCursor
        appearanceTheme = .system
        showLaunchConfirmation = true
        customVocabulary = []
        checkForUpdatesOnLaunch = false
        lastUpdateCheckDate = nil
        pauseMediaDuringDictation = true
        hotkeyEnabled = true
        toggleHotkeyShortcut = Hotkey(keyCode: 2, modifiers: .init(command: true, shift: true))
    }
}
