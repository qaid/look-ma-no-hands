import SwiftUI
import UniformTypeIdentifiers

/// State for managing meeting transcription session
@Observable
class MeetingState {
    var isRecording = false
    var isPaused = false
    var currentTranscript = ""
    var segments: [TranscriptSegment] = []
    var structuredNotes: String?
    var isAnalyzing = false
    var statusMessage = "Ready to start"
    var elapsedTime: TimeInterval = 0
}

/// View for meeting transcription mode
/// Shows live transcript, timer, and recording controls
struct MeetingView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var meetingState = MeetingState()
    @State private var timer: Timer?
    @State private var showPromptEditor = false
    @State private var customPrompt = Settings.shared.meetingPrompt
    @State private var jargonTerms = ""
    @State private var showAdvancedPrompt = false

    // Services
    private let mixedAudioRecorder: MixedAudioRecorder
    private let continuousTranscriber: ContinuousTranscriber
    private let whisperService: WhisperService
    private let meetingAnalyzer: MeetingAnalyzer

    init(whisperService: WhisperService) {
        self.whisperService = whisperService
        self.mixedAudioRecorder = MixedAudioRecorder()
        self.continuousTranscriber = ContinuousTranscriber(whisperService: whisperService)
        self.meetingAnalyzer = MeetingAnalyzer()

        // Setup callbacks for continuous transcription
        setupTranscriberCallbacks()
        setupAudioRecorderCallback()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            headerView

            Divider()

            // Status bar with timer and audio source
            statusBar

            Divider()

            // Live transcript display
            transcriptView

            Divider()

            // Control buttons
            controlsView
        }
        .frame(width: 700, height: 500)
        .sheet(isPresented: $showPromptEditor) {
            promptEditorSheet
        }
        .onDisappear {
            // Cleanup when window closes
            if meetingState.isRecording {
                Task {
                    await stopRecording()
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "mic.fill")
                .foregroundColor(.blue)

            Text("Meeting Transcription")
                .font(.headline)

            Spacer()
        }
        .padding()
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 6) {
                if meetingState.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                }

                Text(meetingState.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Microphone selector (disabled during recording)
            Menu {
                ForEach(Settings.shared.audioDeviceManager.availableDevices) { device in
                    Button {
                        Settings.shared.audioDeviceManager.selectDevice(device)
                    } label: {
                        HStack {
                            Text(device.name)
                            if device.id == Settings.shared.audioDeviceManager.selectedDevice.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    Settings.shared.audioDeviceManager.refreshDevices()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                    Text(Settings.shared.audioDeviceManager.selectedDevice.name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .disabled(meetingState.isRecording)
            .help("Select microphone input")

            Spacer()

            // Timer
            Text(formatTime(meetingState.elapsedTime))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Transcript View

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if meetingState.segments.isEmpty && !meetingState.isRecording {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            Text("No transcript yet")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Text("Click Start to begin recording (captures both system audio and microphone)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        // Show segments with timestamps
                        ForEach(Array(meetingState.segments.enumerated()), id: \.offset) { index, segment in
                            HStack(alignment: .top, spacing: 12) {
                                // Timestamp
                                Text(formatTimestamp(segment.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)

                                // Text
                                Text(segment.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                            .id(index)
                        }

                        // Auto-scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding()
            }
            .onChange(of: meetingState.segments.count) { _, _ in
                // Auto-scroll to bottom when new segment arrives
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: 16) {
            // Start/Stop button
            Button {
                if meetingState.isRecording {
                    Task {
                        await stopRecording()
                    }
                } else {
                    Task {
                        await startRecording()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: meetingState.isRecording ? "stop.fill" : "record.circle")
                    Text(meetingState.isRecording ? "Stop Recording" : "Start Recording")
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(meetingState.isRecording ? .red : .blue)
            .disabled(meetingState.statusMessage.contains("Processing"))

            // Clear transcript button
            Button {
                clearTranscript()
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear")
                }
            }
            .disabled(meetingState.segments.isEmpty)

            // Generate notes button
            Button {
                showPromptEditor = true
            } label: {
                HStack {
                    Image(systemName: meetingState.isAnalyzing ? "hourglass" : "sparkles")
                    Text(meetingState.isAnalyzing ? "Analyzing..." : "Generate Notes")
                }
            }
            .disabled(meetingState.segments.isEmpty || meetingState.isRecording || meetingState.isAnalyzing)

            Spacer()

            // Export button
            Menu {
                Button("Copy Transcript") {
                    copyTranscript()
                }

                Button("Copy Notes (Markdown)") {
                    copyStructuredNotes()
                }
                .disabled(meetingState.structuredNotes == nil)

                Divider()

                Button("Save Transcript (Text)...") {
                    saveTranscript()
                }

                Button("Save Transcript (Timestamped)...") {
                    saveTimestampedTranscript()
                }

                Button("Save Notes (Markdown)...") {
                    saveStructuredNotes()
                }
                .disabled(meetingState.structuredNotes == nil)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
            }
            .disabled(meetingState.segments.isEmpty)
        }
        .padding()
    }

    // MARK: - Recording Control

    private func startRecording() async {
        do {
            // Check permission first
            let hasPermission = await SystemAudioRecorder.requestPermission()
            guard hasPermission else {
                meetingState.statusMessage = "Screen recording permission denied"
                return
            }

            meetingState.statusMessage = "Starting..."

            // Start continuous transcriber session
            continuousTranscriber.startSession()

            // Start mixed audio recording (system + microphone)
            try await mixedAudioRecorder.startRecording()

            meetingState.isRecording = true
            meetingState.statusMessage = "Recording (system + microphone)"
            meetingState.elapsedTime = 0

            // Start timer
            startTimer()

            print("MeetingView: Recording started (mixed audio)")

        } catch {
            print("MeetingView: Failed to start recording - \(error)")
            print("MeetingView: Error details: \(String(describing: error))")

            let errorMessage: String
            if let recorderError = error as? RecorderError {
                switch recorderError {
                case .noDisplayAvailable:
                    errorMessage = "No display available for recording"
                case .permissionDenied:
                    errorMessage = "Screen recording permission denied"
                case .captureFailure(let details):
                    errorMessage = "Capture failed: \(details)"
                }
            } else {
                errorMessage = error.localizedDescription
            }

            meetingState.statusMessage = "Error: \(errorMessage)"
        }
    }

    private func stopRecording() async {
        meetingState.statusMessage = "Finalizing transcription..."

        // Stop timer
        stopTimer()

        // Stop mixed audio recording (audio chunks were already processed in real-time)
        _ = await mixedAudioRecorder.stopRecording()

        // End transcription session (processes any remaining audio)
        let finalSegments = await continuousTranscriber.endSession()

        // Update with all segments (includes real-time + any final processing)
        meetingState.segments = finalSegments

        meetingState.isRecording = false
        meetingState.statusMessage = "Recording stopped - \(finalSegments.count) segments"

        print("MeetingView: Recording stopped, \(finalSegments.count) segments transcribed")
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            meetingState.elapsedTime += 0.1

            // Poll for new audio samples every second
            if Int(meetingState.elapsedTime * 10) % 10 == 0 {
                Task {
                    await processAudioBuffer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func processAudioBuffer() async {
        // Get current audio buffer from recorder and process it
        // Note: This is a simplified approach - ideally we'd have a callback from SystemAudioRecorder
        // For now, we rely on the final processing when recording stops
    }

    // MARK: - Transcript Actions

    private func clearTranscript() {
        meetingState.segments.removeAll()
        meetingState.currentTranscript = ""
        meetingState.structuredNotes = nil
        meetingState.elapsedTime = 0
        meetingState.statusMessage = "Ready to start"
    }

    // MARK: - Structured Notes Generation

    private func generateStructuredNotes(with prompt: String) async {
        guard !meetingState.segments.isEmpty else { return }

        meetingState.isAnalyzing = true
        meetingState.statusMessage = "Generating structured notes..."

        // Build full transcript
        let fullTranscript = meetingState.segments
            .map { $0.text }
            .joined(separator: " ")

        do {
            let notes = try await meetingAnalyzer.analyzeMeeting(transcript: fullTranscript, customPrompt: prompt)
            meetingState.structuredNotes = notes
            meetingState.statusMessage = "Notes generated successfully"
        } catch {
            meetingState.statusMessage = "Failed to generate notes: \(error.localizedDescription)"
        }

        meetingState.isAnalyzing = false
    }

    private func copyTranscript() {
        let text = meetingState.segments
            .map { $0.text }
            .joined(separator: " ")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        meetingState.statusMessage = "Transcript copied to clipboard"
    }

    private func copyStructuredNotes() {
        guard let notes = meetingState.structuredNotes else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes, forType: .string)

        meetingState.statusMessage = "Notes copied to clipboard"
    }

    private func saveTranscript() {
        let text = meetingState.segments
            .map { $0.text }
            .joined(separator: "\n\n")

        saveToFile(content: text, defaultName: "meeting-transcript.txt", contentType: .plainText)
    }

    private func saveTimestampedTranscript() {
        let text = meetingState.segments
            .map { segment in
                "[\(formatTimestamp(segment.startTime))] \(segment.text)"
            }
            .joined(separator: "\n\n")

        saveToFile(content: text, defaultName: "meeting-transcript-timestamped.txt", contentType: .plainText)
    }

    private func saveStructuredNotes() {
        guard let notes = meetingState.structuredNotes else { return }

        saveToFile(content: notes, defaultName: "meeting-notes.md", contentType: .init(filenameExtension: "md")!)
    }

    private func saveToFile(content: String, defaultName: String, contentType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                meetingState.statusMessage = "Saved to \(url.lastPathComponent)"
            } catch {
                meetingState.statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Callbacks

    private func setupTranscriberCallbacks() {
        continuousTranscriber.onSegmentTranscribed = { [self] segment in
            Task { @MainActor in
                meetingState.segments.append(segment)
            }
        }

        continuousTranscriber.onStatusUpdate = { [self] status in
            Task { @MainActor in
                if meetingState.isRecording {
                    meetingState.statusMessage = status
                }
            }
        }
    }

    private func setupAudioRecorderCallback() {
        mixedAudioRecorder.onAudioChunk = { [weak continuousTranscriber] audioChunk in
            guard let transcriber = continuousTranscriber else { return }
            Task {
                // Send mixed audio chunks to the transcriber for real-time processing
                await transcriber.addAudio(audioChunk)
            }
        }
    }

    // MARK: - Prompt Editor Sheet

    private var promptEditorSheet: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Customize Meeting Notes")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showPromptEditor = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }

            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize how the transcript is analyzed. Add domain-specific terms to improve accuracy.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Using model: \(Settings.shared.ollamaModel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Jargon/Terms input (Priority 1)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Domain-Specific Terms & Jargon")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextEditor(text: $jargonTerms)
                            .font(.body)
                            .frame(minHeight: 80)
                            .border(Color.gray.opacity(0.3), width: 1)
                            .cornerRadius(4)

                        Text("Enter technical terms, acronyms, or jargon (comma-separated). Example: \"LLM, RAG, embeddings, vector database\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Advanced prompt editing (Priority 2 - Progressive disclosure)
                    DisclosureGroup(
                        isExpanded: $showAdvancedPrompt,
                        content: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Full Prompt")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Spacer()

                                    Button("Reset to Default") {
                                        customPrompt = Settings.defaultMeetingPrompt
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                TextEditor(text: $customPrompt)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 200)
                                    .border(Color.gray.opacity(0.3), width: 1)
                                    .cornerRadius(4)

                                Text("The transcript will be automatically appended after this prompt.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            Text("Advanced: Edit Full Prompt")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    )
                }
                .padding(.vertical, 8)
            }

            // Action buttons
            HStack {
                Button("Cancel") {
                    showPromptEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Generate Notes") {
                    showPromptEditor = false
                    Task {
                        await generateStructuredNotes(with: buildFinalPrompt())
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 650, height: 550)
    }

    private func buildFinalPrompt() -> String {
        var finalPrompt = customPrompt

        // Add jargon/terms section if provided
        if !jargonTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let termsSection = """

---

## Domain-Specific Context

The following terms, acronyms, and jargon may appear in this transcription. Ensure these are recognized correctly and used appropriately in the summary:

\(jargonTerms)

When these terms appear, preserve their exact formatting and context. If they're used in decision-making or action items, include them precisely as stated.

---
"""
            finalPrompt += termsSection
        }

        return finalPrompt
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
