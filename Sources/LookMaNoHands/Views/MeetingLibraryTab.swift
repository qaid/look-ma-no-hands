import SwiftUI
import UniformTypeIdentifiers

/// Library tab — displays all saved meetings, handles import, and manages retention settings
@available(macOS 13.0, *)
struct MeetingLibraryTab: View {

    // MARK: - Dependencies

    let store: MeetingStore
    let whisperService: WhisperService
    var onMeetingSelected: (MeetingRecord) -> Void

    // MARK: - State

    @State private var searchText = ""
    @State private var typeFilter: MeetingType? = nil
    @State private var showImportTranscriptPanel = false
    @State private var showImportAudioPanel = false
    @State private var importProgress: Double = 0
    @State private var importStatusMessage = ""
    @State private var showImportProgress = false
    @State private var importType: MeetingType = .general
    @State private var showImportTypeSheet = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportIsAudio = false
    @State private var showDeleteConfirmation = false
    @State private var recordToDelete: MeetingRecord?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            if filteredMeetings.isEmpty {
                emptyState
            } else {
                meetingList
            }

            Divider()

            importBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            retentionSettingsView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .sheet(isPresented: $showImportProgress) {
            importProgressSheet
        }
        .sheet(isPresented: $showImportTypeSheet) {
            importTypeSheet
        }
        .confirmationDialog(
            "Delete Meeting?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let record = recordToDelete {
                    try? store.delete(record)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the meeting and all associated files.")
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search meetings", text: $searchText)
                .textFieldStyle(.plain)

            Picker("Filter by type", selection: $typeFilter) {
                Text("All types").tag(MeetingType?.none)
                ForEach(MeetingType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)
        }
    }

    // MARK: - Meeting List

    private var filteredMeetings: [MeetingRecord] {
        store.meetings.filter { record in
            let matchesSearch = searchText.isEmpty || record.title.localizedCaseInsensitiveContains(searchText)
            let matchesType = typeFilter == nil || record.meetingType == typeFilter
            return matchesSearch && matchesType
        }
    }

    private var meetingList: some View {
        List(filteredMeetings) { record in
            MeetingLibraryRow(record: record, store: store)
                .contentShape(Rectangle())
                .onTapGesture { onMeetingSelected(record) }
                .contextMenu {
                    Button("Open in Analyze") { onMeetingSelected(record) }
                    Divider()
                    Button("Export Transcript...") { exportTranscript(for: record) }
                    if record.notesFilename != nil {
                        Button("Export Notes...") { exportNotes(for: record) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        recordToDelete = record
                        showDeleteConfirmation = true
                    }
                }
        }
        .listStyle(.inset)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty && typeFilter == nil ? "No meetings yet" : "No meetings match your filters")
                .font(.system(size: 16, weight: .medium))
            Text("Meetings are saved automatically when you stop recording,\nor import transcript and audio files below.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Import Bar

    private var importBar: some View {
        HStack(spacing: 12) {
            Button {
                pendingImportIsAudio = false
                showImportTypeSheet = true
            } label: {
                Label("Import Transcript...", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(store.isImportingAudio)

            Button {
                pendingImportIsAudio = true
                showImportTypeSheet = true
            } label: {
                Label("Import Audio...", systemImage: "waveform.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(store.isRecording || store.isImportingAudio)
            .help(store.isRecording ? "Stop recording before importing audio" : "Import an audio file for transcription")

            Spacer()
        }
    }

    // MARK: - Retention Settings

    private var retentionSettingsView: some View {
        HStack(spacing: 16) {
            Text("Retention:")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Picker("Keep", selection: Binding(
                get: { Settings.shared.meetingRetentionDays },
                set: {
                    Settings.shared.meetingRetentionDays = $0
                    store.applyRetentionPolicy()
                }
            )) {
                Text("Forever").tag(0)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("1 year").tag(365)
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            Picker("Max count", selection: Binding(
                get: { Settings.shared.meetingRetentionCount },
                set: {
                    Settings.shared.meetingRetentionCount = $0
                    store.applyRetentionPolicy()
                }
            )) {
                Text("Unlimited").tag(0)
                Text("10 meetings").tag(10)
                Text("25 meetings").tag(25)
                Text("50 meetings").tag(50)
                Text("100 meetings").tag(100)
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()

            Text("\(store.meetings.count) meetings stored")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Import Type Sheet

    private var importTypeSheet: some View {
        VStack(spacing: 20) {
            Text(pendingImportIsAudio ? "Import Audio File" : "Import Transcript")
                .font(.system(size: 18, weight: .semibold))

            Text("Select a meeting type for analysis:")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Picker("Meeting type", selection: $importType) {
                ForEach(MeetingType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.radioGroup)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showImportTypeSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(pendingImportIsAudio ? "Choose Audio File..." : "Choose File...") {
                    showImportTypeSheet = false
                    if pendingImportIsAudio {
                        presentAudioImportPanel()
                    } else {
                        presentTranscriptImportPanel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(28)
        .frame(width: 380)
    }

    // MARK: - Import Progress Sheet

    private var importProgressSheet: some View {
        VStack(spacing: 16) {
            Text("Transcribing Audio...")
                .font(.system(size: 16, weight: .semibold))

            ProgressView(value: importProgress)
                .frame(width: 300)

            Text(importStatusMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 360)
    }

    // MARK: - Panel Helpers

    private func presentTranscriptImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "srt") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    _ = try await store.importTranscript(from: url, type: importType)
                } catch {
                    // Error surfaced via status; no-op here
                }
            }
        }
    }

    private func presentAudioImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = AudioFileImporter.supportedTypes
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importProgress = 0
            importStatusMessage = "Starting transcription..."
            showImportProgress = true

            Task {
                do {
                    _ = try await store.importAudio(
                        from: url,
                        type: importType,
                        whisperService: whisperService
                    ) { progress, chunk in
                        await MainActor.run {
                            importProgress = progress
                            importStatusMessage = chunk.prefix(80) + (chunk.count > 80 ? "…" : "")
                        }
                    }
                    await MainActor.run { showImportProgress = false }
                } catch {
                    await MainActor.run {
                        showImportProgress = false
                        importStatusMessage = "Failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Export Helpers

    private func exportTranscript(for record: MeetingRecord) {
        guard let text = try? store.transcriptText(for: record) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(record.title)-transcript.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportNotes(for record: MeetingRecord) {
        guard let text = try? store.notesText(for: record) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(record.title)-notes.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Row View

@available(macOS 13.0, *)
private struct MeetingLibraryRow: View {
    let record: MeetingRecord
    let store: MeetingStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.meetingType.icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(record.meetingType.displayName, systemImage: record.meetingType.icon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(formatDuration(record.duration))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text("\(record.segmentCount) segments")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if record.notesFilename != nil {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Spacer()

            Text(record.createdAt, style: .relative)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
