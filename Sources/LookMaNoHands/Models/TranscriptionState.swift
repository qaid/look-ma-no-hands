import Foundation
import SwiftUI

/// Audio source for recording
enum AudioSource: String, Equatable {
    case microphone = "Microphone"
    case systemAudio = "System Audio"
}

/// Represents the current state of the recording/transcription process
enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording..."
        case .processing:
            return "Processing..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

/// Central state management for the transcription pipeline
/// Observable so SwiftUI views can react to changes
@Observable
class TranscriptionState {
    
    // MARK: - State Properties
    
    /// Current recording state
    var recordingState: RecordingState = .idle
    
    /// The raw transcription from Whisper (before formatting)
    var rawTranscription: String?
    
    /// The formatted text (after LLM processing)
    var formattedText: String?
    
    /// Whether Ollama is available for formatting
    var isOllamaAvailable: Bool = false
    
    /// Whether microphone permission is granted
    var hasMicrophonePermission: Bool = false
    
    /// Whether accessibility permission is granted
    var hasAccessibilityPermission: Bool = false

    /// Whether screen recording permission is granted (for system audio capture)
    var hasScreenRecordingPermission: Bool = false

    /// Current audio source being used
    var audioSource: AudioSource = .microphone

    // MARK: - Computed Properties
    
    /// Whether we're currently in a recording session
    var isRecording: Bool {
        recordingState == .recording
    }
    
    /// Whether we're currently processing (transcribing or formatting)
    var isProcessing: Bool {
        recordingState == .processing
    }
    
    /// Whether we have all required permissions
    var hasAllPermissions: Bool {
        hasMicrophonePermission && hasAccessibilityPermission
    }
    
    /// The final text to insert (formatted if available, raw otherwise)
    var textToInsert: String? {
        formattedText ?? rawTranscription
    }
    
    // MARK: - State Transitions
    
    /// Start a new recording session
    func startRecording() {
        guard recordingState == .idle else { return }
        recordingState = .recording
        rawTranscription = nil
        formattedText = nil
    }
    
    /// Stop recording and begin processing
    func stopRecording() {
        guard recordingState == .recording else { return }
        recordingState = .processing
    }
    
    /// Set the raw transcription result
    func setTranscription(_ text: String) {
        rawTranscription = text
    }
    
    /// Set the formatted text result
    func setFormattedText(_ text: String) {
        formattedText = text
    }
    
    /// Mark processing as complete, return to idle
    func completeProcessing() {
        recordingState = .idle
    }
    
    /// Set an error state
    func setError(_ message: String) {
        recordingState = .error(message)
    }
    
    /// Reset to idle state, clearing any error
    func reset() {
        recordingState = .idle
        rawTranscription = nil
        formattedText = nil
    }
}
