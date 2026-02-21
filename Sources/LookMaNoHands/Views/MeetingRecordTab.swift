import SwiftUI
import UniformTypeIdentifiers

/// Live recording tab — captures system + mic audio, shows real-time transcript, auto-saves to library
@available(macOS 13.0, *)
struct MeetingRecordTab: View {

    // MARK: - Dependencies

    let store: MeetingStore
    var onRecordingFinished: (MeetingRecord) -> Void

    // MARK: - Services

    private let mixedAudioRecorder: MixedAudioRecorder
    private let continuousTranscriber: ContinuousTranscriber
    private let whisperService: WhisperService
    private let recordingIndicator: RecordingIndicatorWindowController?
    private weak var appDelegate: AppDelegate?

    // MARK: - State

    @State private var liveState = LiveMeetingState()
    @State private var selectedType: MeetingType = .general
    @State private var timer: Timer?
    @State private var audioUpdateTimer: Timer?
    @State private var showClearConfirmation = false
    @State private var showTranscript = true
    @State private var scrollProxy: ScrollViewProxy?

    // MARK: - Init

    init(
        store: MeetingStore,
        whisperService: WhisperService,
        recordingIndicator: RecordingIndicatorWindowController? = nil,
        appDelegate: AppDelegate? = nil,
        onRecordingFinished: @escaping (MeetingRecord) -> Void
    ) {
        self.store = store
        self.whisperService = whisperService
        self.recordingIndicator = recordingIndicator
        self.appDelegate = appDelegate
        self.onRecordingFinished = onRecordingFinished
        self.mixedAudioRecorder = MixedAudioRecorder()
        self.continuousTranscriber = ContinuousTranscriber(whisperService: whisperService)
        setupTranscriberCallbacks()
        setupAudioRecorderCallback()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider()

            typePicker
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider()

            recordingVisualizationView
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

            Divider()

            transcriptView
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            bottomActionsView
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .onAppear {
            checkStatus()
            if liveState.status == .missingPermissions {
                CGRequestScreenCaptureAccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { checkStatus() }
            }
        }
        .onDisappear {
            liveState.isActive = false
            stopAudioLevelUpdates()
            if liveState.isRecording {
                Task { await stopRecording() }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text(liveState.meetingTitle)
                .font(.system(size: 15, weight: .medium))

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(liveState.status.displayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(liveState.status.badgeColor))
    }

    // MARK: - Type Picker

    private var typePicker: some View {
        HStack(spacing: 8) {
            Text("Meeting type:")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Picker("", selection: $selectedType) {
                ForEach(MeetingType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(liveState.isRecording)

            Spacer()
        }
    }

    // MARK: - Recording Visualization

    private var recordingVisualizationView: some View {
        HStack(spacing: 12) {
            Button {
                handleRecordingToggle()
            } label: {
                Image(systemName: liveState.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 32))
                    .foregroundColor(recordButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(!liveState.canRecord && liveState.status != .missingPermissions)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(store.isImportingAudio)
            .help(liveState.isRecording ? "Stop recording" : "Start recording")

            if liveState.isRecording {
                WaveformLineView(frequencyBands: Binding(
                    get: { liveState.frequencyBands },
                    set: { _ in }
                ), height: 50)
                    .frame(maxWidth: .infinity)
            } else if !liveState.recordingSessions.isEmpty {
                recordingBarsView
            } else {
                emptyVisualizationState
            }

            if liveState.isRecording || !liveState.recordingSessions.isEmpty {
                Text(formatTime(totalDuration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60)
            }
        }
        .frame(height: 60)
    }

    private var emptyVisualizationState: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .frame(maxWidth: .infinity)
            .overlay(
                Text(store.isImportingAudio ? "Import in progress..." : "Ready to record")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            )
    }

    private var recordButtonColor: Color {
        if store.isImportingAudio { return .secondary }
        if liveState.isRecording { return .red }
        if liveState.status == .missingPermissions { return .red }
        if !liveState.canRecord { return .secondary }
        return .red
    }

    private var recordingBarsView: some View {
        HStack(spacing: 8) {
            ForEach(Array(liveState.recordingSessions.enumerated()), id: \.offset) { index, session in
                recordingBar(for: session, at: index)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func recordingBar(for session: RecordingSession, at index: Int) -> some View {
        let isSelected = liveState.selectedSessionIndex == index
        return RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
            .frame(maxWidth: .infinity, minHeight: 40)
            .overlay(
                Text(formatTime(session.duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
            )
            .onTapGesture { selectRecordingSession(at: index) }
    }

    private var totalDuration: TimeInterval {
        if liveState.isRecording {
            return liveState.recordingSessions.reduce(0) { $0 + $1.duration } + liveState.elapsedTime
        }
        return liveState.recordingSessions.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Transcript

    private var transcriptView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showTranscript.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showTranscript ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Image(systemName: "doc.text").font(.system(size: 14))
                        Text("Transcription").font(.system(size: 15, weight: .medium))
                        if !liveState.segments.isEmpty {
                            Text("\(liveState.segments.count) segments")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showClearConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("Clear").font(.system(size: 13))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(liveState.segments.isEmpty)
                .confirmationDialog(
                    "Clear Transcript?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear Transcript", role: .destructive) { clearTranscript() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete \(liveState.segments.count) transcript segments.")
                }
            }
            .padding(.bottom, 8)

            if showTranscript {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if liveState.segments.isEmpty {
                                Text("No transcript yet")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 40)
                            } else {
                                ForEach(Array(liveState.segments.enumerated()), id: \.offset) { index, segment in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(formatTimestamp(segment.startTime))
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)

                                        Text(segment.text)
                                            .font(.system(size: 16))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .id(index)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(height: 200)
                    .onChange(of: liveState.segments.count) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onAppear { scrollProxy = proxy }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Bottom Actions

    private var bottomActionsView: some View {
        HStack(spacing: 12) {
            Button {
                let text = liveState.segments.map { $0.text }.joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                liveState.statusMessage = "Transcript copied"
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc").font(.system(size: 16))
                    Text("Copy").font(.system(size: 15))
                }
                .frame(width: 120, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(liveState.segments.isEmpty)

            Button {
                saveTranscript()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 16))
                    Text("Export").font(.system(size: 15))
                }
                .frame(width: 120, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(liveState.segments.isEmpty)

            Spacer()

            if !liveState.statusMessage.isEmpty {
                Text(liveState.statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Recording Control

    private func handleRecordingToggle() {
        if liveState.isRecording {
            Task { await stopRecording() }
        } else if liveState.status == .missingPermissions {
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { checkStatus() }
        } else if liveState.canRecord {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        do {
            if !SystemAudioRecorder.hasPermission() {
                let granted = await SystemAudioRecorder.requestPermission()
                if !granted {
                    liveState.status = .missingPermissions
                    return
                }
            }

            if liveState.sessionStartDate == nil { liveState.sessionStartDate = Date() }

            liveState.status = .recording
            continuousTranscriber.startSession()
            try await mixedAudioRecorder.startRecording()
            liveState.isRecording = true
            liveState.elapsedTime = 0
            liveState.statusMessage = "Recording"

            store.isRecording = true
            appDelegate?.isMeetingRecording = true

            startTimer()
            startAudioLevelUpdates()
        } catch {
            liveState.statusMessage = "Failed to start: \(error.localizedDescription)"
            liveState.status = .ready
        }
    }

    private func stopRecording() async {
        liveState.status = .processing
        liveState.statusMessage = "Finalizing transcription..."

        stopTimer()
        stopAudioLevelUpdates()

        _ = await mixedAudioRecorder.stopRecording()
        let finalSegments = await continuousTranscriber.endSession()

        let sessionStartIndex = liveState.segments.count - finalSegments.count
        let sessionEndIndex = liveState.segments.count
        if sessionEndIndex > sessionStartIndex {
            let newSession = RecordingSession(
                startTime: Date().addingTimeInterval(-liveState.elapsedTime),
                endTime: Date(),
                segmentRange: sessionStartIndex..<sessionEndIndex
            )
            liveState.recordingSessions.append(newSession)
        }

        liveState.isRecording = false
        liveState.status = .completed
        liveState.statusMessage = "\(liveState.segments.count) segments"

        store.isRecording = false
        appDelegate?.isMeetingRecording = false

        // Auto-save to library
        do {
            let duration = totalDuration
            let record = try await store.saveRecordedMeeting(
                segments: liveState.segments,
                duration: duration,
                type: selectedType
            )
            onRecordingFinished(record)
        } catch {
            liveState.statusMessage = "Auto-save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Timers

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            liveState.elapsedTime += 0.1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startAudioLevelUpdates() {
        stopAudioLevelUpdates()
        let recorder = mixedAudioRecorder
        let state = liveState
        audioUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { t in
            guard t.isValid, state.isActive else { t.invalidate(); return }
            let bands = recorder.getFrequencyBands(bandCount: 40)
            Task { @MainActor in
                guard state.isActive else { return }
                state.updateFrequencyBands(bands)
            }
        }
    }

    private func stopAudioLevelUpdates() {
        audioUpdateTimer?.invalidate()
        audioUpdateTimer = nil
        liveState.frequencyBands = Array(repeating: 0.0, count: 40)
    }

    // MARK: - Transcript Actions

    private func clearTranscript() {
        liveState.segments.removeAll()
        liveState.recordingSessions.removeAll()
        liveState.elapsedTime = 0
        liveState.sessionStartDate = nil
        liveState.statusMessage = "Ready to start"
        liveState.status = .ready
        continuousTranscriber.clearSegments()
    }

    private func saveTranscript() {
        let text = liveState.segments.map { $0.text }.joined(separator: "\n\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "meeting-transcript.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func selectRecordingSession(at index: Int) {
        liveState.selectedSessionIndex = liveState.selectedSessionIndex == index ? nil : index
    }

    // MARK: - Status Check

    private func checkStatus() {
        if !whisperService.isModelLoaded {
            liveState.status = .missingModel
            return
        }
        if !SystemAudioRecorder.hasPermission() {
            liveState.status = .missingPermissions
            return
        }
        liveState.status = .ready
    }

    // MARK: - Callbacks

    private func setupTranscriberCallbacks() {
        continuousTranscriber.onSegmentTranscribed = { segment in
            Task { @MainActor in
                self.liveState.segments.append(segment)
            }
        }
        continuousTranscriber.onStatusUpdate = { status in
            Task { @MainActor in
                if self.liveState.isRecording {
                    self.liveState.statusMessage = status
                }
            }
        }
    }

    private func setupAudioRecorderCallback() {
        mixedAudioRecorder.onAudioChunk = { [weak continuousTranscriber] chunk in
            guard let transcriber = continuousTranscriber else { return }
            Task { await transcriber.addAudio(chunk) }
        }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
