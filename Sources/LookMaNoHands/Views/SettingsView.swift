import SwiftUI
import AVFoundation
import ApplicationServices

/// Settings tabs
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case recording = "Recording"
    case vocabulary = "Vocabulary"
    case models = "Models"
    case permissions = "Permissions"
    case diagnostics = "Diagnostics"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .recording: return "mic.circle"
        case .vocabulary: return "text.book.closed"
        case .models: return "cpu"
        case .permissions: return "lock.shield"
        case .diagnostics: return "ant.circle"
        case .about: return "info.circle"
        }
    }
}

/// Settings window for configuring Look Ma No Hands
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    // Permission states (would be updated by checking actual permissions)
    @State private var micPermission: PermissionState = .unknown
    @State private var accessibilityPermission: PermissionState = .unknown
    @State private var ollamaStatus: ConnectionState = .unknown
    @State private var isDownloadingModel = false
    @State private var modelDownloadProgress: Double = 0.0
    @State private var modelDownloadError: String?
    @State private var modelAvailability: [WhisperModel: Bool] = [:]

    // Selected tab (optional for NavigationSplitView)
    @State private var selectedTab: SettingsTab? = .general

    // Hotkey change confirmation
    @State private var showingHotkeyConfirmation = false

    // Permission polling timer
    @State private var permissionCheckTimer: Timer?

    // Update checking state
    @State private var availableUpdate: UpdateService.UpdateInfo?
    @State private var isCheckingForUpdates = false
    @State private var updateCheckError: String?

    // Track permission changes for restart prompt
    @State private var permissionsChanged = false
    @State private var previousMicPermission: PermissionState = .unknown
    @State private var previousAccessibilityPermission: PermissionState = .unknown

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 750, minHeight: 450)
        .onAppear {
            checkPermissions()
            checkWhisperModelStatus()
            // Start permission polling if on permissions tab
            if selectedTab == .permissions {
                startPermissionPolling()
            }
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(SettingsTab.allCases, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                Label(tab.rawValue, systemImage: tab.icon)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .onChange(of: selectedTab) { oldValue, newValue in
            if let newValue = newValue {
                handleTabChange(to: newValue)
            }
        }
    }

    // MARK: - Detail Pane

    private var detailContent: some View {
        ScrollView {
            Group {
                if let selectedTab = selectedTab {
                    contentForTab(selectedTab)
                } else {
                    emptyStateView
                }
            }
            .padding()
            .padding(.trailing, 12)
        }
        .navigationTitle(selectedTab?.rawValue ?? "Settings")
    }

    @ViewBuilder
    private func contentForTab(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: generalTab
        case .recording: recordingTab
        case .vocabulary: vocabularyTab
        case .models: modelsTab
        case .permissions: permissionsTab
        case .diagnostics: diagnosticsTab
        case .about: aboutTab
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a category")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            // Appearance Section
            Section {
                Toggle("Show recording indicator", isOn: $settings.showIndicator)
                    .help("Display a floating waveform visualizer while recording")

                if settings.showIndicator {
                    Picker("Position", selection: $settings.indicatorPosition) {
                        ForEach(IndicatorPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.leading, 20)
                    .help("Choose where the waveform visualizer appears on screen")
                }
            } header: {
                Text("Appearance")
                    .font(.headline)
            } footer: {
                if settings.showIndicator {
                    Text(positionHelpText(for: settings.indicatorPosition))
                        .font(.caption)
                } else {
                    Text("A floating waveform shows audio levels in real-time while recording")
                        .font(.caption)
                }
            }

            // Startup Section
            Section {
                Toggle("Show launch confirmation", isOn: $settings.showLaunchConfirmation)
                    .help("Display a brief splash screen when the app launches")
            } header: {
                Text("Startup")
                    .font(.headline)
            } footer: {
                Text("Brief splash screen appears for 2 seconds. Click or press any key to dismiss immediately.")
                    .font(.caption)
            }

            // Advanced Section (collapsed by default)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    // Run Setup Wizard
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showSetupWizardRestartConfirmation()
                        } label: {
                            Label("Run Setup Wizard Again", systemImage: "arrow.clockwise")
                        }
                        .help("Re-run the initial onboarding experience")

                        Text("Reconfigure Whisper models, Ollama, and permissions. Requires app restart.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Reset Settings
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Reset All Settings to Defaults", role: .destructive) {
                            showResetConfirmation()
                        }
                        .help("Reset all preferences to factory defaults")

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("This will reset all preferences but won't delete downloaded models or affect system permissions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced")
                    .font(.headline)
            }

            Spacer()
        }
    }

    // MARK: - Recording Tab

    private var recordingTab: some View {
        Form {
            Section {
                Picker("Trigger Key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .onChange(of: settings.triggerKey) { _, newValue in
                    // Post notification when trigger key changes
                    NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)

                    // Show brief feedback that change was applied
                    showHotkeyChangeConfirmation()
                }

                // Show HotkeyRecorderView when custom is selected
                if settings.triggerKey == .custom {
                    HStack {
                        Text("Custom Hotkey")
                        Spacer()
                        HotkeyRecorderView(hotkey: $settings.customHotkey)
                            .onChange(of: settings.customHotkey) { _, _ in
                                NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)

                                // Show brief feedback that change was applied
                                showHotkeyChangeConfirmation()
                            }
                    }
                }

                Text("Press this key to start and stop recording")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show confirmation message when hotkey changes
                if showingHotkeyConfirmation {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Trigger key updated (no restart needed)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("Trigger Key")
            }

            Section {
                Picker("Microphone", selection: Binding(
                    get: { settings.audioDeviceManager.selectedDevice },
                    set: { settings.audioDeviceManager.selectDevice($0) }
                )) {
                    ForEach(settings.audioDeviceManager.availableDevices) { device in
                        Text(device.name).tag(device)
                    }
                }

                HStack {
                    Text("Select which microphone to use for dictation and meeting transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        settings.audioDeviceManager.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh device list")
                }
            } header: {
                Text("Audio Input")
            }

            Spacer()
        }
    }
    
    // MARK: - Vocabulary Tab

    private var vocabularyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Vocabulary")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Add words that dictation often gets wrong. Correct spellings are used to hint Whisper, and misheard forms are replaced after transcription.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Vocabulary list
            if settings.customVocabulary.isEmpty {
                VStack(spacing: 8) {
                    Text("No custom vocabulary entries yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Click \"Add Word\" to get started.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Column headers
                HStack(spacing: 8) {
                    Text("Heard as")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 160, alignment: .leading)
                    Text("Correct spelling")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Entries
                ForEach($settings.customVocabulary) { $entry in
                    HStack(spacing: 8) {
                        TextField("e.g. swift ui", text: $entry.phrase)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        TextField("e.g. SwiftUI", text: $entry.replacement)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        Toggle("", isOn: $entry.enabled)
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                        Button(role: .destructive) {
                            settings.customVocabulary.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this entry")
                    }
                }
            }

            // Add button
            Button {
                settings.customVocabulary.append(VocabularyEntry())
            } label: {
                Label("Add Word", systemImage: "plus")
            }
            .controlSize(.small)

            // Tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Leave \"Heard as\" blank for words where you just want to hint the correct spelling to Whisper.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding()
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        VStack(spacing: 0) {
            // Dictation Section
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dictation")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Voice-to-text using Whisper (Caps Lock trigger)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                // Model picker
                HStack {
                    Text("Model")
                        .frame(width: 80, alignment: .trailing)

                    Picker("", selection: $settings.whisperModel) {
                        ForEach(WhisperModel.allCases) { model in
                            HStack {
                                Text(model.displayName)
                                Spacer()
                                if let isAvailable = modelAvailability[model] {
                                    if isAvailable {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                            }
                            .tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .onChange(of: settings.whisperModel) { oldValue, newValue in
                        handleModelChange(to: newValue)
                    }

                    // Show model status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(modelStatusColor)
                            .frame(width: 8, height: 8)
                        Text(modelStatusText)
                            .font(.caption)
                    }
                    .frame(width: 100, alignment: .leading)
                }

                // Show download progress if downloading
                if isDownloadingModel {
                    HStack {
                        Spacer()
                            .frame(width: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                ProgressView(value: modelDownloadProgress)
                                    .frame(width: 200)
                                Text("\(Int(modelDownloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("Downloading \(settings.whisperModel.displayName)...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Show error if download failed
                if let error = modelDownloadError {
                    HStack {
                        Spacer()
                            .frame(width: 80)
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Help text
                HStack {
                    Spacer()
                        .frame(width: 80)
                    Text("Larger models are more accurate but slower")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 4)

                // Media pause toggle
                Toggle("Pause media during dictation", isOn: $settings.pauseMediaDuringDictation)
                    .font(.body)

                Text("Automatically pauses playing media when you start dictating and resumes it when you stop")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)

            Divider()

            // Meeting Transcription Section
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meeting Transcription")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("System audio recording with AI-powered notes (via Ollama)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                // Model name
                HStack {
                    Text("Model")
                        .frame(width: 80, alignment: .trailing)

                    TextField("", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .disabled(true)
                        .help("Ollama model configuration (currently fixed to qwen3:8b)")

                    connectionStatusView(ollamaStatus, label: "")
                        .frame(width: 100, alignment: .leading)
                }

                // Help text explaining why it's disabled
                HStack {
                    Spacer()
                        .frame(width: 80)
                    Text("Model selection will be customizable in a future update")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Connection check button
                HStack {
                    Spacer()
                        .frame(width: 80)

                    Button("Check Connection") {
                        checkOllamaStatus()
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)

            Spacer()
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            Section("Required for Dictation") {
                permissionRow(
                    title: "Microphone",
                    description: "Required to capture your voice for dictation",
                    state: micPermission,
                    action: requestMicrophonePermission
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Required to insert transcribed text into applications",
                    state: accessibilityPermission,
                    action: openAccessibilityPreferences
                )
            }

            if permissionsChanged {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permissions Changed")
                                .font(.headline)
                            Text("Restart the app to apply the new permissions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Restart App") {
                            restartApp()
                        }
                        .controlSize(.large)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Additional Info") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Meeting transcription requires Screen Recording permission")
                            .font(.caption)
                    }

                    Text("This permission is requested automatically when you start a meeting recording.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Permission status updates automatically")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .onAppear {
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }
    
    // MARK: - Diagnostics Tab

    private var diagnosticsTab: some View {
        VStack(spacing: 0) {
            // Memory Status Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Memory Status")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        // Force refresh
                        _ = MemoryMonitor.shared.getCurrentMemoryUsageMB()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Current Usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(MemoryMonitor.shared.getFormattedMemoryUsage())
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(memoryStatusColor)
                    }

                    VStack(alignment: .leading) {
                        Text("Peak Usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(MemoryMonitor.shared.peakMemoryUsageMB) MB")
                            .font(.title2)
                            .fontWeight(.medium)
                    }
                }

                // Memory status explanation
                HStack(spacing: 6) {
                    Image(systemName: memoryStatusIcon)
                        .foregroundColor(memoryStatusColor)
                        .font(.caption)
                    Text(memoryStatusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)

            Divider()

            // Log Files Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Log Files")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Open Log Folder") {
                        NSWorkspace.shared.open(Logger.shared.logDirectoryURL)
                    }
                    .controlSize(.small)
                }

                let logFiles = Logger.shared.getLogFiles()
                if logFiles.isEmpty {
                    Text("No log files found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(logFiles.prefix(3), id: \.self) { file in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                            Text(file.lastPathComponent)
                                .font(.caption)
                            Spacer()
                            Button("Open") {
                                NSWorkspace.shared.open(file)
                            }
                            .controlSize(.mini)
                        }
                    }
                    if logFiles.count > 3 {
                        Text("+ \(logFiles.count - 3) more files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)

            Divider()

            // Crash Reports Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Crash Reports")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Open Crash Folder") {
                        NSWorkspace.shared.open(CrashReporter.shared.crashDirectoryURL)
                    }
                    .controlSize(.small)
                }

                let crashReports = CrashReporter.shared.getAllCrashReports()
                if crashReports.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No crash reports")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(crashReports.prefix(3), id: \.self) { file in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(file.lastPathComponent)
                                .font(.caption)
                            Spacer()
                            Button("View") {
                                NSWorkspace.shared.open(file)
                            }
                            .controlSize(.mini)
                        }
                    }
                    if crashReports.count > 3 {
                        Text("+ \(crashReports.count - 3) more reports")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Clear All Crash Reports", role: .destructive) {
                        CrashReporter.shared.deleteAllCrashReports()
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            .padding(16)

            Spacer()
        }
    }

    /// Color for memory status display
    private var memoryStatusColor: Color {
        let memoryMB = MemoryMonitor.shared.getCurrentMemoryUsageMB()
        if memoryMB > MemoryMonitor.shared.criticalThresholdMB {
            return .red
        } else if memoryMB > MemoryMonitor.shared.warningThresholdMB {
            return .orange
        } else {
            return .primary
        }
    }

    /// Icon for memory status
    private var memoryStatusIcon: String {
        let memoryMB = MemoryMonitor.shared.lastMemoryUsageMB
        if memoryMB > MemoryMonitor.shared.criticalThresholdMB {
            return "exclamationmark.triangle.fill"
        } else if memoryMB > MemoryMonitor.shared.warningThresholdMB {
            return "info.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    /// Explanatory message for current memory status
    private var memoryStatusMessage: String {
        let memoryMB = MemoryMonitor.shared.lastMemoryUsageMB
        if memoryMB > MemoryMonitor.shared.criticalThresholdMB {
            return "High memory usage. Stop recording if the app becomes unresponsive."
        } else if memoryMB > MemoryMonitor.shared.warningThresholdMB {
            return "Elevated but normal with a Whisper model loaded. Monitor during long recordings."
        } else {
            return "Normal. Memory includes the loaded Whisper model (~75-150 MB)."
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Look Ma No Hands")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                .foregroundColor(.secondary)

            Text("Fast, local voice dictation for macOS")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Divider()

            // Update check section
            VStack(spacing: 12) {
                HStack {
                    if isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let error = updateCheckError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let update = availableUpdate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.green)
                                Text("Update available: \(update.version)")
                                    .font(.headline)
                            }

                            HStack(spacing: 12) {
                                Button("Download Update") {
                                    NSWorkspace.shared.open(update.downloadURL)
                                }

                                if let url = URL(string: "https://github.com/qaid/look-ma-no-hands/releases/tag/v\(update.version)") {
                                    Button("View Release Notes") {
                                        NSWorkspace.shared.open(url)
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Up to date")
                            .font(.caption)
                    }

                    Spacer()

                    if !isCheckingForUpdates {
                        Button("Check Now") {
                            performUpdateCheck()
                        }
                        .controlSize(.small)
                    }
                }

                if let lastCheck = settings.lastUpdateCheckDate {
                    HStack {
                        Text("Last checked: \(lastCheck, style: .relative) ago")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                Toggle("Automatically check for updates on launch", isOn: $settings.checkForUpdatesOnLaunch)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Features")
                    .font(.headline)

                FeatureListItem(icon: "bolt.fill", text: "Lightning-fast transcription with Whisper")
                FeatureListItem(icon: "lock.fill", text: "100% local - your voice never leaves your Mac")
                FeatureListItem(icon: "waveform", text: "Smart text formatting and punctuation")
                FeatureListItem(icon: "keyboard", text: "Works in any app with Caps Lock trigger")
            }
            .frame(maxWidth: 400)

            Divider()

            VStack(spacing: 8) {
                Text("Powered By")
                    .font(.headline)

                Link(destination: URL(string: "https://github.com/ggerganov/whisper.cpp")!) {
                    Label("Whisper.cpp - Local speech recognition", systemImage: "link")
                        .font(.caption)
                }

                Link(destination: URL(string: "https://ollama.ai")!) {
                    Label("Ollama - Local LLM for meeting notes", systemImage: "link")
                        .font(.caption)
                }

                Link(destination: URL(string: "https://github.com/qaid/look-ma-no-hands")!) {
                    Label("Source code on GitHub", systemImage: "link")
                        .font(.caption)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            if availableUpdate == nil && !isCheckingForUpdates {
                performUpdateCheck()
            }
        }
    }

    // MARK: - Update Checking

    private func performUpdateCheck() {
        isCheckingForUpdates = true
        updateCheckError = nil
        availableUpdate = nil

        Task {
            do {
                let service = UpdateService()
                if let update = try await service.checkForUpdates() {
                    await MainActor.run {
                        self.availableUpdate = update
                        settings.lastUpdateCheckDate = Date()
                        self.isCheckingForUpdates = false
                    }
                } else {
                    await MainActor.run {
                        settings.lastUpdateCheckDate = Date()
                        self.isCheckingForUpdates = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.updateCheckError = error.localizedDescription
                    self.isCheckingForUpdates = false
                }
            }
        }
    }

    // MARK: - Helper Views

    /// Returns help text based on the selected indicator position
    private func positionHelpText(for position: IndicatorPosition) -> String {
        switch position {
        case .followCursor:
            return "Indicator follows your cursor/text insertion point (default)"
        case .top:
            return "Indicator stays at the top center of the screen"
        case .bottom:
            return "Indicator stays at the bottom center of the screen"
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        state: PermissionState,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            permissionStatusBadge(state)

            if state != .granted {
                Button(title == "Accessibility" ? "Open Settings" : "Grant") {
                    action()
                }
                .help(title == "Accessibility" ? "Opens System Settings where you can grant permission" : "Request \(title.lowercased()) permission")
            }
        }
        .padding(.vertical, 4)
    }
    
    private func permissionStatusBadge(_ state: PermissionState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
            Text(state.description)
                .font(.caption)
        }
    }
    
    private func connectionStatusView(_ state: ConnectionState, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
            Text("\(label): \(state.description)")
                .font(.caption)
        }
    }
    
    // MARK: - Permission Logic
    
    private func checkPermissions() {
        // Check microphone permission
        let newMicPermission: PermissionState
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            newMicPermission = .granted
        case .denied, .restricted:
            newMicPermission = .denied
        case .notDetermined:
            newMicPermission = .unknown
        @unknown default:
            newMicPermission = .unknown
        }

        // Check accessibility permission
        let trusted = AXIsProcessTrusted()
        let newAccessibilityPermission: PermissionState = trusted ? .granted : .denied

        // Detect permission changes (only after initial check)
        if previousMicPermission != .unknown || previousAccessibilityPermission != .unknown {
            if newMicPermission != previousMicPermission || newAccessibilityPermission != previousAccessibilityPermission {
                permissionsChanged = true
            }
        }

        previousMicPermission = newMicPermission
        previousAccessibilityPermission = newAccessibilityPermission
        micPermission = newMicPermission
        accessibilityPermission = newAccessibilityPermission
    }
    
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.micPermission = granted ? .granted : .denied
            }
        }
    }
    
    private func openAccessibilityPreferences() {
        // First, trigger the system prompt to add this app to Accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Also open System Settings to the Accessibility pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Permission Polling

    /// Start automatic permission status polling
    private func startPermissionPolling() {
        // Stop any existing timer first
        stopPermissionPolling()

        // Initial check
        checkPermissions()

        // Poll every second for permission changes
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkPermissions()
        }
    }

    /// Stop automatic permission status polling
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// Handle tab changes to manage permission polling
    private func handleTabChange(to newTab: SettingsTab) {
        if newTab == .permissions {
            startPermissionPolling()
        } else {
            stopPermissionPolling()
        }
    }

    private func checkOllamaStatus() {
        ollamaStatus = .checking

        Task {
            let ollamaService = OllamaService()
            let isAvailable = await ollamaService.isAvailable()

            await MainActor.run {
                self.ollamaStatus = isAvailable ? .connected : .disconnected
            }
        }
    }

    // MARK: - Model Management

    /// Check availability of all Whisper models
    private func checkWhisperModelStatus() {
        for model in WhisperModel.allCases {
            let exists = WhisperService.modelExists(named: model.rawValue)
            modelAvailability[model] = exists
        }
    }

    /// Handle when user switches models in the picker
    private func handleModelChange(to newModel: WhisperModel) {
        // Clear any previous error
        modelDownloadError = nil

        // Check if model exists
        let modelExists = WhisperService.modelExists(named: newModel.rawValue)

        if !modelExists {
            // Model doesn't exist, start download
            Task {
                await downloadModel(newModel)
            }
        } else {
            print("SettingsView: Model \(newModel.rawValue) already downloaded")
            // TODO: Notify AppDelegate to reload the model if needed
        }
    }

    /// Download a Whisper model
    private func downloadModel(_ model: WhisperModel) async {
        isDownloadingModel = true
        modelDownloadProgress = 0.0
        modelDownloadError = nil

        print("SettingsView: Starting download of \(model.rawValue) model...")

        do {
            try await WhisperService.downloadModel(named: model.rawValue) { progress in
                DispatchQueue.main.async {
                    self.modelDownloadProgress = progress
                }
            }

            // Download successful
            DispatchQueue.main.async {
                self.isDownloadingModel = false
                self.modelDownloadProgress = 1.0
                self.modelAvailability[model] = true
                print("SettingsView: Model \(model.rawValue) downloaded successfully")

                // TODO: Notify AppDelegate to reload the model
            }

        } catch {
            // Download failed
            DispatchQueue.main.async {
                self.isDownloadingModel = false
                self.modelDownloadError = "Download failed: \(error.localizedDescription)"
                print("SettingsView: Model download failed - \(error)")
            }
        }
    }

    /// Computed property for model status color
    private var modelStatusColor: Color {
        if isDownloadingModel {
            return .yellow
        } else if let isAvailable = modelAvailability[settings.whisperModel] {
            return isAvailable ? .green : .orange
        } else {
            return .gray
        }
    }

    /// Computed property for model status text
    private var modelStatusText: String {
        if isDownloadingModel {
            return "Downloading..."
        } else if let isAvailable = modelAvailability[settings.whisperModel] {
            return isAvailable ? "Downloaded" : "Not downloaded"
        } else {
            return "Checking..."
        }
    }

    // MARK: - Hotkey Change Feedback

    /// Show brief confirmation that hotkey change was applied
    private func showHotkeyChangeConfirmation() {
        showingHotkeyConfirmation = true

        // Hide the message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showingHotkeyConfirmation = false
            }
        }
    }

    // MARK: - Setup Wizard

    /// Show confirmation dialog to restart app and run setup wizard again
    private func showSetupWizardRestartConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "Look Ma No Hands needs to restart to run the setup wizard again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Reset onboarding flag
            settings.hasCompletedOnboarding = false

            // Force UserDefaults to synchronize immediately
            UserDefaults.standard.synchronize()

            // Small delay to ensure settings are written to disk
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Restart the app
                self.restartApp()
            }
        }
    }

    /// Show confirmation dialog before resetting all settings
    private func showResetConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings?"
        alert.informativeText = "This will restore all preferences to their default values. Downloaded models and system permissions will not be affected.\n\nThis action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            settings.resetToDefaults()
        }
    }

    /// Restart the application
    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundlePath),
                                          configuration: config) { _, error in
            if let error = error {
                print("Failed to relaunch app: \(error)")
            } else {
                // Only terminate if relaunch succeeded
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

/// Feature list item for About tab
struct FeatureListItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 20)

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Supporting Types

enum PermissionState {
    case unknown
    case granted
    case denied
    
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .granted: return "Granted"
        case .denied: return "Not Granted"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .granted: return .green
        case .denied: return .red
        }
    }
}

enum ConnectionState {
    case unknown
    case checking
    case connected
    case disconnected

    var description: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking..."
        case .connected: return "Connected"
        case .disconnected: return "Not Running"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .checking: return .yellow
        case .connected: return .green
        case .disconnected: return .red
        }
    }
}

