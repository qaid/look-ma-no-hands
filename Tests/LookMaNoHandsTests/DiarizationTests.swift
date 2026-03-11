import XCTest
@testable import LookMaNoHands

// MARK: - MixedAudioRecorder source classification

@available(macOS 13.0, *)
final class DiarizationSourceClassificationTests: XCTestCase {

    func testMicDominant() {
        let result = MixedAudioRecorder.classifySource(micRMS: 0.5, systemRMS: 0.1)
        XCTAssertEqual(result, .local)
    }

    func testSystemDominant() {
        let result = MixedAudioRecorder.classifySource(micRMS: 0.1, systemRMS: 0.5)
        XCTAssertEqual(result, .remote)
    }

    func testBothEqualReturnsMixed() {
        let result = MixedAudioRecorder.classifySource(micRMS: 0.3, systemRMS: 0.3)
        XCTAssertEqual(result, .mixed)
    }

    func testBothSilentReturnsMixed() {
        let result = MixedAudioRecorder.classifySource(micRMS: 0.001, systemRMS: 0.001)
        XCTAssertEqual(result, .mixed)
    }

    func testMicSilentSystemActiveReturnsRemote() {
        let result = MixedAudioRecorder.classifySource(micRMS: 0.001, systemRMS: 0.3)
        XCTAssertEqual(result, .remote)
    }

    func testSystemSilentMicActiveReturnsLocal() {
        let result = MixedAudioRecorder.classifySource(micRMS: 0.3, systemRMS: 0.001)
        XCTAssertEqual(result, .local)
    }

    func testSlightlyLouderMicReturnsMixed() {
        // mic is 1.3x louder — below 1.5 dominanceRatio threshold
        let result = MixedAudioRecorder.classifySource(micRMS: 0.26, systemRMS: 0.2)
        XCTAssertEqual(result, .mixed)
    }

    func testComputeRMSEmpty() {
        XCTAssertEqual(MixedAudioRecorder.computeRMS([]), 0)
    }

    func testComputeRMSKnownValue() {
        // RMS of [1, 1, 1, 1] = 1.0
        let rms = MixedAudioRecorder.computeRMS([1, 1, 1, 1])
        XCTAssertEqual(rms, 1.0, accuracy: 0.001)
    }
}

// MARK: - ContinuousTranscriber pause detection

@available(macOS 13.0, *)
final class PauseDetectionTests: XCTestCase {

    private func makeTranscriber() -> ContinuousTranscriber {
        // We don't need a real WhisperService for pause detection tests
        ContinuousTranscriber(whisperService: WhisperService(), chunkDuration: 10)
    }

    private func makeSamples(sampleRate: Double = 16000, durationSec: Double, amplitude: Float) -> [Float] {
        let count = Int(durationSec * sampleRate)
        return [Float](repeating: amplitude, count: count)
    }

    func testSilenceChunkReturnsSinglePause() {
        let transcriber = makeTranscriber()
        // 2s silence followed by 1s speech then 1s silence
        let speech = makeSamples(durationSec: 1, amplitude: 0.5)
        let silence1 = makeSamples(durationSec: 2, amplitude: 0.0)
        let silence2 = makeSamples(durationSec: 1, amplitude: 0.0)
        let samples = silence1 + speech + silence2

        let offsets = transcriber.detectPauses(in: samples)
        // Only silence1 >= 500ms, silence2 is also >=500ms — expect at least 1 offset
        XCTAssertFalse(offsets.isEmpty)
    }

    func testShortPauseIgnored() {
        let transcriber = makeTranscriber()
        // 200ms silence — below 500ms threshold
        let speech1 = makeSamples(durationSec: 0.5, amplitude: 0.5)
        let shortSilence = makeSamples(durationSec: 0.2, amplitude: 0.0)
        let speech2 = makeSamples(durationSec: 0.5, amplitude: 0.5)
        let samples = speech1 + shortSilence + speech2

        let offsets = transcriber.detectPauses(in: samples)
        XCTAssertTrue(offsets.isEmpty, "Short pause should not produce an offset")
    }

    func testNoSilenceNoOffsets() {
        let transcriber = makeTranscriber()
        let samples = makeSamples(durationSec: 3, amplitude: 0.5)
        let offsets = transcriber.detectPauses(in: samples)
        XCTAssertTrue(offsets.isEmpty)
    }
}

// MARK: - MeetingStore buildMergedTranscript with source labels

@available(macOS 13.0, *)
final class MergedTranscriptDiarizationTests: XCTestCase {

