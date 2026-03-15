import SwiftUI
import UniformTypeIdentifiers

/// Live recording tab — captures system + mic audio, shows real-time transcript, auto-saves to library
@available(macOS 13.0, *)
struct MeetingRecordTab: View {

    // MARK: - Dependencies

    let store: MeetingStore
    var onRecordingFinished: (MeetingRecord) -> Void

    // MARK: - Services

    @State private var mixedAudioRecorder: MixedAudioRecorder
    @State private var continuousTranscriber: ContinuousTranscriber
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
    @FocusState private var isNoteInputFocused: Bool

    // Note-above indicator state
    @State private var showNoteAboveIndicator = false
    @State private var lastSubmittedNoteID: UUID?
    @State private var noteAboveCount = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var permissionWorkItem: DispatchWorkItem?

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
        // 5s chunks for fast display. Previously 10s to reduce Whisper hallucinations,
        // but AEC now removes system audio bleed which was the main cause of repetition artifacts.
        let meetingChunkDuration: TimeInterval = 5
        _mixedAudioRecorder = State(initialValue: MixedAudioRecorder(chunkDuration: meetingChunkDuration))
        _continuousTranscriber = State(initialValue: ContinuousTranscriber(whisperService: whisperService, chunkDuration: meetingChunkDuration))
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
        }
        .onAppear {
            liveState.isActive = true
            setupTranscriberCallbacks()
            setupAudioRecorderCallback()
            checkStatus()
            if liveState.status == .missingPermissions {
                requestScreenRecordingPermission()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard Settings.shared.pendingScreenRecordingGrant else { return }
            checkStatus()
            appDelegate?.restoreMeetingWindowAfterPermission()
        }
        .onDisappear {
            liveState.isActive = false
            permissionWorkItem?.cancel()
            permissionWorkItem = nil
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
                .font(.system(size: 16))
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
                .font(.system(size: 14))
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
            if liveState.status == .completed {
                // Continue recording — primary action
                Button {
                    continueRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Continue")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.red))
                }
                .buttonStyle(.plain)
                .help("Continue recording, appending to existing transcript")

                // New recording — secondary action
                Button {
                    resetForNewRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("New")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().stroke(Color.secondary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Start a new recording")
            } else {
                Button {
                    handleRecordingToggle()
                } label: {
                    Image(systemName: liveState.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 32))
                        .foregroundColor(recordButtonColor)
                }
                .buttonStyle(.plain)
                .disabled(!liveState.canRecord && liveState.status != .missingPermissions)
                .disabled(store.isImportingAudio)
                .help(liveState.isRecording ? "Stop recording" : "Start recording")
            }

            // Hidden button for Space shortcut — disabled when note input has focus
            Button("") {
                if liveState.status == .completed {
                    continueRecording()
                } else {
                    handleRecordingToggle()
                }
            }
                .keyboardShortcut(.space, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
                .disabled(isNoteInputFocused || store.isImportingAudio || (!liveState.canRecord && liveState.status != .missingPermissions && liveState.status != .completed))

            if liveState.isRecording {
                WaveformLineView(frequencyBands: Binding(
                    get: { liveState.frequencyBands },
                    set: { _ in }
                ), height: 50)
                    .frame(maxWidth: .infinity)
            } else if liveState.status == .completed {
                completedVisualizationState
            } else {
                emptyVisualizationState
            }

            if liveState.isRecording {
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

    private var completedVisualizationState: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
            if liveState.recordingSessions.count > 1 {
                Text("Recording saved (\(liveState.recordingSessions.count) sessions)")
                    .font(.system(size: 14, weight: .medium))
            } else {
                Text("Recording saved")
                    .font(.system(size: 14, weight: .medium))
            }
            Text(formatTime(totalDuration))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var totalDuration: TimeInterval {
        if liveState.isRecording {
            return liveState.recordingSessions.reduce(0) { $0 + $1.duration } + liveState.elapsedTime
        }
        return liveState.recordingSessions.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Transcript + Notes Split

    private var transcriptView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showTranscript.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showTranscript ? "chevron.down" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Image(systemName: "doc.text").font(.system(size: 16))
                        Text("Transcription").font(.system(size: 15, weight: .medium))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showClearConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 14))
                        Text("Clear").font(.system(size: 14))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(liveState.segments.isEmpty && liveState.userNotes.isEmpty)
                .confirmationDialog(
                    "Clear Transcript?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) { clearTranscript() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete \(liveState.segments.count) transcript segments and \(liveState.userNotes.count) notes.")
                }

                Spacer()

                if liveState.isRecording || !liveState.userNotes.isEmpty {
                    Button {
                        liveState.isNotesSidebarVisible.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.line").font(.system(size: 14))
                            Text("Jot Notes")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(liveState.isNotesSidebarVisible ? Color(red: 0.55, green: 0.38, blue: 0.12) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("j", modifiers: .command)
                }
            }
            .padding(.bottom, 8)

            if showTranscript {
                HStack(spacing: 0) {
                    transcriptLeftPane

                    if liveState.isNotesSidebarVisible {
                        Divider()
                        notesSidebarPane
                            .frame(width: 240)
                    }
                }
                .frame(minHeight: 200, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Pastel Colors

    private static let pastelBlue = Color(red: 0.68, green: 0.78, blue: 0.95)     // Me
    private static let pastelGreen = Color(red: 0.68, green: 0.90, blue: 0.75)     // Remote/Mac OS
    static let pastelAmber = Color(red: 0.96, green: 0.84, blue: 0.62)     // Notes

    private static let pastelBlueTint = Color(red: 0.68, green: 0.78, blue: 0.95).opacity(0.12)
    private static let pastelGreenTint = Color(red: 0.68, green: 0.90, blue: 0.75).opacity(0.12)
    private static let pastelAmberTint = Color(red: 0.96, green: 0.84, blue: 0.62).opacity(0.15)

    private static let pastelBlueText = Color(red: 0.20, green: 0.36, blue: 0.60)
    private static let pastelGreenText = Color(red: 0.18, green: 0.45, blue: 0.30)
    private static let pastelAmberText = Color(red: 0.55, green: 0.38, blue: 0.12)

    // MARK: - Transcript Left Pane (timeline)

    private var transcriptLeftPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let groups = TimelineEntry.grouped(liveState.timelineEntries)
                    if groups.isEmpty {
                        Text("No transcript yet")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(groups) { group in
                            Group {
                                switch group.key {
                                case .speaker(let source):
                                    speakerGroupView(group: group, source: source)
                                case .note:
                                    noteGroupView(group: group)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("timeline-bottom")
                    }
                }
                .padding(.top, 8)
            }
            .coordinateSpace(name: "transcriptScroll")
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { scrollViewHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in scrollViewHeight = h }
                }
            )
            .overlay(alignment: .top) {
                if showNoteAboveIndicator {
                    NoteAboveIndicator(count: noteAboveCount) {
                        if let id = lastSubmittedNoteID {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                                proxy.scrollTo("note-\(id.uuidString)", anchor: .center)
                            }
                            withAnimation(.easeOut(duration: 0.2).delay(0.5)) {
                                showNoteAboveIndicator = false
                                noteAboveCount = 0
                            }
                        }
                    }
                    .padding(.top, 6)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: showNoteAboveIndicator)
            .onChange(of: liveState.segments.count) { _, _ in
                if !isNoteInputFocused {
                    withAnimation { proxy.scrollTo("timeline-bottom", anchor: .bottom) }
                    if showNoteAboveIndicator {
                        withAnimation(.easeOut(duration: 0.15).delay(0.3)) {
                            showNoteAboveIndicator = false
                            noteAboveCount = 0
                        }
                    }
                }
            }
            .onChange(of: liveState.userNotes.count) { _, _ in
                if !isNoteInputFocused {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        proxy.scrollTo("timeline-bottom", anchor: .bottom)
                    }
                }
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    // MARK: - Speaker Group View

    private func speakerGroupView(group: TimelineGroup, source: DiarizationSource) -> some View {
        let isLocal = source == .local
        let badgeColor = isLocal ? Self.pastelBlue : Self.pastelGreen
        let tintColor = isLocal ? Self.pastelBlueTint : Self.pastelGreenTint
        let label: String = {
            if source == .unknown { return "" }
            return isLocal ? "Me" : "Mac OS"
        }()
        let timeRange: String = {
            if group.entries.count > 1 && group.startTimestamp != group.endTimestamp {
                return "\(formatTimestamp(group.startTimestamp)) – \(formatTimestamp(group.endTimestamp))"
            }
            return formatTimestamp(group.startTimestamp)
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // Group header
            HStack(spacing: 8) {
                if source != .unknown {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badgeColor))
                }

                Spacer()

                Text(timeRange)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)

            // Segment text joined into flowing prose
            Text(group.entries.compactMap { entry -> String? in
                if case .segment(let segment, _) = entry { return segment.text }
                return nil
            }.joined(separator: " "))
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(source == .unknown ? Color.clear : tintColor)
        )
        .padding(.horizontal, 4)
    }

    // MARK: - Note Group View

    private func noteGroupView(group: TimelineGroup) -> some View {
        ForEach(group.entries) { entry in
            if case .note(let note) = entry {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Note")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Self.pastelAmber))

                        Text("You")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Self.pastelAmberText)

                        Spacer()

                        Text(formatTimestamp(note.timestamp))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Self.pastelAmberText.opacity(0.7))
                    }
                    .padding(.bottom, 6)

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 12))
                            .foregroundColor(Self.pastelAmberText)
                        Text(note.text)
                            .font(.system(size: 14))
                            .foregroundColor(Self.pastelAmberText)
                            .italic()
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Self.pastelAmberTint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Self.pastelAmber.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 4)
                .id("note-\(note.id.uuidString)")
                .background(
                    Group {
                        if note.id == lastSubmittedNoteID {
                            GeometryReader { noteGeo in
                                Color.clear
                                    .onChange(of: noteGeo.frame(in: .named("transcriptScroll")).minY) { _, minY in
                                        if showNoteAboveIndicator && minY >= -20 && minY < scrollViewHeight {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                showNoteAboveIndicator = false
                                                noteAboveCount = 0
                                            }
                                        }
                                    }
                            }
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.97, anchor: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }

    // MARK: - Notes Sidebar

    private var notesSidebarPane: some View {
        VStack(spacing: 0) {
            // Notes list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(liveState.userNotes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@ \(formatTimestamp(note.timestamp))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Self.pastelAmberText)
                            Text(note.text)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }

            Divider()

            // Input area with timestamp badge
            noteInputArea
        }
    }

    private var noteInputArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp badge — visible when field is focused
            if let stamp = liveState.noteFocusTimestamp {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10))
                        .foregroundStyle(Self.pastelAmberText)
                    Text("@ \(formatTimestamp(stamp))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Self.pastelAmberText)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Self.pastelAmber.opacity(0.2))
                        .overlay(
                            Capsule()
                                .stroke(Self.pastelAmber.opacity(0.5), lineWidth: 0.75)
                        )
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            TextField("Jot a note...", text: $liveState.noteInputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isNoteInputFocused ? Self.pastelAmber.opacity(0.9) : Self.pastelAmber.opacity(0.5),
                            lineWidth: isNoteInputFocused ? 1.5 : 1
                        )
                        .animation(.easeOut(duration: 0.12), value: isNoteInputFocused)
                )
                .focused($isNoteInputFocused)
                .onSubmit { submitNote() }

            Button { submitNote() } label: {
                Text("Add Note")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.pastelAmber)
            .disabled(liveState.noteInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(8)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: liveState.noteFocusTimestamp != nil)
        .onChange(of: isNoteInputFocused) { _, focused in
            if focused {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    liveState.noteFocusTimestamp = totalDuration
                }
            } else if liveState.noteInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.easeOut(duration: 0.15)) {
                    liveState.noteFocusTimestamp = nil
                }
            }
        }
    }

    private func submitNote() {
        let text = liveState.noteInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let stamp = liveState.noteFocusTimestamp ?? totalDuration
        let note = UserNote(text: text, timestamp: stamp)
        liveState.userNotes.append(note)
        liveState.noteInputText = ""
        liveState.noteFocusTimestamp = nil

        // Unfocus note input so transcript auto-scrolling resumes,
        // giving the user visual confirmation that live transcription continues.
        isNoteInputFocused = false

        // Show "note above" indicator since transcript has scrolled past insertion point
        lastSubmittedNoteID = note.id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            noteAboveCount += 1
            showNoteAboveIndicator = true
        }
    }

    // MARK: - Recording Control

    private func requestScreenRecordingPermission() {
        Settings.shared.pendingScreenRecordingGrant = true
        appDelegate?.minimizeMeetingWindowForPermission()
        // Delay permission request so the window hides first, ensuring the
        // macOS System Settings dialog appears visibly in the foreground.
        // Use a cancellable work item so disappearing the view cancels the request.
        permissionWorkItem?.cancel()
        let workItem = DispatchWorkItem { CGRequestScreenCaptureAccess() }
        permissionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func handleRecordingToggle() {
        if liveState.isRecording {
            Task { await stopRecording() }
        } else if liveState.status == .missingPermissions {
            requestScreenRecordingPermission()
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
            liveState.isNotesSidebarVisible = true
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
        liveState.statusMessage = "Recording complete"

        store.isRecording = false
        appDelegate?.isMeetingRecording = false

        // Auto-save to library (update existing record if continuing, otherwise create new)
        do {
            let duration = totalDuration
            let record: MeetingRecord
            if let existingID = liveState.lastSavedRecordID {
                record = try await store.updateRecordedMeeting(
                    id: existingID,
                    segments: liveState.segments,
                    userNotes: liveState.userNotes,
                    duration: duration
                )
            } else {
                record = try await store.saveRecordedMeeting(
                    segments: liveState.segments,
                    userNotes: liveState.userNotes,
                    duration: duration,
                    type: selectedType
                )
            }
            liveState.lastSavedRecordID = record.id
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
        audioUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak mixedAudioRecorder, weak liveState] t in
            guard let recorder = mixedAudioRecorder, let state = liveState, t.isValid, state.isActive else {
                t.invalidate()
                return
            }
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
        liveState.userNotes.removeAll()
        liveState.noteInputText = ""
        liveState.noteFocusTimestamp = nil
        liveState.isNotesSidebarVisible = false
        liveState.recordingSessions.removeAll()
        liveState.elapsedTime = 0
        liveState.sessionStartDate = nil
        liveState.lastSavedRecordID = nil
        liveState.statusMessage = "Ready to start"
        liveState.status = .ready
        showNoteAboveIndicator = false
        noteAboveCount = 0
        lastSubmittedNoteID = nil
        continuousTranscriber.clearSegments()
    }

    private func resetForNewRecording() {
        clearTranscript()
        Task { await startRecording() }
    }

    private func continueRecording() {
        Task {
            await startRecording()
        }
    }

    // MARK: - Status Check

    private func checkStatus() {
        if liveState.status == .completed { return }
        if !whisperService.isModelLoaded {
            liveState.status = .missingModel
            return
        }
        if !SystemAudioRecorder.hasPermission() {
            liveState.status = .missingPermissions
            return
        }
        if Settings.shared.pendingScreenRecordingGrant {
            Settings.shared.pendingScreenRecordingGrant = false
        }
        liveState.status = .ready
    }

    // MARK: - Callbacks

    private func setupTranscriberCallbacks() {
        continuousTranscriber.onSegmentTranscribed = { segment in
            Task { @MainActor [weak liveState] in
                liveState?.segments.append(segment)
            }
        }
        continuousTranscriber.onStatusUpdate = { status in
            Task { @MainActor [weak liveState] in
                guard let state = liveState, state.isRecording else { return }
                state.statusMessage = status
            }
        }
    }

    private func setupAudioRecorderCallback() {
        mixedAudioRecorder.onAudioChunkWithSource = { [weak continuousTranscriber] chunk in
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

// MARK: - Note Above Indicator

@available(macOS 13.0, *)
private struct NoteAboveIndicator: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                Text(count == 1 ? "1 note above" : "\(count) notes above")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(MeetingRecordTab.pastelAmber)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
