import XCTest
@testable import LookMaNoHands

final class WhisperDictationTests: XCTestCase {
    
    func testTranscriptionStateInitialState() {
        let state = TranscriptionState()
        XCTAssertEqual(state.recordingState, .idle)
        XCTAssertNil(state.rawTranscription)
        XCTAssertNil(state.formattedText)
    }
    
    func testTranscriptionStateTransitions() {
        let state = TranscriptionState()
        
        // Start recording
        state.startRecording()
        XCTAssertEqual(state.recordingState, .recording)
        XCTAssertTrue(state.isRecording)
        
        // Stop recording
        state.stopRecording()
        XCTAssertEqual(state.recordingState, .processing)
        XCTAssertTrue(state.isProcessing)
        
        // Complete processing
        state.completeProcessing()
        XCTAssertEqual(state.recordingState, .idle)
    }
    
    func testSettingsDefaults() {
        let settings = Settings.shared
        // After reset, should have default values
        settings.resetToDefaults()
        
        XCTAssertEqual(settings.triggerKey, .capsLock)
        XCTAssertEqual(settings.whisperModel, .base)
        XCTAssertTrue(settings.enableFormatting)
        XCTAssertTrue(settings.showIndicator)
    }
    
    // TODO: Add more tests as implementation progresses
}
