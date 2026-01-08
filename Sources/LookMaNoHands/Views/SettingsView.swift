import SwiftUI
import AVFoundation
import ApplicationServices

/// Settings window for configuring Look Ma No Hands
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
    // Permission states (would be updated by checking actual permissions)
    @State private var micPermission: PermissionState = .unknown
    @State private var accessibilityPermission: PermissionState = .unknown
    @State private var ollamaStatus: ConnectionState = .unknown
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            modelsTab
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
            
            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 500, height: 350)
        .onAppear {
            checkPermissions()
            checkOllamaStatus()
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                Picker("Trigger Key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .pickerStyle(.menu)
                
                Text("Press this key to start and stop recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Toggle("Show recording indicator", isOn: $settings.showIndicator)
                
                Text("Display a floating indicator while recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Toggle("Enable smart formatting", isOn: $settings.enableFormatting)
                
                Text("Use AI to format transcribed text (requires Ollama)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .padding()
    }
    
    // MARK: - Models Tab
    
    private var modelsTab: some View {
        Form {
            Section("Whisper (Transcription)") {
                Picker("Model", selection: $settings.whisperModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                
                Text("Larger models are more accurate but slower")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Ollama (Formatting)") {
                TextField("Model name", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                
                Text("The Ollama model used for formatting (e.g., llama3.2:3b)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    connectionStatusView(ollamaStatus, label: "Ollama")
                    
                    Spacer()
                    
                    Button("Check Connection") {
                        checkOllamaStatus()
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Permissions Tab
    
    private var permissionsTab: some View {
        Form {
            Section("Required Permissions") {
                permissionRow(
                    title: "Microphone",
                    description: "Required to capture your voice",
                    state: micPermission,
                    action: requestMicrophonePermission
                )
                
                permissionRow(
                    title: "Accessibility",
                    description: "Required to insert text into other apps",
                    state: accessibilityPermission,
                    action: openAccessibilityPreferences
                )
            }
            
            Section {
                Button("Refresh Permission Status") {
                    checkPermissions()
                }
            }
            
            Spacer()
        }
        .padding()
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
        .padding()
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    private func checkOllamaStatus() {
        // TODO: Implement actual HTTP check to localhost:11434
        ollamaStatus = .checking
        
        // Simulate async check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // This would be replaced with actual HTTP check
            self.ollamaStatus = .unknown
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

