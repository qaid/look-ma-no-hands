import SwiftUI
import AVFoundation
import ApplicationServices

/// Settings tabs
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case recording = "Recording"
    case models = "Models"
    case permissions = "Permissions"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .recording: return "mic.circle"
        case .models: return "cpu"
        case .permissions: return "lock.shield"
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

    // Selected tab
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .recording:
                    recordingTab
                case .models:
                    modelsTab
                case .permissions:
                    permissionsTab
                case .about:
                    aboutTab
                }
            }
            .padding()
        }
        .frame(width: 550, height: 400)
        .onAppear {
            checkPermissions()
            checkOllamaStatus()
            checkWhisperModelStatus()
        }
    }
    
    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Show recording indicator", isOn: $settings.showIndicator)

                if settings.showIndicator {
                    Picker("Indicator Position", selection: $settings.indicatorPosition) {
                        ForEach(IndicatorPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text("Display a floating indicator while recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Display")
            }

            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Automatic formatting enabled")
                        .font(.body)
                }

                Text("Applies capitalization and punctuation to transcribed text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Text Formatting")
            }

            Section {
                Button {
                    // Reset onboarding flag and show restart alert
                    settings.hasCompletedOnboarding = false

                    let alert = NSAlert()
                    alert.messageText = "Restart Required"
                    alert.informativeText = "Please restart Look Ma No Hands to run the setup wizard again."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                } label: {
                    Text("Run Setup Wizard Again")
                }

                Text("Re-run the initial setup wizard to reconfigure Ollama, models, and permissions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Setup")
            }

            Spacer()

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
            }
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

                Text("Press this key to start and stop recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

                    connectionStatusView(ollamaStatus, label: "")
                        .frame(width: 100, alignment: .leading)
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
            }

            Section {
                Button {
                    checkPermissions()
                } label: {
                    Label("Refresh Permission Status", systemImage: "arrow.clockwise")
                }
            }

            Spacer()
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

            Text("Version 0.1.0")
                .foregroundColor(.secondary)

            Text("Local voice dictation with AI-powered formatting")
                .multilineTextAlignment(.center)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Link("Whisper.cpp on GitHub", destination: URL(string: "https://github.com/ggerganov/whisper.cpp")!)
                Link("Ollama", destination: URL(string: "https://ollama.ai")!)
            }

            Spacer()
        }
    }
    
    // MARK: - Helper Views
    
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
                Button("Grant") {
                    action()
                }
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
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            micPermission = .granted
        case .denied, .restricted:
            micPermission = .denied
        case .notDetermined:
            micPermission = .unknown
        @unknown default:
            micPermission = .unknown
        }

        // Check accessibility permission
        let trusted = AXIsProcessTrusted()
        accessibilityPermission = trusted ? .granted : .denied
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
        case .unknown: return "Unknown"
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

