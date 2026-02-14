import Foundation

/// Tracks progress through the onboarding wizard
@Observable
class OnboardingState {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case ollama = 1
        case whisperModel = 2
        case permissions = 3
        case complete = 4
    }

    var currentStep: Step = .welcome
    var isDownloadingModel: Bool = false
    var ollamaSkipped: Bool = false
    var selectedModel: WhisperModel = .tiny
    var modelDownloaded: Bool = false

    // Permission status (updated in real-time)
    var hasMicrophonePermission: Bool = false
    var hasAccessibilityPermission: Bool = false

    // Track if this is a permissions-only flow (skips to permissions step)
    var isPermissionsOnlyFlow: Bool = false

    func nextStep() {
        if let nextStep = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }

    func previousStep() {
        if let prevStep = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
        }
    }

    func canContinue() -> Bool {
        switch currentStep {
        case .welcome:
            return true
        case .ollama:
            return true // Can always skip Ollama
        case .whisperModel:
            return modelDownloaded // Must download model
        case .permissions:
            return true // Can continue without permissions (with warning)
        case .complete:
            return true
        }
    }
}
