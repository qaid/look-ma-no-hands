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
    @State private var showTranscript = true
    @State private var showPrompt = false
    @State private var hasProcessed = false
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
                .foregroundStyle(.secondary)
            Text("No Meeting Selected")
                .font(.system(size: 18, weight: .semibold))
            Text("Select a meeting from the Library tab to analyze it.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Analyze View

    private func analyzeView(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header area — never scrolls
            VStack(alignment: .leading, spacing: 0) {
                headerView(for: meeting)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider()

                typePicker
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                Divider()
            }

            // Scrollable content area — fills remaining space without growing the window
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Transcript — bounded scrollable pane
                    transcriptSection
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    Divider()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)

                    // Prompt — bounded, collapsed by default
                    promptSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    // Status
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                    }

                    // Notes — bounded scrollable pane, shown after processing
                    if !notes.isEmpty {
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)

                        notesSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .foregroundStyle(.tint)

            Text(meeting.title)
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(meeting.createdAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(meeting.segmentCount) segments")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Type Picker

    private var typePicker: some View {
        HStack(spacing: 8) {
            Text("Meeting type:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

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

            // CTAs inline with meeting type selector, above transcript (#207)
            actionRow
        }
    }

    private func applyTypeChange(_ type: MeetingType) {
        selectedType = type
        customPrompt = Settings.shared.meetingTypePrompts[type.rawValue] ?? type.defaultPrompt
        pendingTypeChange = nil
    }

    // MARK: - Action Row

    // Minimum button width that can accommodate both the "Re-process" label and
    // the "Cancel" label (with spinner), so the button never changes size when
    // toggling between the two states.
    private let processButtonMinWidth: CGFloat = 110

    @ViewBuilder
    private var actionRow: some View {
        if isAnalyzing {
            // Cancel button with inline spinner to indicate background work (#current)
            Button {
                cancelAnalysis()
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Cancel")
                }
                .frame(minWidth: processButtonMinWidth)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])
        } else {
            // Process / Re-process
            Button {
                runAnalysis()
            } label: {
                Label(
                    hasProcessed ? "Re-process" : "Process",
                    systemImage: "sparkles"
                )
                .frame(minWidth: processButtonMinWidth)
            }
            .buttonStyle(.borderedProminent)
            .disabled(transcript.isEmpty)
            .keyboardShortcut("n", modifiers: .command)
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(notes, forType: .string)
            statusMessage = "Notes copied to clipboard"
        } label: {
            Label("Copy Notes", systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .disabled(notes.isEmpty)

        Button {
            if let meeting = selectedMeeting { saveNotes(for: meeting) }
        } label: {
            Label("Save Notes...", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(notes.isEmpty)

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            statusMessage = "Transcript copied to clipboard"
        } label: {
            Label("Copy Transcript", systemImage: "doc.text")
        }
        .buttonStyle(.bordered)
        .disabled(transcript.isEmpty)
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showTranscript.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTranscript ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Transcript")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(.plain)

            if showTranscript {
                ScrollView {
                    Text(transcript)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showPrompt.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showPrompt ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Prompt")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(.plain)

            if showPrompt {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Reset to default") {
                            customPrompt = selectedType.defaultPrompt
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.tint)
                    }

                    TextEditor(text: $customPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 160)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Notes")
                    .font(.system(size: 14, weight: .semibold))
                if hasProcessed {
                    Text("Processed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            ScrollView {
                Group {
                    if let attributed = try? AttributedString(
                        markdown: notes,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(attributed)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    } else {
                        Text(notes)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Analysis

    private func loadMeeting() {
        guard let meeting = selectedMeeting else { return }
        selectedType = meeting.meetingType
        customPrompt = Settings.shared.meetingTypePrompts[meeting.meetingType.rawValue] ?? meeting.meetingType.defaultPrompt
        transcript = (try? store.transcriptText(for: meeting)) ?? ""
        notes = (try? store.notesText(for: meeting)).flatMap { $0 } ?? ""
        hasProcessed = !notes.isEmpty
        showTranscript = true
        showPrompt = false
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
                    hasProcessed = true
                    statusMessage = "Notes generated successfully"
                    // Collapse transcript and prompt so the notes section is prominent
                    showTranscript = false
                    showPrompt = false
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
