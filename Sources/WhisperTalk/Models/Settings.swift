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
        static let enableFormatting = "enableFormatting"
        static let showIndicator = "showIndicator"
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
    
    /// The Ollama model to use for formatting
    @Published var ollamaModel: String {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel)
        }
    }
    
    /// Whether to enable AI formatting (if false, use raw transcription)
    @Published var enableFormatting: Bool {
        didSet {
            UserDefaults.standard.set(enableFormatting, forKey: Keys.enableFormatting)
        }
    }
    
    /// Whether to show the floating recording indicator
    @Published var showIndicator: Bool {
        didSet {
            UserDefaults.standard.set(showIndicator, forKey: Keys.showIndicator)
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
        
        // Default to true if not set
        if UserDefaults.standard.object(forKey: Keys.enableFormatting) != nil {
            self.enableFormatting = UserDefaults.standard.bool(forKey: Keys.enableFormatting)
        } else {
            self.enableFormatting = true
        }
        
        if UserDefaults.standard.object(forKey: Keys.showIndicator) != nil {
            self.showIndicator = UserDefaults.standard.bool(forKey: Keys.showIndicator)
        } else {
            self.showIndicator = true
        }
    }
    
    // MARK: - Methods
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        triggerKey = .capsLock
        whisperModel = .base
        ollamaModel = "llama3.2:3b"
        enableFormatting = true
        showIndicator = true
    }
}
