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
    
    // MARK: - Keys
    
    private enum Keys {
        static let triggerKey = "triggerKey"
        static let whisperModel = "whisperModel"
        static let ollamaModel = "ollamaModel"
        // Note: enableFormatting removed - formatting is always enabled for dictation
        // Ollama integration reserved for future meeting transcription feature
        static let showIndicator = "showIndicator"
        static let indicatorPosition = "indicatorPosition"
    }
    
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
        
        self.ollamaModel = UserDefaults.standard.string(forKey: Keys.ollamaModel) ?? "llama3.2:3b"

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
    }
    
    // MARK: - Methods
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        triggerKey = .capsLock
        whisperModel = .base
        ollamaModel = "llama3.2:3b"
        showIndicator = true
        indicatorPosition = .top
    }
}
