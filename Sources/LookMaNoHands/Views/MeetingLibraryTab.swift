import SwiftUI
import UniformTypeIdentifiers

/// Library tab — displays all saved meetings, handles import, and manages retention settings
@available(macOS 13.0, *)
struct MeetingLibraryTab: View {

    // MARK: - Types

    private enum ImportMode: Identifiable {
        case transcript, audio, clipboard
        var id: Self { self }

        var sheetTitle: String {
            switch self {
            case .transcript: return "Import Transcript"
            case .audio: return "Import Audio File"
            case .clipboard: return "Paste Transcript Text"
            }
        }

        var confirmButtonLabel: String {
            switch self {
            case .transcript: return "Choose File..."
            case .audio: return "Choose Audio File..."
            case .clipboard: return "Import"
            }
        }
    }

    // MARK: - Dependencies

    let store: MeetingStore
    let whisperService: WhisperService
    var onMeetingSelected: (MeetingRecord) -> Void

    // MARK: - State

    @State private var searchText = ""
    @State private var typeFilter: MeetingType? = nil
    @State private var importProgress: Double = 0
    @State private var importStatusMessage = ""
    @State private var showImportProgress = false
    @State private var importType: MeetingType = .general
    @State private var activeImportMode: ImportMode? = nil
    @State private var pendingPasteText = ""
    @State private var showDeleteConfirmation = false
    @State private var recordToDelete: MeetingRecord?
    @State private var importErrorMessage: String?
    @State private var showImportError = false

    // Rename
    @State private var recordToRename: MeetingRecord?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    // Selection mode
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .animation(.default, value: isSelectionMode)

            Divider()

