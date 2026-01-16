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
