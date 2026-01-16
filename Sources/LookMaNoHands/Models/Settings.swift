import Foundation

/// Available trigger keys for starting/stopping recording
enum TriggerKey: String, CaseIterable, Identifiable {
    case capsLock = "Caps Lock"
    case rightOption = "Right Option"
    case fn = "Fn (Double-tap)"
    
    var id: String { rawValue }
}

/// Available Whisper model sizes
enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (75MB, fastest)"
        case .base: return "Base (150MB, balanced)"
        case .small: return "Small (500MB, better)"
        case .medium: return "Medium (1.5GB, best)"
        }
    }

    var modelFileName: String {
        "ggml-\(rawValue).bin"
    }
}

/// Recording indicator position
enum IndicatorPosition: String, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"

    var id: String { rawValue }
}

/// User preferences and settings
/// Persisted to UserDefaults
class Settings: ObservableObject {

    // MARK: - Singleton

    static let shared = Settings()

    // MARK: - Default Values

    static let defaultMeetingPrompt = """
You are a professional meeting assistant. Your task is to transform a raw meeting transcription into a clear, actionable document that helps participants stay productive after the meeting.

## Instructions

Analyze the transcription below and produce a structured summary following this exact format. Be concise but thorough. Extract only what was actually discussed—do not invent or assume information.

---

## Output Format

### Meeting Overview
- **Date/Time**: [Extract if mentioned, otherwise write "Not specified"]
- **Participants**: [List all speakers identified in the transcription]
- **Meeting Purpose**: [One sentence describing the main topic or goal]

### Key Decisions Made
List each decision that was clearly agreed upon during the meeting. If no decisions were made, write "No decisions were finalized."

Format each as:
- **Decision**: [What was decided]
- **Context**: [Brief background on why this decision was made]

### Action Items
List every task, assignment, or commitment mentioned. This is the most critical section.

Format each as:
| Task | Owner | Deadline | Notes |
|------|-------|----------|-------|
| [Specific task description] | [Person responsible, or "Unassigned"] | [Due date, or "Not specified"] | [Any relevant details] |

### Discussion Summary
Summarize the main topics discussed in 3-5 bullet points. Focus on substance, not small talk or tangents. Each bullet should capture a complete thought.

### Open Questions & Unresolved Items
List any questions raised but not answered, disagreements not resolved, or topics that need further discussion.

Format each as:
- **Question/Issue**: [Description]
- **Why it matters**: [Brief context]

### Follow-Up Required
List any items that require action before the next meeting or that were explicitly marked for follow-up.

### Next Steps
If a follow-up meeting or next steps were discussed, describe them here. If not mentioned, write "No next steps were explicitly discussed."

---

## Processing Rules

1. **Speaker Attribution**: When someone commits to a task or makes a decision, always attribute it to them by name if identifiable.

2. **Handle Transcription Noise**: Ignore filler words (um, uh, like), false starts, and crosstalk. Focus on the meaningful content.

3. **Be Precise with Action Items**: Only list something as an action item if someone clearly committed to doing it or was assigned to do it. Do not infer tasks that weren't explicitly discussed.

4. **Preserve Important Details**: If specific numbers, dates, names, or technical terms were mentioned, include them exactly as stated.

5. **Flag Uncertainty**: If the transcription is unclear about who said something or what was meant, note this with [unclear] rather than guessing.

6. **Keep It Scannable**: Use short sentences. Busy professionals should be able to extract value in under 2 minutes of reading.
"""

    // MARK: - Keys
    
    private enum Keys {
        static let triggerKey = "triggerKey"
        static let whisperModel = "whisperModel"
        static let ollamaModel = "ollamaModel"
        static let meetingPrompt = "meetingPrompt"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        // Note: enableFormatting removed - formatting is always enabled for dictation
        // Ollama integration reserved for future meeting transcription feature
        static let showIndicator = "showIndicator"
        static let indicatorPosition = "indicatorPosition"
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

    /// Whether the user has completed the onboarding wizard
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
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
            self.indicatorPosition = .top
        }

        // Onboarding completion defaults to false for new users
        if UserDefaults.standard.object(forKey: Keys.hasCompletedOnboarding) != nil {
            self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        } else {
            self.hasCompletedOnboarding = false
        }
    }
    
    // MARK: - Methods
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        triggerKey = .capsLock
        whisperModel = .base
        ollamaModel = "qwen3:8b"
        meetingPrompt = Settings.defaultMeetingPrompt
        showIndicator = true
        indicatorPosition = .top
    }
}