            if filteredMeetings.isEmpty {
                emptyState
            } else {
                meetingList
            }
        }
        .sheet(isPresented: $showImportProgress) {
            importProgressSheet
        }
        .sheet(item: $activeImportMode) { mode in
            importTypeSheet(for: mode)
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
        .confirmationDialog(
            "Delete \(selectedIDs.count) Meeting\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedIDs.count) Meeting\(selectedIDs.count == 1 ? "" : "s")", role: .destructive) {
                bulkDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected meetings and all associated files.")
        }
        .alert("Rename Meeting", isPresented: $showRenameAlert) {
            TextField("Meeting title", text: $renameText)
            Button("Rename") {
                if let record = recordToRename {
                    try? store.renameMeeting(record, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new title for this meeting.")
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarView: some View {
        if isSelectionMode {
            selectionToolbar
        } else {
            normalToolbar
        }
    }

    private var normalToolbar: some View {
        VStack(spacing: 10) {
            // Row 1: Search + utility actions
            HStack(spacing: 8) {
                // Select toggle
                Button {
                    isSelectionMode = true
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(store.meetings.isEmpty)
                .help("Select meetings")

                // Search field with clear button
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)

                    TextField("Search meetings...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                        )
                }

                Divider()
                    .frame(height: 22)

                // Import menu
                Menu {
                    Button {
                        activeImportMode = .transcript
                    } label: {
                        Label("Import Transcript...", systemImage: "doc.badge.plus")
                    }
                    .disabled(store.isImportingAudio)

                    Button {
                        activeImportMode = .audio
                    } label: {
                        Label("Import Audio...", systemImage: "waveform.badge.plus")
                    }
                    .disabled(store.isRecording || store.isImportingAudio)

                    Button {
                        pendingPasteText = ""
                        activeImportMode = .clipboard
                    } label: {
                        Label("Paste Transcript Text", systemImage: "doc.on.clipboard")
                    }
                    .disabled(store.isImportingAudio)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                }
                .menuIndicator(.hidden)
                .help("Import a transcript or audio file")

                // Settings menu
                Menu {
                    Section("Retention") {
                        Picker("Keep", selection: retentionDaysBinding) {
                            Text("Forever").tag(0)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                            Text("180 days").tag(180)
                            Text("1 year").tag(365)
                        }
                    }
                    Section("Max count") {
                        Picker("Max count", selection: retentionCountBinding) {
                            Text("Unlimited").tag(0)
                            Text("10 meetings").tag(10)
                            Text("25 meetings").tag(25)
                            Text("50 meetings").tag(50)
                            Text("100 meetings").tag(100)
                        }
                    }
                    Divider()
                    Text("\(store.meetings.count) meetings stored")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                }
                .menuIndicator(.hidden)
                .help("Retention settings")
            }

            // Row 2: Type filter pills
            if !store.meetings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterPill("All", icon: "tray.full", isActive: typeFilter == nil) {
                            withAnimation(.easeInOut(duration: 0.15)) { typeFilter = nil }
                        }
                        ForEach(MeetingType.allCases) { type in
                            filterPill(type.displayName, icon: type.icon, isActive: typeFilter == type) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    typeFilter = (typeFilter == type) ? nil : type
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterPill(_ label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.3),
                                lineWidth: 0.5
                            )
                    )
            }
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Button("Cancel") {
                isSelectionMode = false
                selectedIDs.removeAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(.accentColor)

            Button {
                if selectedIDs.count == filteredMeetings.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(filteredMeetings.map(\.id))
                }
            } label: {
                Text(selectedIDs.count == filteredMeetings.count && !selectedIDs.isEmpty ? "Deselect All" : "Select All")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            Text(selectedIDs.isEmpty ? "Select items" : "\(selectedIDs.count) selected")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Spacer()

            // Export menu
            Menu {
                Button("Export Transcripts...") { bulkExportTranscripts() }
                Button("Export Notes...") { bulkExportNotes() }
                    .disabled(!selectedHaveNotes)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .foregroundColor(selectedIDs.isEmpty ? .secondary.opacity(0.5) : .secondary)
            }
            .menuIndicator(.hidden)
            .disabled(selectedIDs.isEmpty)
            .help("Export selected meetings")

            // Delete
            Button {
                showBulkDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(selectedIDs.isEmpty ? .secondary.opacity(0.5) : .red)
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty)
            .help("Delete selected meetings")
        }
    }

    // MARK: - Retention Bindings

    private var retentionDaysBinding: Binding<Int> {
        Binding(
            get: { Settings.shared.meetingRetentionDays },
            set: {
                Settings.shared.meetingRetentionDays = $0
                store.applyRetentionPolicy()
            }
        )
    }

    private var retentionCountBinding: Binding<Int> {
        Binding(
            get: { Settings.shared.meetingRetentionCount },
            set: {
                Settings.shared.meetingRetentionCount = $0
                store.applyRetentionPolicy()
            }
        )
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
            HStack(spacing: 8) {
                if isSelectionMode {
                    Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(selectedIDs.contains(record.id) ? .accentColor : .secondary)
                }

                MeetingLibraryRow(record: record, store: store)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelectionMode {
                    toggleSelection(record.id)
                } else {
                    onMeetingSelected(record)
                }
            }
            .contextMenu {
                if !isSelectionMode {
                    Button("Open in Analyze") { onMeetingSelected(record) }
                    Button("Rename...") {
                        recordToRename = record
                        renameText = record.title
                        showRenameAlert = true
                    }
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
            Text("Meetings are saved automatically when you stop recording,\nor use the import button in the toolbar above.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Import Type Sheet

    @ViewBuilder
    private func importTypeSheet(for mode: ImportMode) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(mode.sheetTitle)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            if mode == .clipboard {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $pendingPasteText)
                        .font(.system(size: 13))
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )

                    if pendingPasteText.isEmpty {
                        Text("Paste your transcript here...")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select a meeting type for analysis:")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Picker("Meeting type", selection: $importType) {
                    ForEach(MeetingType.allCases) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") {
                    activeImportMode = nil
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(mode.confirmButtonLabel) {
                    activeImportMode = nil
                    switch mode {
                    case .clipboard:
                        importFromClipboard()
                    case .audio:
                        presentAudioImportPanel()
                    case .transcript:
                        presentTranscriptImportPanel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(mode == .clipboard && pendingPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: mode == .clipboard ? 480 : 380)
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
                    await MainActor.run {
                        importErrorMessage = error.localizedDescription
                        showImportError = true
                    }
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
                            importStatusMessage = chunk.prefix(80) + (chunk.count > 80 ? "..." : "")
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

    private func importFromClipboard() {
        let text = pendingPasteText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            do {
                _ = try await store.importTranscriptFromText(text, type: importType)
            } catch {
                await MainActor.run {
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            }
        }
    }

    // MARK: - Selection Helpers

    private var selectedRecords: [MeetingRecord] {
        filteredMeetings.filter { selectedIDs.contains($0.id) }
    }

    private var selectedHaveNotes: Bool {
        selectedRecords.contains { $0.notesFilename != nil }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    // MARK: - Bulk Actions

    private func bulkExportTranscripts() {
        let records = selectedRecords
        guard !records.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export \(records.count) transcript\(records.count == 1 ? "" : "s")"
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            for record in records {
                guard let text = try? store.transcriptText(for: record) else { continue }
                let filename = sanitizeFilename(record.title) + "-transcript.txt"
                let dest = folder.appendingPathComponent(filename)
                try? text.write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }

    private func bulkExportNotes() {
        let records = selectedRecords.filter { $0.notesFilename != nil }
        guard !records.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export \(records.count) note\(records.count == 1 ? "" : "s")"
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            for record in records {
                guard let text = try? store.notesText(for: record) else { continue }
                let filename = sanitizeFilename(record.title) + "-notes.md"
                let dest = folder.appendingPathComponent(filename)
                try? text.write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }

    private func bulkDelete() {
        let records = selectedRecords
        for record in records {
            try? store.delete(record)
        }
        selectedIDs.removeAll()
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

                    Text("\u{00B7}")
                        .foregroundColor(.secondary)

                    Text(formatDuration(record.duration))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("\u{00B7}")
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