    private func makeSegment(_ text: String, source: DiarizationSource = .unknown, at start: TimeInterval = 0) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: start + 5, timestamp: Date(), source: source)
    }

    func testUnknownSourceNoPrefix() {
        let seg = makeSegment("hello world")
        let transcript = MeetingStore.buildMergedTranscript(segments: [seg], userNotes: [])
        XCTAssertEqual(transcript, "hello world")
    }

    func testLocalSourceMePrefix() {
        let seg = makeSegment("hello everyone", source: .local)
        let transcript = MeetingStore.buildMergedTranscript(segments: [seg], userNotes: [])
        XCTAssertTrue(transcript.hasPrefix("[Me]"), "Local segment should be prefixed with [Me]")
    }

    func testRemoteSourceRemotePrefix() {
        let seg = makeSegment("hi there", source: .remote)
        let transcript = MeetingStore.buildMergedTranscript(segments: [seg], userNotes: [])
        XCTAssertTrue(transcript.hasPrefix("[Remote]"), "Remote segment should be prefixed with [Remote]")
    }

    func testMixedSourceRemotePrefix() {
        let seg = makeSegment("okay let's start", source: .mixed)
        let transcript = MeetingStore.buildMergedTranscript(segments: [seg], userNotes: [])
        XCTAssertTrue(transcript.hasPrefix("[Remote]"), "Mixed segment should be prefixed with [Remote]")
    }

    func testBackwardCompatMultipleUnknownSegments() {
        let segs = [
            makeSegment("first paragraph", at: 0),
            makeSegment("second paragraph", at: 5)
        ]
        let transcript = MeetingStore.buildMergedTranscript(segments: segs, userNotes: [])
        XCTAssertEqual(transcript, "first paragraph\n\nsecond paragraph")
        XCTAssertFalse(transcript.contains("[Me]"))
        XCTAssertFalse(transcript.contains("[Remote]"))
    }

    func testMixedSourcesInSameTranscript() {
        let segs = [
            makeSegment("my comment", source: .local, at: 0),
            makeSegment("your response", source: .remote, at: 5)
        ]
        let transcript = MeetingStore.buildMergedTranscript(segments: segs, userNotes: [])
        XCTAssertTrue(transcript.contains("[Me] my comment"))
        XCTAssertTrue(transcript.contains("[Remote] your response"))
    }
}

// MARK: - MeetingStore insertSpeakerChangeMarkers

@available(macOS 13.0, *)
final class SpeakerChangeMarkerTests: XCTestCase {

    func testNoChangesReturnsSameText() {
        let text = "hello world how are you"
        let result = MeetingStore.insertSpeakerChangeMarkers(text: text, changes: [], segmentDuration: 5)
        XCTAssertEqual(result, text)
    }

    func testSingleChangeInMiddle() {
        // Offset at midpoint of a 10s segment → inserts at ~50% word position
        let words = "one two three four five six seven eight nine ten"
        let result = MeetingStore.insertSpeakerChangeMarkers(text: words, changes: [5.0], segmentDuration: 10)
        XCTAssertTrue(result.contains("[SPEAKER_CHANGE]"), "Should contain a speaker change marker")
    }

    func testMultipleChanges() {
        let words = "a b c d e f g h i j"
        let result = MeetingStore.insertSpeakerChangeMarkers(text: words, changes: [2.0, 7.0], segmentDuration: 10)
        let count = result.components(separatedBy: "[SPEAKER_CHANGE]").count - 1
        XCTAssertGreaterThanOrEqual(count, 1, "Should have at least one speaker change marker")
    }

    func testEmptyTextReturnsEmpty() {
        let result = MeetingStore.insertSpeakerChangeMarkers(text: "", changes: [1.0], segmentDuration: 5)
        XCTAssertEqual(result, "")
    }

    func testSingleWordReturnsSingleWord() {
        let result = MeetingStore.insertSpeakerChangeMarkers(text: "hello", changes: [1.0], segmentDuration: 5)
        XCTAssertEqual(result, "hello")
    }
}

// MARK: - MeetingAnalyzer diarization suffix

@available(macOS 13.0, *)
final class MeetingAnalyzerDiarizationTests: XCTestCase {

    func testDiarizationSuffixAppendedWhenMePresent() {
        let transcript = "[Me] hello there\n[Remote] hi how are you"
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize this meeting.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertTrue(split.system.contains("SPEAKER DIARIZATION RULES"), "Diarization suffix should be appended")
    }

    func testDiarizationSuffixNotAppendedWithoutMarkers() {
        let transcript = "Alice said hello. Bob replied."
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize this meeting.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertFalse(split.system.contains("SPEAKER DIARIZATION RULES"), "Diarization suffix should not be appended")
    }

    func testBothNoteAndDiarizationSuffixesCoexist() {
        let transcript = "[Me] hello\n[USER NOTE @ 00:05] key point\n[Remote] bye"
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize this meeting.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertTrue(split.system.contains("USER NOTE"), "Note suffix should be appended")
        XCTAssertTrue(split.system.contains("SPEAKER DIARIZATION RULES"), "Diarization suffix should also be appended")
    }

    func testDiarizationSuffixAppendedWhenRemotePresent() {
        let transcript = "[Remote] let me explain the issue"
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertTrue(split.system.contains("SPEAKER DIARIZATION RULES"))
    }
}
