import SwiftUI
import UniformTypeIdentifiers
import Foundation

// MARK: - Typography & Color System

extension Font {
    // Craft.do-inspired typography scale
    static let meetingTitle = Font.system(size: 16, weight: .semibold)
    static let meetingBody = Font.system(size: 16, weight: .regular)
    static let meetingMetadata = Font.system(size: 14, weight: .regular)
    static let meetingCaption = Font.system(size: 13, weight: .regular)
    static let meetingTimestamp = Font.system(size: 13, weight: .medium, design: .monospaced)
}

extension Color {
    // Semantic colors that adapt to light/dark mode
    static let meetingPrimary = Color(nsColor: .labelColor)
    static let meetingSecondary = Color(nsColor: .secondaryLabelColor)
    static let meetingTertiary = Color(nsColor: .tertiaryLabelColor)
    static let meetingAccent = Color.accentColor
    static let meetingBackground = Color(nsColor: .textBackgroundColor)
    static let meetingChrome = Color(nsColor: .controlBackgroundColor)
}

// MARK: - Note Presets

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

// MARK: - Recording Session Model

/// Represents a single recording session within a meeting
struct RecordingSession: Identifiable {
    let id = UUID()
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }
    var segmentRange: Range<Int> // Range of transcript segments for this recording
}

/// Status of the meeting transcription
enum MeetingStatus: Equatable {
    case ready
    case missingModel
    case missingPermissions
    case recording
    case processing
    case completed

    var displayText: String {
        switch self {
        case .ready: return "Ready"
        case .missingModel: return "Model Required"
        case .missingPermissions: return "Permissions Required"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .completed: return "Completed"
        }
    }

    var badgeColor: Color {
        switch self {
        case .ready: return .green
        case .missingModel, .missingPermissions: return .orange
        case .recording: return .red
        case .processing: return .blue
        case .completed: return .purple
        }
    }
}

/// State for managing meeting transcription session
@Observable
class MeetingState {
    var status: MeetingStatus = .ready
    var isRecording = false
    var isPaused = false
    var currentTranscript = ""
    var segments: [TranscriptSegment] = []
    var recordingSessions: [RecordingSession] = []
    var selectedSessionIndex: Int? = nil
    var structuredNotes: String?
    var isAnalyzing = false
    var statusMessage = "Ready to start"
    var elapsedTime: TimeInterval = 0
    var sessionStartDate: Date?
    var frequencyBands: [Float] = Array(repeating: 0.0, count: 40)
    var isActive = true  // Flag to indicate if the view is active

    // Streaming progress
    var generationProgress: Double = 0.0
    var estimatedTotalChars: Int = 0
    var receivedChars: Int = 0
    var isStreaming: Bool = false
    var streamedNotesPreview: String = ""

    // Computed properties
    var meetingTitle: String {
        if let date = sessionStartDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            return "Meeting - \(formatter.string(from: date))"
        }
        return "Meeting Recording"
    }

    var canRecord: Bool {
        status != .missingModel && status != .missingPermissions
    }

    // Exponential smoothing for fluid waveform animation
    func updateFrequencyBands(_ newBands: [Float]) {
        guard frequencyBands.count == newBands.count else {
            frequencyBands = newBands
            return
        }

        // Smooth transition: 70% old + 30% new
        var smoothedBands: [Float] = []
        for i in 0..<newBands.count {
            let smoothed = frequencyBands[i] * 0.7 + newBands[i] * 0.3
            smoothedBands.append(smoothed)
        }

        frequencyBands = smoothedBands
    }
}

