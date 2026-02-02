import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// Preset note generation styles
enum NotePreset {
    case quickSummary
    case detailedNotes

    var prompt: String {
        switch self {
        case .quickSummary:
            return """
            Summarize this meeting transcript concisely:

            ## Key Points
            - List the 3-5 main topics discussed

            ## Action Items
            - List specific tasks and owners

            ## Decisions Made
            - List concrete decisions
            """
        case .detailedNotes:
            return Settings.shared.meetingPrompt
        }
    }
}

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

    // Streaming progress
    var generationProgress: Double = 0.0
    var estimatedTotalChars: Int = 0
    var receivedChars: Int = 0
    var isStreaming: Bool = false
    var streamedNotesPreview: String = ""
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
    @State private var showCustomization = false
    @State private var menuRefreshTrigger = UUID()
    @State private var lastProgressUpdate = Date()
    @State private var showClearConfirmation = false
    @State private var analysisTask: Task<Void, Never>?

    // Services
    private let mixedAudioRecorder: MixedAudioRecorder
    private let continuousTranscriber: ContinuousTranscriber
    private let whisperService: WhisperService
    private let meetingAnalyzer: MeetingAnalyzer
    private let recordingIndicator: RecordingIndicatorWindowController?
    private weak var appDelegate: AppDelegate?

    init(whisperService: WhisperService, recordingIndicator: RecordingIndicatorWindowController? = nil, appDelegate: AppDelegate? = nil) {
        self.whisperService = whisperService
        self.mixedAudioRecorder = MixedAudioRecorder()
        self.continuousTranscriber = ContinuousTranscriber(whisperService: whisperService)
        self.meetingAnalyzer = MeetingAnalyzer()
        self.recordingIndicator = recordingIndicator
        self.appDelegate = appDelegate

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
                        // Empty state with improved visual hierarchy
                        VStack(spacing: 16) {
                            Image(systemName: "waveform.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.accentColor)
                                .symbolEffect(.pulse)

                            VStack(spacing: 8) {
                                Text("Ready to Record")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("Captures system audio and microphone")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }

                            // Visual CTA
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.6))

                                Text("Click Start Recording below")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
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
                showClearConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear")
                }
            }
            .disabled(meetingState.segments.isEmpty)
            .confirmationDialog(
                "Clear Transcript?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Transcript", role: .destructive) {
                    clearTranscript()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \(meetingState.segments.count) transcript segments.")
            }

            // Generate notes button with overlaid progress bar and cancellation
            Button {
                if meetingState.isAnalyzing {
                    cancelAnalysis()
                } else {
                    showPromptEditor = true
                }
            } label: {
                HStack {
                    Image(systemName: meetingState.isAnalyzing ? "xmark.circle.fill" : "sparkles")
                    Text(meetingState.isAnalyzing
                        ? "Cancel (\(Int(meetingState.generationProgress * 100))%)"
                        : (meetingState.structuredNotes != nil ? "Re-Generate Notes" : "Generate Notes")
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if meetingState.isAnalyzing && meetingState.isStreaming {
                    ProgressView(value: meetingState.generationProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(height: 4)
                        .padding(.horizontal, 2)
                        .padding(.bottom, -2)
                }
            }
            .disabled(meetingState.segments.isEmpty || meetingState.isRecording)
            .help(generateNotesHelpText)

            Spacer()

            // Export buttons - split into Transcript and Notes
            HStack(spacing: 12) {
                // Transcript export (always available if segments exist)
                Menu {
                    Section("Transcript") {
                        Button("Copy Transcript") {
                            copyTranscript()
                        }
                        Button("Copy Timestamped") {
                            copyTimestampedTranscript()
                        }

                        Divider()

                        Button("Save as Text...") {
                            saveTranscript()
                        }
                        Button("Save with Timestamps...") {
                            saveTimestampedTranscript()
                        }
                    }
                } label: {
                    Label("Export Transcript", systemImage: "doc.text")
                }
                .disabled(meetingState.segments.isEmpty)
                .help("Export raw transcript in various formats")

                // Notes export (only when generated)
                if meetingState.structuredNotes != nil {
                    Menu {
                        Button("Copy Notes") {
                            copyStructuredNotes()
                        }
                        Button("Save Notes...") {
                            saveStructuredNotes()
                        }
                    } label: {
                        Label("Export Notes", systemImage: "note.text")
                    }
                    .help("Export AI-generated meeting notes")
                }
            }
            .id(menuRefreshTrigger)
        }
        .padding()
    }

    // MARK: - Recording Control

    private func startRecording() async {
        do {
            meetingState.statusMessage = "Starting..."

            // Start continuous transcriber session
            continuousTranscriber.startSession()

            // Start mixed audio recording (system + microphone)
            // Note: ScreenCaptureKit requires screen recording permission for system audio
            // The system will automatically request permission if not yet granted
            try await mixedAudioRecorder.startRecording()

            meetingState.isRecording = true
            meetingState.statusMessage = "Recording (system + microphone)"
            meetingState.elapsedTime = 0

            // Notify AppDelegate that recording started
            appDelegate?.isMeetingRecording = true

            // Note: No waveform indicator for meeting mode - it's dictation-only

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

        // Note: No waveform indicator for meeting mode - it's dictation-only

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

        // Notify AppDelegate that recording stopped
        appDelegate?.isMeetingRecording = false

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

        // Cancel any existing analysis task
        analysisTask?.cancel()

        // Initialize streaming state
        await MainActor.run {
            meetingState.isAnalyzing = true
            meetingState.isStreaming = true
            meetingState.generationProgress = 0.0
            meetingState.receivedChars = 0
            meetingState.streamedNotesPreview = ""
            meetingState.statusMessage = "Generating structured notes..."
            lastProgressUpdate = Date()
        }

        // Create cancellable task
        analysisTask = Task {

            // Build full transcript
            let fullTranscript = meetingState.segments
                .map { $0.text }
                .joined(separator: " ")

            // Estimate expected response length
            let estimatedLength = estimateResponseLength(transcriptLength: fullTranscript.count)
            await MainActor.run {
                meetingState.estimatedTotalChars = estimatedLength
            }

            do {
                // Check for cancellation before starting
                if Task.isCancelled {
                    await MainActor.run {
                        meetingState.statusMessage = "Note generation cancelled"
                        meetingState.isAnalyzing = false
                        meetingState.isStreaming = false
                        resetGenerationState()
                    }
                    return
                }

                // Use streaming analysis with progress callback
                let notes = try await meetingAnalyzer.analyzeMeetingStreaming(
                    transcript: fullTranscript,
                    customPrompt: prompt
                ) { receivedChars, chunk in
                    // Check for cancellation during streaming
                    guard !Task.isCancelled else { return }

                    // Throttle UI updates to every 50ms
                    await MainActor.run {
                        let now = Date()
                        if now.timeIntervalSince(lastProgressUpdate) >= 0.05 {
                            meetingState.receivedChars = receivedChars
                            meetingState.streamedNotesPreview += chunk
                            meetingState.generationProgress = calculateProgress(
                                received: receivedChars,
                                estimated: estimatedLength
                            )
                            lastProgressUpdate = now
                        }
                    }
                }

                // Check for cancellation after completion
                if Task.isCancelled {
                    await MainActor.run {
                        meetingState.statusMessage = "Note generation cancelled"
                        meetingState.isAnalyzing = false
                        meetingState.isStreaming = false
                        resetGenerationState()
                    }
                    return
                }

                print("MeetingView: Analysis complete, notes length: \(notes.count)")

                await MainActor.run {
                    meetingState.structuredNotes = notes
                    meetingState.statusMessage = "Notes generated successfully"
                    meetingState.generationProgress = 1.0 // Set to 100%
                    meetingState.isAnalyzing = false
                    meetingState.isStreaming = false
                    menuRefreshTrigger = UUID() // Force menu to refresh
                    print("MeetingView: State updated - structuredNotes is now set: \(meetingState.structuredNotes != nil)")
                }

                // Send notification after state update
                let isAuthorized = await NotificationService.shared.isAuthorized()
                print("MeetingView: Notification authorized: \(isAuthorized)")

                // Always try to send notification (will request permission if needed)
                await NotificationService.shared.sendNotification(
                    title: "Meeting Notes Ready",
                    body: "Your structured meeting notes have been generated successfully."
                )
                print("MeetingView: Notification sent")
            } catch {
                print("MeetingView: Analysis failed: \(error)")
                await MainActor.run {
                    meetingState.statusMessage = "Failed to generate notes: \(error.localizedDescription)"
                    meetingState.isAnalyzing = false
                    meetingState.isStreaming = false
                    resetGenerationState()
                }
            }
        }

        await analysisTask?.value
        analysisTask = nil
    }

    // Helper: Estimate expected response length based on transcript
    private func estimateResponseLength(transcriptLength: Int) -> Int {
        // Meeting notes typically 15-25% of transcript length
        let baseEstimate = Int(Double(transcriptLength) * 0.20)
        return min(max(baseEstimate, 500), 5000) // Clamp to 500-5000 chars
    }

    // Helper: Calculate progress with logarithmic scaling
    private func calculateProgress(received: Int, estimated: Int) -> Double {
        guard estimated > 0 else { return 0.0 }

        let rawProgress = Double(received) / Double(estimated)

        // Asymptotic approach: never quite reaches 100% until done
        // Formula: -log(1 - x) / 3.0
        let scaled = -log(1 - min(rawProgress, 0.95)) / 3.0

        return min(scaled, 0.98) // Cap at 98% until stream completes
    }

    // Helper: Cancel analysis task
    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil

        meetingState.isAnalyzing = false
        meetingState.isStreaming = false
        meetingState.statusMessage = "Note generation cancelled"
        resetGenerationState()
    }

    // Helper: Reset generation state
    private func resetGenerationState() {
        meetingState.generationProgress = 0.0
        meetingState.receivedChars = 0
        meetingState.estimatedTotalChars = 0
        meetingState.streamedNotesPreview = ""
    }

    private func copyTranscript() {
        let text = meetingState.segments
            .map { $0.text }
            .joined(separator: " ")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        meetingState.statusMessage = "Transcript copied to clipboard"
    }

    private func copyTimestampedTranscript() {
        let text = meetingState.segments
            .map { segment in
                "[\(formatTimestamp(segment.startTime))] \(segment.text)"
            }
            .joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        meetingState.statusMessage = "Timestamped transcript copied to clipboard"
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
                Text("Generate Meeting Notes")
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

            // Quick generate options - primary interface
            VStack(alignment: .leading, spacing: 12) {
                Text("What type of notes do you need?")
                    .font(.headline)

                HStack(spacing: 12) {
                    // Preset 1: Quick summary
                    Button {
                        generateWithPreset(.quickSummary)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: "list.bullet.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("Quick Summary")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Key points and action items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    // Preset 2: Detailed notes
                    Button {
                        generateWithPreset(.detailedNotes)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: "doc.text.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                            Text("Detailed Notes")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Full summary with context")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Customization - secondary, progressive disclosure
            DisclosureGroup(
                isExpanded: $showCustomization,
                content: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Jargon/Terms input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Domain-Specific Terms & Jargon")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                TextEditor(text: $jargonTerms)
                                    .font(.body)
                                    .frame(minHeight: 60)
                                    .border(Color.gray.opacity(0.3), width: 1)
                                    .cornerRadius(4)

                                Text("Enter technical terms, acronyms, or jargon (comma-separated)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            // Advanced prompt editing
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
                                            .frame(minHeight: 150)
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
                },
                label: {
                    Text("Customize Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            )

            Spacer()

            // Model info
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Using model: \(Settings.shared.ollamaModel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Action buttons (only show if customization expanded)
            HStack {
                Button("Cancel") {
                    showPromptEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if showCustomization {
                    Button("Generate with Custom Settings") {
                        showPromptEditor = false
                        Task {
                            await generateStructuredNotes(with: buildFinalPrompt())
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 650, height: 550)
    }

    private func generateWithPreset(_ preset: NotePreset) {
        showPromptEditor = false
        Task {
            await generateStructuredNotes(with: preset.prompt)
        }
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

    // MARK: - Computed Properties

    private var generateNotesHelpText: String {
        if meetingState.isAnalyzing {
            return "Generating structured notes via Ollama..."
        } else if meetingState.structuredNotes != nil {
            return "Re-generate notes with different settings"
        } else {
            return "Generate AI-powered meeting notes"
        }
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
