import XCTest
@testable import LookMaNoHands

// MARK: - SpeakerDiarizationService label mapping

@available(macOS 13.0, *)
final class SpeakerLabelMappingTests: XCTestCase {

    func testSpeakerIdZeroMapsToA() {
        XCTAssertEqual(SpeakerDiarizationService.labelForSpeakerId(0), "Speaker A")
    }

    func testSpeakerIdOneMapsToB() {
        XCTAssertEqual(SpeakerDiarizationService.labelForSpeakerId(1), "Speaker B")
    }

    func testSpeakerIdTwentyFiveMapsToZ() {
        XCTAssertEqual(SpeakerDiarizationService.labelForSpeakerId(25), "Speaker Z")
    }

    func testSpeakerIdBeyondZUsesNumber() {
        XCTAssertEqual(SpeakerDiarizationService.labelForSpeakerId(26), "Speaker 27")
    }
}

// MARK: - SpeakerInfo label formatting

@available(macOS 13.0, *)
final class SpeakerInfoLabelTests: XCTestCase {

    func testSingleSpeakerLabel() {
        let label = SpeakerDiarizationService.labelForSpeakerInfo(.speakerId(2))
        XCTAssertEqual(label, "Speaker C")
    }

    func testMultipleSpeakersLabel() {
        let label = SpeakerDiarizationService.labelForSpeakerInfo(.multiple([0, 1]))
        XCTAssertEqual(label, "Speaker A & Speaker B")
    }

    func testNoMatchLabel() {
        let label = SpeakerDiarizationService.labelForSpeakerInfo(.noMatch)
        XCTAssertEqual(label, "Remote")
    }
}

// MARK: - buildMergedTranscript with speakerLabel

@available(macOS 13.0, *)
final class SpeakerLabelTranscriptTests: XCTestCase {

    func testSpeakerLabelUsedInMergedTranscript() {
        let seg = TranscriptSegment(
            text: "hello everyone",
            startTime: 0, endTime: 5,
            timestamp: Date(),
            source: .remote,
            speakerLabel: "Speaker A"
        )
        let transcript = MeetingStore.buildMergedTranscript(segments: [seg], userNotes: [])
        XCTAssertTrue(transcript.contains("[Speaker A] hello everyone"),
                       "Should use speakerLabel instead of [Mac OS]")
        XCTAssertFalse(transcript.contains("[Mac OS]"),
                        "Should not contain [Mac OS] when speakerLabel is set")
    }

    func testSpeakerLabelNilFallsBackToMacOS() {
        let seg = TranscriptSegment(
            text: "hi there",
            startTime: 0, endTime: 5,
            timestamp: Date(),
            source: .remote,
            speakerLabel: nil
        )
        let transcript = MeetingStore.buildMergedTranscript(segments: [seg], userNotes: [])
        XCTAssertTrue(transcript.hasPrefix("[Mac OS]"),
                       "Should fall back to [Mac OS] when speakerLabel is nil")
    }

    func testMixedSpeakerLabelsInTranscript() {
        let segs = [
            TranscriptSegment(text: "my turn", startTime: 0, endTime: 5, timestamp: Date(), source: .local),
            TranscriptSegment(text: "speaker a talks", startTime: 5, endTime: 10, timestamp: Date(), source: .remote, speakerLabel: "Speaker A"),
            TranscriptSegment(text: "speaker b talks", startTime: 10, endTime: 15, timestamp: Date(), source: .remote, speakerLabel: "Speaker B"),
        ]
        let transcript = MeetingStore.buildMergedTranscript(segments: segs, userNotes: [])
        XCTAssertTrue(transcript.contains("[Me] my turn"))
        XCTAssertTrue(transcript.contains("[Speaker A] speaker a talks"))
        XCTAssertTrue(transcript.contains("[Speaker B] speaker b talks"))
    }
}

// MARK: - Timeline grouping with speaker labels

@available(macOS 13.0, *)
final class SpeakerLabelGroupingTests: XCTestCase {

    func testDifferentSpeakerLabelsFormSeparateGroups() {
        let segA = TranscriptSegment(text: "a1", startTime: 0, endTime: 5, timestamp: Date(), source: .remote, speakerLabel: "Speaker A")
        let segB = TranscriptSegment(text: "b1", startTime: 5, endTime: 10, timestamp: Date(), source: .remote, speakerLabel: "Speaker B")

        let entries = TimelineEntry.merge(segments: [segA, segB], notes: [])
        let groups = TimelineEntry.grouped(entries)

        XCTAssertEqual(groups.count, 2, "Different speaker labels should form separate groups")
    }

    func testSameSpeakerLabelGroupsTogether() {
        let seg1 = TranscriptSegment(text: "a1", startTime: 0, endTime: 5, timestamp: Date(), source: .remote, speakerLabel: "Speaker A")
        let seg2 = TranscriptSegment(text: "a2", startTime: 5, endTime: 10, timestamp: Date(), source: .remote, speakerLabel: "Speaker A")

        let entries = TimelineEntry.merge(segments: [seg1, seg2], notes: [])
        let groups = TimelineEntry.grouped(entries)

        XCTAssertEqual(groups.count, 1, "Same speaker label should group together")
    }
}

// MARK: - MeetingAnalyzer SpeakerKit prompt suffix

@available(macOS 13.0, *)
final class SpeakerKitPromptTests: XCTestCase {

    func testSpeakerKitSuffixAppendedWhenSpeakerLabelsPresent() {
        let transcript = "[Me] hello\n[Speaker A] hi there\n[Speaker B] good morning"
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertTrue(split.system.contains("voice analysis"),
                       "SpeakerKit suffix should be used for [Speaker X] labels")
        XCTAssertFalse(split.system.contains("[SPEAKER_CHANGE]"),
                        "Legacy suffix should not be used when SpeakerKit labels present")
    }

    func testLegacySuffixUsedForMacOSLabels() {
        let transcript = "[Me] hello\n[Mac OS] hi there"
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertTrue(split.system.contains("[SPEAKER_CHANGE]"),
                       "Legacy suffix should be used for [Mac OS] labels")
        XCTAssertFalse(split.system.contains("voice analysis"),
                        "SpeakerKit suffix should not be used for legacy labels")
    }

    func testSpeakerKitSuffixAndNoteSuffixCoexist() {
        let transcript = "[Me] hello\n[Speaker A] hi\n[USER NOTE @ 00:05] important point"
        let split = MeetingAnalyzer.buildSplitPrompt(
            prompt: "Summarize.\n[TRANSCRIPTION_PLACEHOLDER]",
            transcript: transcript,
            modelName: "llama3"
        )
        XCTAssertTrue(split.system.contains("voice analysis"), "SpeakerKit suffix should be present")
        XCTAssertTrue(split.system.contains("USER NOTE"), "Note suffix should also be present")
    }
}