/// View for meeting transcription mode
/// Shows live transcript, timer, and recording controls
struct MeetingView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var meetingState = MeetingState()
    @State private var timer: Timer?
    @State private var audioUpdateTimer: Timer?
    @State private var showPromptEditor = false
    @State private var customPrompt = Settings.shared.meetingPrompt
    @State private var jargonTerms = ""
    @State private var showAdvancedPrompt = false
    @State private var showCustomization = false
    @State private var selectedPreset: NotePreset = .quickSummary
    @State private var menuRefreshTrigger = UUID()
    @State private var lastProgressUpdate = Date()
    @State private var showClearConfirmation = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var showTranscript = true
    @State private var showSettings = false
    @State private var availableOllamaModels: [String] = []
    @State private var showExportMenu = false
    @State private var scrollProxy: ScrollViewProxy?

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
            // Header: Meeting Title + Status Badge (no branding)
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            // Recording Visualization Area
            recordingVisualizationView
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

            Divider()

            // Transcription Section with fixed height
            transcriptView
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            // Bottom Action Buttons
            bottomActionsView
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 600)
        .animation(.easeInOut(duration: 0.3), value: showTranscript)
        .sheet(isPresented: $showPromptEditor) {
            promptEditorSheet
        }
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            settingsPopover
        }
        .onAppear {
            checkStatus()
            if meetingState.status == .missingPermissions {
                CGRequestScreenCaptureAccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { checkStatus() }
            }
        }
        .onDisappear {
            // Mark state as inactive to prevent timer callbacks
            meetingState.isActive = false

            // Stop all timers immediately
            stopAudioLevelUpdates()

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
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text(meetingState.meetingTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            // Status Badge
            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(meetingState.status.displayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(meetingState.status.badgeColor)
            )
    }

    // MARK: - Recording Visualization

    private var recordingVisualizationView: some View {
        HStack(spacing: 12) {
            // Record/Stop Button
            Button {
                handleRecordingToggle()
            } label: {
                Image(systemName: meetingState.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 32))
                    .foregroundColor(meetingState.status == .missingModel ? .secondary : .red)
            }
            .buttonStyle(.plain)
            .disabled(meetingState.status == .missingModel)
            .keyboardShortcut(.space, modifiers: [])
            .help(meetingState.isRecording ? "Stop recording" : (meetingState.status == .missingPermissions ? "Grant screen recording permission" : "Start recording"))

            // Waveform or Recording Bars
            if meetingState.isRecording {
                // Live waveform during recording
                liveWaveformView
            } else if !meetingState.recordingSessions.isEmpty {
                // Recording bars showing completed recordings
                recordingBarsView
            } else {
                // Empty state placeholder
                emptyVisualizationState
            }

            // Duration display
            if meetingState.isRecording || !meetingState.recordingSessions.isEmpty {
                Text(formatTime(totalDuration))
                    .font(.meetingTimestamp)
                    .foregroundColor(.meetingSecondary)
                    .frame(width: 60)
            }
        }
        .frame(height: 60)
    }

    private var emptyVisualizationState: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.meetingChrome.opacity(0.5))
            .frame(maxWidth: .infinity)
            .overlay(
                Text("Ready to record")
                    .font(.meetingMetadata)
                    .foregroundColor(.meetingTertiary)
            )
    }

    private var liveWaveformView: some View {
        WaveformLineView(frequencyBands: $meetingState.frequencyBands, height: 50)
            .frame(maxWidth: .infinity)
    }

    private var recordingBarsView: some View {
        HStack(spacing: 8) {
            ForEach(Array(meetingState.recordingSessions.enumerated()), id: \.offset) { index, session in
                recordingBar(for: session, at: index)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func recordingBar(for session: RecordingSession, at index: Int) -> some View {
        let isSelected = meetingState.selectedSessionIndex == index

        return RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.blue : Color.meetingChrome)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .overlay(
                Text("\(formatTime(session.duration))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
            )
            .onTapGesture {
                selectRecordingSession(at: index)
            }
    }

    private var totalDuration: TimeInterval {
        if meetingState.isRecording {
            return meetingState.recordingSessions.reduce(0) { $0 + $1.duration } + meetingState.elapsedTime
        }
        return meetingState.recordingSessions.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Transcript View

    private var transcriptView: some View {
        VStack(spacing: 0) {
            // Transcript header with Clear button
            HStack {
                Button(action: { showTranscript.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: showTranscript ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                        Text("Transcription")
                            .font(.system(size: 15, weight: .medium))

                        if !meetingState.segments.isEmpty {
                            Text("\(meetingState.segments.count) segments")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Clear button inside transcript frame
                Button {
                    showClearConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Clear")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(meetingState.segments.isEmpty)
                .keyboardShortcut("k", modifiers: .command)
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
            }
            .padding(.bottom, 8)

            if showTranscript {
                // Fixed height transcript content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if meetingState.segments.isEmpty {
                                Text("No transcript yet")
                                    .font(.meetingMetadata)
                                    .foregroundColor(.meetingTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 40)
                            } else {
                                // Show segments with timestamps and session dividers
                                ForEach(Array(meetingState.segments.enumerated()), id: \.offset) { index, segment in
                                    let isHighlighted = isSegmentInSelectedSession(index: index)

                                    // Show session divider if this is the first segment of a new recording session
                                    if isFirstSegmentOfSession(index: index) && index > 0 {
                                        sessionDivider(for: index)
                                            .padding(.vertical, 12)
                                    }

                                    HStack(alignment: .top, spacing: 12) {
                                        // Timestamp
                                        Text(formatTimestamp(segment.startTime))
                                            .font(.meetingTimestamp)
                                            .foregroundColor(isHighlighted ? .blue : .meetingSecondary)
                                            .frame(width: 60, alignment: .leading)
                                            .accessibilityLabel("Time \(formatTimestamp(segment.startTime))")

                                        // Text
                                        Text(segment.text)
                                            .font(.meetingBody)
                                            .foregroundColor(isHighlighted ? .primary : .meetingPrimary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .accessibilityLabel("Transcript: \(segment.text)")
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .id(index)
                                    .accessibilityElement(children: .combine)
                                }

                                // Auto-scroll anchor
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(height: 200)  // Fixed height to prevent window scrolling
                    .onChange(of: meetingState.segments.count) { _, _ in
                        // Auto-scroll to bottom when new segment arrives
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        // Capture scroll proxy for use in selectRecordingSession
                        scrollProxy = proxy
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Bottom Actions

    private var bottomActionsView: some View {
        HStack(spacing: 12) {
            // Export Button with Popover
            Button {
                showExportMenu.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                    Text("Export")
                        .font(.system(size: 15))
                }
                .frame(width: 120, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(meetingState.segments.isEmpty)
            .popover(isPresented: $showExportMenu, arrowEdge: .bottom) {
                exportPopover
            }

            // Summary Button (or Cancel when analyzing)
            Button {
                if meetingState.isAnalyzing {
                    cancelAnalysis()
                } else {
                    showPromptEditor = true
                }
            } label: {
                HStack(spacing: 8) {
                    if meetingState.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                    }
                    Text(meetingState.isAnalyzing ? "Cancel" : "Summary")
                        .font(.system(size: 15))
                }
                .frame(width: 120, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(meetingState.segments.isEmpty || meetingState.isRecording)
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            // Settings Button (right side)
            Button {
                showSettings.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                    Text("Settings")
                        .font(.system(size: 15))
                }
                .frame(width: 120, height: 32)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Settings Popover

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))

            Divider()

            // Microphone Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Microphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { Settings.shared.audioDeviceManager.selectedDevice },
                    set: { Settings.shared.audioDeviceManager.selectDevice($0) }
                )) {
                    ForEach(Settings.shared.audioDeviceManager.availableDevices) { device in
                        Text(device.name).tag(device)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Button {
                    Settings.shared.audioDeviceManager.refreshDevices()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Refresh Devices")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }

            Divider()

            // Model Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("LLM Model")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                if availableOllamaModels.isEmpty {
                    TextField("Model name", text: Binding(
                        get: { Settings.shared.ollamaModel },
                        set: { Settings.shared.ollamaModel = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                } else {
                    Picker("", selection: Binding(
                        get: { Settings.shared.ollamaModel },
                        set: { Settings.shared.ollamaModel = $0 }
                    )) {
                        if !availableOllamaModels.contains(Settings.shared.ollamaModel) {
                            Text(Settings.shared.ollamaModel).tag(Settings.shared.ollamaModel)
                        }
                        ForEach(availableOllamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                if availableOllamaModels.isEmpty {
                    Text("Start Ollama to select from installed models")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Select from locally installed models")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .onAppear {
                fetchOllamaModels()
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - Ollama Models

    private func fetchOllamaModels() {
        Task {
            let ollamaService = OllamaService()
            do {
                let models = try await ollamaService.listModels()
                await MainActor.run {
                    self.availableOllamaModels = models
                }
            } catch {
                await MainActor.run {
                    self.availableOllamaModels = []
                }
            }
        }
    }

    // MARK: - Export Popover

    private var exportPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Transcript Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Button {
                    copyTranscript()
                    showExportMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Copy Transcript")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    copyTimestampedTranscript()
                    showExportMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Copy Timestamped")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 4)

                Button {
                    saveTranscript()
                    showExportMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Save as Text...")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    saveTimestampedTranscript()
                    showExportMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Save with Timestamps...")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // Notes Section (if available)
            if meetingState.structuredNotes != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    Button {
                        copyStructuredNotes()
                        showExportMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text("Copy Notes")
                                .font(.system(size: 14))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        saveStructuredNotes()
                        showExportMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text("Save Notes...")
                                .font(.system(size: 14))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 240)
    }

    // MARK: - Helper Functions

    private func checkStatus() {
        // Check if model is loaded
        if !whisperService.isModelLoaded {
            meetingState.status = .missingModel
            return
        }

        // Check screen recording permission
        if !SystemAudioRecorder.hasPermission() {
            meetingState.status = .missingPermissions
            return
        }

        meetingState.status = .ready
    }

    private func selectRecordingSession(at index: Int) {
        // Toggle selection - clicking the same bar deselects it
        if meetingState.selectedSessionIndex == index {
            meetingState.selectedSessionIndex = nil
        } else {
            meetingState.selectedSessionIndex = index

            // Expand transcript if collapsed
            if !showTranscript {
                showTranscript = true
            }

            // Scroll to first segment of this recording session
            guard index < meetingState.recordingSessions.count else { return }
            let session = meetingState.recordingSessions[index]
            let firstSegmentIndex = session.segmentRange.lowerBound

            // Scroll to the first segment with animation
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy?.scrollTo(firstSegmentIndex, anchor: .top)
            }
        }
    }

    /// Check if a segment index belongs to the currently selected recording session
    private func isSegmentInSelectedSession(index: Int) -> Bool {
        guard let selectedIndex = meetingState.selectedSessionIndex,
              selectedIndex < meetingState.recordingSessions.count else {
            return false
        }

        let session = meetingState.recordingSessions[selectedIndex]
        return session.segmentRange.contains(index)
    }

    /// Check if a segment is the first segment of a recording session
    private func isFirstSegmentOfSession(index: Int) -> Bool {
        return meetingState.recordingSessions.contains { session in
            session.segmentRange.lowerBound == index
        }
    }

    /// Session divider view to visually separate recording segments
    @ViewBuilder
    private func sessionDivider(for index: Int) -> some View {
        // Find which session this divider represents
        if let sessionIndex = meetingState.recordingSessions.firstIndex(where: { $0.segmentRange.lowerBound == index }) {
            let session = meetingState.recordingSessions[sessionIndex]

            VStack(spacing: 4) {
                // Main divider line with session info
                HStack(spacing: 8) {
                    // Left line - more prominent
                    Rectangle()
                        .fill(Color.blue.opacity(0.5))
                        .frame(height: 2)

                    // Session badge - high contrast
                    sessionBadge(session: session, sessionIndex: sessionIndex)

                    // Right line
                    Rectangle()
                        .fill(Color.blue.opacity(0.5))
                        .frame(height: 2)
                }

                // Gap indicator (if applicable)
                if sessionIndex > 0 {
                    gapIndicator(currentSession: session, sessionIndex: sessionIndex)
                }
            }
        }
    }

    /// Creates the prominent session badge with session info
    private func sessionBadge(session: RecordingSession, sessionIndex: Int) -> some View {
        HStack(spacing: 8) {
            // Record icon
            Image(systemName: "record.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)

            // Session number
            Text("Recording \(sessionIndex + 1)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            // Separator dot
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 3, height: 3)

            // Duration
            Text(formatTime(session.duration))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)

            // Separator dot
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 3, height: 3)

            // Segment count
            Text("\(session.segmentRange.count) segments")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.blue)
        )
    }

    /// Shows gap duration between recording sessions
    @ViewBuilder
    private func gapIndicator(currentSession: RecordingSession, sessionIndex: Int) -> some View {
        if sessionIndex > 0,
           sessionIndex - 1 < meetingState.recordingSessions.count,
           let gap = calculateGapDuration(
               currentSession: currentSession,
               previousSession: meetingState.recordingSessions[sessionIndex - 1]
           ),
           gap > 1.0 { // Only show if gap > 1 second
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.meetingTertiary)

                Text("Gap: \(formatTime(gap)) since last session")
                    .font(.system(size: 11))
                    .foregroundColor(.meetingTertiary)
            }
            .padding(.top, 4)
        }
    }

    private func startAudioLevelUpdates() {
        // Stop any existing timer first
        stopAudioLevelUpdates()

        let recorder = self.mixedAudioRecorder
        let state = self.meetingState

        audioUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { timer in
            // Check if timer is still valid and state is active
            guard timer.isValid, state.isActive else {
                timer.invalidate()
                return
            }

            let bands = recorder.getFrequencyBands(bandCount: 40)
            Task { @MainActor in
                // Double-check state is still active before updating
                guard state.isActive else { return }
                state.updateFrequencyBands(bands)
            }
        }
    }

    private func stopAudioLevelUpdates() {
        audioUpdateTimer?.invalidate()
        audioUpdateTimer = nil
        meetingState.frequencyBands = Array(repeating: 0.0, count: 40)
    }

    // MARK: - Keyboard Shortcuts

    private func handleRecordingToggle() {
        if meetingState.isRecording {
            Task {
                await stopRecording()
            }
        } else if meetingState.status == .missingPermissions {
            promptForScreenRecordingPermission()
        } else if meetingState.canRecord {
            Task {
                await startRecording()
            }
        }
    }

    private func promptForScreenRecordingPermission() {
        // CGRequestScreenCaptureAccess() shows the macOS permission dialog on first request,
        // or opens System Settings > Privacy & Security > Screen Recording if already denied.
        CGRequestScreenCaptureAccess()

        // Re-check after a short delay to update status if permission was just granted
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            checkStatus()
        }
    }

    // MARK: - Recording Control

    private func startRecording() async {
        do {
            // Request screen recording permission if not yet determined
            if !SystemAudioRecorder.hasPermission() {
                let granted = await SystemAudioRecorder.requestPermission()
                if !granted {
                    meetingState.status = .missingPermissions
                    meetingState.statusMessage = "Screen recording permission required"
                    return
                }
            }

            // Set session start date on first recording
            if meetingState.sessionStartDate == nil {
                meetingState.sessionStartDate = Date()
            }

            meetingState.status = .recording
            meetingState.statusMessage = "Starting..."

            // Start continuous transcriber session
            continuousTranscriber.startSession()

            // Start mixed audio recording (system + microphone)
            try await mixedAudioRecorder.startRecording()

            meetingState.isRecording = true
            meetingState.statusMessage = "Recording (system + microphone)"
            meetingState.elapsedTime = 0

            // Notify AppDelegate that recording started
            appDelegate?.isMeetingRecording = true

            // Start timer and audio visualization
            startTimer()
            startAudioLevelUpdates()

            print("MeetingView: Recording started (mixed audio)")

        } catch {
            print("MeetingView: Failed to start recording - \(error)")

            let errorMessage: String
            if let recorderError = error as? RecorderError {
                switch recorderError {
                case .noDisplayAvailable:
                    errorMessage = "No display available for recording"
                case .permissionDenied:
                    errorMessage = "Screen recording permission denied"
                    meetingState.status = .missingPermissions
                case .captureFailure(let details):
                    errorMessage = "Capture failed: \(details)"
                }
            } else {
                errorMessage = error.localizedDescription
            }

            meetingState.statusMessage = "Error: \(errorMessage)"
            meetingState.status = .ready
        }
    }

    private func stopRecording() async {
        meetingState.status = .processing
        meetingState.statusMessage = "Finalizing transcription..."

        // Stop timer and audio visualization
        stopTimer()
        stopAudioLevelUpdates()

        // Stop mixed audio recording
        _ = await mixedAudioRecorder.stopRecording()

        // End transcription session
        let finalSegments = await continuousTranscriber.endSession()

        // Create recording session
        // Calculate correct indices: segments are already added via callback
        let sessionStartIndex = meetingState.segments.count - finalSegments.count
        let sessionEndIndex = meetingState.segments.count

        // Only create session if we have new segments
        if sessionEndIndex > sessionStartIndex {
            let newSession = RecordingSession(
                startTime: Date().addingTimeInterval(-meetingState.elapsedTime),
                endTime: Date(),
                segmentRange: sessionStartIndex..<sessionEndIndex
            )
            meetingState.recordingSessions.append(newSession)
        }

        // Segments are already in meetingState.segments via real-time callback
        // (no need to overwrite - that would lose previous sessions' segments)

        meetingState.isRecording = false
        meetingState.status = .completed
        meetingState.statusMessage = "Recording stopped - \(meetingState.segments.count) segments total"

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
        meetingState.recordingSessions.removeAll()
        meetingState.sessionStartDate = nil
        meetingState.statusMessage = "Ready to start"
        meetingState.status = .ready

        // Clear the continuous transcriber's segments as well
        continuousTranscriber.clearSegments()
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate Meeting Notes")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button {
                    showPromptEditor = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Note type selection - card-based with clear selected state
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select note type")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(spacing: 12) {
                            // Quick Summary Card
                            noteTypeCard(
                                preset: .quickSummary,
                                icon: "list.bullet.clipboard",
                                title: "Quick Summary",
                                description: "3-5 key points, action items, and decisions (~2 min read)",
                                isSelected: selectedPreset == .quickSummary
                            )

                            // Detailed Notes Card
                            noteTypeCard(
                                preset: .detailedNotes,
                                icon: "doc.text",
                                title: "Detailed Notes",
                                description: "Comprehensive summary with full context and discussion points (~5 min read)",
                                isSelected: selectedPreset == .detailedNotes
                            )
                        }
                    }

                    // Customization - progressive disclosure
                    DisclosureGroup(
                        isExpanded: $showCustomization,
                        content: {
                            VStack(alignment: .leading, spacing: 16) {
                                // Jargon/Terms input
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Domain-Specific Terms")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)

                                    TextEditor(text: $jargonTerms)
                                        .font(.system(size: 13))
                                        .frame(height: 60)
                                        .scrollContentBackground(.hidden)
                                        .padding(8)
                                        .background(Color(NSColor.textBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )

                                    Text("Enter technical terms or acronyms (comma-separated)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                // Advanced prompt editing
                                DisclosureGroup(
                                    isExpanded: $showAdvancedPrompt,
                                    content: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Custom Prompt")
                                                    .font(.system(size: 13, weight: .medium))

                                                Spacer()

                                                Button("Reset") {
                                                    customPrompt = Settings.defaultMeetingPrompt
                                                }
                                                .buttonStyle(.borderless)
                                                .controlSize(.small)
                                                .foregroundColor(.accentColor)
                                            }

                                            TextEditor(text: $customPrompt)
                                                .font(.system(size: 12, design: .monospaced))
                                                .frame(height: 120)
                                                .scrollContentBackground(.hidden)
                                                .padding(8)
                                                .background(Color(NSColor.textBackgroundColor))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                                )

                                            Text("Transcript will be appended automatically")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.top, 8)
                                    },
                                    label: {
                                        HStack {
                                            Text("Advanced Options")
                                                .font(.system(size: 13, weight: .medium))
                                            Spacer()
                                        }
                                    }
                                )
                            }
                            .padding(.top, 12)
                        },
                        label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 13))
                                Text("Customize")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                    )
                    .accentColor(.primary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            Divider()

            // Bottom action bar
            HStack(spacing: 12) {
                Button("Cancel") {
                    showPromptEditor = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                .controlSize(.large)

                Spacer()

                Button {
                    generateNotes()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .medium))
                        Text("Generate Notes")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .controlSize(.large)
                .accessibilityLabel("Generate notes with selected settings")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 480)
    }

    /// Creates a selectable note type card with clear visual feedback
    private func noteTypeCard(preset: NotePreset, icon: String, title: String, description: String, isSelected: Bool) -> some View {
        Button {
            selectedPreset = preset
        } label: {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : Color(NSColor.tertiaryLabelColor))
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(description)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Generates notes with the currently selected preset and customizations
    private func generateNotes() {
        showPromptEditor = false
        Task {
            let prompt = showCustomization ? buildFinalPrompt() : selectedPreset.prompt
            await generateStructuredNotes(with: prompt)
        }
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

    /// Calculates the time gap between two recording sessions
    private func calculateGapDuration(currentSession: RecordingSession, previousSession: RecordingSession) -> TimeInterval? {
        guard let previousEnd = previousSession.endTime else { return nil }
        let gap = currentSession.startTime.timeIntervalSince(previousEnd)
        return gap > 0 ? gap : nil
    }
}
