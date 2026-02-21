import SwiftUI

/// Analyze tab — select a meeting, choose type, run LLM, view and export notes
@available(macOS 13.0, *)
struct MeetingAnalyzeTab: View {

    // MARK: - Dependencies

    let store: MeetingStore
    @Binding var selectedMeeting: MeetingRecord?

    // MARK: - State

    @State private var selectedType: MeetingType = .general
    @State private var customPrompt = ""
    @State private var transcript = ""
    @State private var notes = ""
    @State private var isAnalyzing = false
    @State private var analysisProgress: Double = 0
    @State private var streamedNotes = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var showTranscript = false
    @State private var lastProgressUpdate = Date()
    @State private var statusMessage = ""
    @State private var showPromptChangedAlert = false
    @State private var pendingTypeChange: MeetingType?

    private let analyzer = MeetingAnalyzer()

    // MARK: - Body

    var body: some View {
        if let meeting = selectedMeeting {
            analyzeView(for: meeting)
                .onChange(of: selectedMeeting?.id) { _, _ in loadMeeting() }
                .onAppear { loadMeeting() }
        } else {
            emptyState
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Meeting Selected")
                .font(.system(size: 18, weight: .semibold))
            Text("Select a meeting from the Library tab to analyze it.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Analyze View

    private func analyzeView(for meeting: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerView(for: meeting)

                Divider()

                // Meeting type picker
                typePicker

                Divider()

                // Prompt editor
                promptEditor

                // Process button
                processButton

                // Progress bar
                if isAnalyzing {
                    ProgressView(value: analysisProgress)
                        .padding(.top, 4)
                }

                // Status
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Notes output
                if !notes.isEmpty || !streamedNotes.isEmpty {
                    Divider()
                    notesView
                }

                // Transcript (collapsible)
                if !transcript.isEmpty {
                    Divider()
                    transcriptView
                }

                // Export bar
                if !notes.isEmpty {
                    Divider()
                    exportBar(for: meeting)
                }
            }
            .padding(24)
        }
        .alert("Change Meeting Type?", isPresented: $showPromptChangedAlert) {
            Button("Change Type") {
                if let newType = pendingTypeChange {
                    applyTypeChange(newType)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have edited the prompt. Changing the type will replace it with the default prompt for the new type.")
        }
    }

    // MARK: - Header

    private func headerView(for meeting: MeetingRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: meeting.meetingType.icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)

            Text(meeting.title)
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(meeting.createdAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("\(meeting.segmentCount) segments")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
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
            .onChange(of: selectedType) { oldType, newType in
                let defaultPrompt = Settings.shared.meetingTypePrompts[oldType.rawValue] ?? oldType.defaultPrompt
                if customPrompt != defaultPrompt {
                    pendingTypeChange = newType
                    selectedType = oldType  // revert until confirmed
                    showPromptChangedAlert = true
                } else {
                    applyTypeChange(newType)
                }
            }

            Spacer()
        }
    }

    private func applyTypeChange(_ type: MeetingType) {
        selectedType = type
        customPrompt = Settings.shared.meetingTypePrompts[type.rawValue] ?? type.defaultPrompt
        pendingTypeChange = nil
    }

    // MARK: - Prompt Editor

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset to default") {
                    customPrompt = selectedType.defaultPrompt
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            }

            TextEditor(text: $customPrompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Process Button

    private var processButton: some View {
        HStack {
            Button {
                if isAnalyzing {
                    cancelAnalysis()
                } else {
                    runAnalysis()
                }
            } label: {
                HStack(spacing: 8) {
                    if isAnalyzing {
                        ProgressView().scaleEffect(0.7).progressViewStyle(.circular)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? "Cancel" : "Process with Ollama")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(transcript.isEmpty)
            .keyboardShortcut("n", modifiers: .command)

            Spacer()
        }
    }

    // MARK: - Notes View

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 14, weight: .semibold))

            let displayNotes = isAnalyzing ? streamedNotes : notes
            if displayNotes.isEmpty {
                Text("Generating…")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                Text(displayNotes)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Transcript View

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showTranscript.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTranscript ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Transcript")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(.plain)

            if showTranscript {
                Text(transcript)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Export Bar

    private func exportBar(for meeting: MeetingRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(notes, forType: .string)
                statusMessage = "Notes copied to clipboard"
            } label: {
                Label("Copy Notes", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                saveNotes(for: meeting)
            } label: {
                Label("Save Notes...", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
                statusMessage = "Transcript copied to clipboard"
            } label: {
                Label("Copy Transcript", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    // MARK: - Analysis

    private func loadMeeting() {
        guard let meeting = selectedMeeting else { return }
        selectedType = meeting.meetingType
        customPrompt = Settings.shared.meetingTypePrompts[meeting.meetingType.rawValue] ?? meeting.meetingType.defaultPrompt
        transcript = (try? store.transcriptText(for: meeting)) ?? ""
        notes = (try? store.notesText(for: meeting)).flatMap { $0 } ?? ""
        streamedNotes = ""
        statusMessage = ""
    }

    private func runAnalysis() {
        guard !transcript.isEmpty else { return }

        // Persist prompt override for this type
        Settings.shared.meetingTypePrompts[selectedType.rawValue] = customPrompt

        isAnalyzing = true
        analysisProgress = 0
        streamedNotes = ""
        statusMessage = "Analyzing…"
        lastProgressUpdate = Date()

        let promptToUse = customPrompt
        let transcriptToUse = transcript

        analysisTask = Task {
            let estimatedLength = max(500, min(5000, Int(Double(transcriptToUse.count) * 0.20)))

            do {
                let result = try await analyzer.analyzeMeetingStreaming(
                    transcript: transcriptToUse,
                    customPrompt: promptToUse
                ) { receivedChars, chunk in
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        let now = Date()
                        if now.timeIntervalSince(lastProgressUpdate) >= 0.05 {
                            streamedNotes += chunk
                            let raw = Double(receivedChars) / Double(estimatedLength)
                            let scaled = -log(1 - min(raw, 0.95)) / 3.0
                            analysisProgress = min(scaled, 0.98)
                            lastProgressUpdate = now
                        }
                    }
                }

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    notes = result
                    streamedNotes = ""
                    analysisProgress = 1.0
                    isAnalyzing = false
                    statusMessage = "Notes generated successfully"
                }

                // Persist notes to disk
                if let meeting = selectedMeeting {
                    try? await store.saveNotes(result, for: meeting)
                }

                // Notify user
                await NotificationService.shared.sendNotification(
                    title: "Meeting Notes Ready",
                    body: "Your structured meeting notes have been generated."
                )
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    statusMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        streamedNotes = ""
        statusMessage = "Cancelled"
    }

    private func saveNotes(for meeting: MeetingRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(meeting.title)-notes.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? notes.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
