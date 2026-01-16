import SwiftUI
import AVFoundation
import AppKit

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var onboardingState = OnboardingState()

    // Services (injected from AppDelegate)
    let whisperService: WhisperService
    let ollamaService: OllamaService
    let onComplete: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            VStack(spacing: 0) {
                // Spacer for progress indicator
                Spacer()
                    .frame(height: 80)

                // Content area - using ZStack instead of TabView to avoid page indicators
                ZStack {
                    if onboardingState.currentStep == .welcome {
                        WelcomeStepView(onboardingState: onboardingState)
                            .transition(.opacity)
                    } else if onboardingState.currentStep == .ollama {
                        OllamaStepView(
                            onboardingState: onboardingState,
                            ollamaService: ollamaService
                        )
                        .transition(.opacity)
                    } else if onboardingState.currentStep == .whisperModel {
                        WhisperModelStepView(
                            onboardingState: onboardingState,
                            whisperService: whisperService
                        )
                        .transition(.opacity)
                    } else if onboardingState.currentStep == .permissions {
                        PermissionsStepView(
                            onboardingState: onboardingState
                        )
                        .transition(.opacity)
                    } else if onboardingState.currentStep == .complete {
                        CompletionStepView(
                            onboardingState: onboardingState
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: onboardingState.currentStep)

                Spacer()
                    .frame(height: 20)

                // Navigation buttons
                OnboardingNavigationView(
                    state: onboardingState,
                    onComplete: completeOnboarding
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }

            // Progress indicator (floating on top)
            ProgressIndicatorView(currentStep: onboardingState.currentStep)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 600)
    }

    private func completeOnboarding() {
        Settings.shared.hasCompletedOnboarding = true
        onComplete()
        dismiss()
    }
}

// MARK: - Progress Indicator

struct ProgressIndicatorView: View {
    let currentStep: OnboardingState.Step

    private let stepTitles = ["Welcome", "Ollama", "Model", "Permissions", "Complete"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(OnboardingState.Step.allCases.enumerated()), id: \.element) { index, step in
                VStack(spacing: 8) {
                    // Step circle
                    ZStack {
                        Circle()
                            .strokeBorder(
                                step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3),
                                lineWidth: 2
                            )
                            .background(
                                Circle()
                                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.clear)
                            )
                            .frame(width: 32, height: 32)

                        if step.rawValue < currentStep.rawValue {
                            // Checkmark for completed steps
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else if step.rawValue == currentStep.rawValue {
                            // Current step number
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            // Future step number
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }

                    // Step label
                    Text(stepTitles[index])
                        .font(.system(size: 11, weight: step.rawValue == currentStep.rawValue ? .semibold : .regular))
                        .foregroundColor(step.rawValue <= currentStep.rawValue ? .primary : .secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)

                // Connecting line (except after last step)
                if index < OnboardingState.Step.allCases.count - 1 {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 32) // Align with circles
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    @Bindable var onboardingState: OnboardingState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            Image(systemName: "mic.circle.fill")
                .resizable()
                .frame(width: 90, height: 90)
                .foregroundColor(.accentColor)

            // Title
            Text("Welcome to Look Ma No Hands")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)

            // Description
            VStack(spacing: 15) {
                Text("Fast, local voice dictation for macOS")
                    .font(.title3)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "bolt.fill", text: "Lightning-fast voice dictation")
                    FeatureRow(icon: "lock.fill", text: "100% local - your voice never leaves your Mac")
                    FeatureRow(icon: "waveform", text: "AI-powered meeting transcription")
                }
                .padding(.top, 10)
            }

            Spacer()
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Ollama Step

struct OllamaStepView: View {
    @Bindable var onboardingState: OnboardingState
    let ollamaService: OllamaService

    @State private var ollamaInstalled: Bool = false
    @State private var isChecking: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: "brain.head.profile")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)
                .foregroundColor(.purple)

            // Title
            Text("Install Ollama (Optional)")
                .font(.system(size: 26, weight: .bold))

            // Description
            Text("Ollama enables AI-powered meeting notes from transcripts.\nVoice dictation works without it.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.body)
                .padding(.horizontal, 50)

            // Status
            if isChecking {
                ProgressView("Checking for Ollama...")
                    .padding(.top, 10)
            } else if ollamaInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Ollama is installed and running")
                        .font(.headline)
                }
                .padding(.top, 10)
            } else {
                VStack(spacing: 18) {
                    // Instructions
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Installation steps:")
                            .font(.headline)

                        InstructionRow(number: 1, text: "Open Terminal")
                        InstructionRow(number: 2, text: "Run: brew install ollama")
                        InstructionRow(number: 3, text: "Run: ollama serve")
                    }
                    .frame(maxWidth: 450)

                    HStack(spacing: 12) {
                        // Copy commands button
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install ollama && ollama serve", forType: .string)
                        }) {
                            Label("Copy Commands", systemImage: "doc.on.doc")
                        }

                        // Check again button
                        Button(action: {
                            checkOllama()
                        }) {
                            Label("Check Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 10)
            }

            Spacer()
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
        .onAppear {
            checkOllama()
        }
    }

    private func checkOllama() {
        isChecking = true
        Task {
            let available = await ollamaService.isAvailable()
            await MainActor.run {
                ollamaInstalled = available
                isChecking = false
            }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Whisper Model Step

struct WhisperModelStepView: View {
    @Bindable var onboardingState: OnboardingState
    let whisperService: WhisperService

    @State private var modelExists: Bool = false
    @State private var isCheckingModel: Bool = true

    var body: some View {
        VStack(spacing: 25) {
            Spacer()

            // Icon
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)

            // Title
            Text("Download Whisper Model")
                .font(.system(size: 28, weight: .bold))

            // Description
            Text("Required for voice transcription.\nWe recommend the Tiny model for best speed.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Status or download UI
            if isCheckingModel {
                ProgressView("Checking for existing model...")
                    .padding()
            } else if modelExists || onboardingState.modelDownloaded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Current model: \(onboardingState.selectedModel.displayName)")
                        .font(.headline)
                }
                .padding()
            } else {
                VStack(spacing: 20) {
                    // Model picker
                    Picker("Select Model", selection: $onboardingState.selectedModel) {
                        Text("Tiny (75MB) - Recommended").tag(WhisperModel.tiny)
                        Text("Base (142MB)").tag(WhisperModel.base)
                        Text("Small (466MB)").tag(WhisperModel.small)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 450)

                    // Download button or progress
                    if onboardingState.isDownloadingModel {
                        VStack(spacing: 12) {
                            ProgressView(value: onboardingState.downloadProgress, total: 1.0)
                                .frame(maxWidth: 350)

                            Text("\(Int(onboardingState.downloadProgress * 100))% complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            downloadModel()
                        }) {
                            Label("Download Model", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: 350)
                    }
                }
            }

            Spacer()
        }
        .padding(40)
        .onAppear {
            checkExistingModel()
        }
    }

    private func checkExistingModel() {
        isCheckingModel = true
        Task {
            // FIRST: Get the currently configured model from Settings
            let configuredModel = Settings.shared.whisperModel

            // Check if the configured model exists on disk
            let configuredModelExists = WhisperService.modelExists(named: configuredModel.rawValue)

            // Also check other models for fallback
            let tinyExists = WhisperService.modelExists(named: "tiny")
            let baseExists = WhisperService.modelExists(named: "base")
            let smallExists = WhisperService.modelExists(named: "small")

            let anyModelExists = tinyExists || baseExists || smallExists

            await MainActor.run {
                modelExists = anyModelExists
                onboardingState.modelDownloaded = anyModelExists
                isCheckingModel = false

                // PRIORITY 1: Use configured model if it exists on disk
                if configuredModelExists {
                    onboardingState.selectedModel = configuredModel
                } else if anyModelExists {
                    // PRIORITY 2: Fallback to first available model
                    if tinyExists {
                        onboardingState.selectedModel = .tiny
                    } else if baseExists {
                        onboardingState.selectedModel = .base
                    } else if smallExists {
                        onboardingState.selectedModel = .small
                    }
                }
                // PRIORITY 3: No models exist, keep default .tiny for download
            }
        }
    }

    private func downloadModel() {
        onboardingState.isDownloadingModel = true
        onboardingState.downloadProgress = 0.0

        Task {
            do {
                try await WhisperService.downloadModel(
                    named: onboardingState.selectedModel.rawValue,
                    progress: { progress in
                        Task { @MainActor in
                            onboardingState.downloadProgress = progress
                        }
                    }
                )

                await MainActor.run {
                    onboardingState.isDownloadingModel = false
                    onboardingState.modelDownloaded = true
                    Settings.shared.whisperModel = onboardingState.selectedModel
                }
            } catch {
                await MainActor.run {
                    onboardingState.isDownloadingModel = false
                    // Show error (simplified for now)
                    print("Download error: \(error)")
                }
            }
        }
    }
}

// MARK: - Permissions Step

struct PermissionsStepView: View {
    @Bindable var onboardingState: OnboardingState

    @State private var permissionCheckTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: "lock.shield.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)
                .foregroundColor(.orange)

            // Title
            Text("Grant Permissions")
                .font(.system(size: 26, weight: .bold))

            // Description
            Text("Look Ma No Hands needs permissions to work properly")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.body)

            // Permission cards
            VStack(spacing: 16) {
                // Microphone permission
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Capture your voice for dictation",
                    isGranted: onboardingState.hasMicrophonePermission,
                    actionTitle: "Grant Permission",
                    action: {
                        requestMicrophonePermission()
                    }
                )

                // Accessibility permission
                PermissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Monitor Caps Lock and insert text into apps",
                    isGranted: onboardingState.hasAccessibilityPermission,
                    actionTitle: "Open System Settings",
                    action: {
                        openAccessibilitySettings()
                    },
                    extraInfo: onboardingState.hasAccessibilityPermission ? nil : "You'll need to manually enable accessibility in System Settings"
                )
            }
            .frame(maxWidth: 550)
            .padding(.top, 10)

            Spacer()
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
        .onAppear {
            startPermissionChecking()
        }
        .onDisappear {
            stopPermissionChecking()
        }
    }

    private func requestMicrophonePermission() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                onboardingState.hasMicrophonePermission = granted
            }
        }
    }

    private func openAccessibilitySettings() {
        // First, trigger the system prompt to add this app to Accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Also open System Settings to the Accessibility pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func startPermissionChecking() {
        // Initial check
        checkPermissions()

        // Check every second
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkPermissions()
        }
    }

    private func stopPermissionChecking() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func checkPermissions() {
        Task {
            // Check microphone
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let micGranted = (micStatus == .authorized)

            // Check accessibility
            let accessibilityGranted = AXIsProcessTrusted()

            await MainActor.run {
                onboardingState.hasMicrophonePermission = micGranted
                onboardingState.hasAccessibilityPermission = accessibilityGranted
            }
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void
    var extraInfo: String? = nil

    var body: some View {
        HStack(spacing: 15) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 50)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let extraInfo = extraInfo {
                    Text(extraInfo)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Status/Action
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Completion Step

struct CompletionStepView: View {
    @Bindable var onboardingState: OnboardingState

    var needsRestart: Bool {
        onboardingState.hasAccessibilityPermission
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: needsRestart ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                .resizable()
                .frame(width: 70, height: 70)
                .foregroundColor(needsRestart ? .orange : .green)

            // Title
            Text(needsRestart ? "Setup Complete - Restart Required" : "You're All Set!")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)

            // Summary
            VStack(alignment: .leading, spacing: 10) {
                Text("Configuration Summary:")
                    .font(.headline)
                    .padding(.bottom, 5)

                SummaryRow(
                    icon: "waveform",
                    text: "Whisper model: \(onboardingState.selectedModel.rawValue)",
                    status: .success
                )

                SummaryRow(
                    icon: "brain",
                    text: "Ollama: \(onboardingState.ollamaSkipped ? "Skipped" : "Installed")",
                    status: onboardingState.ollamaSkipped ? .warning : .success
                )

                SummaryRow(
                    icon: "mic",
                    text: "Microphone: \(onboardingState.hasMicrophonePermission ? "Granted" : "Not granted")",
                    status: onboardingState.hasMicrophonePermission ? .success : .warning
                )

                SummaryRow(
                    icon: "accessibility",
                    text: "Accessibility: \(onboardingState.hasAccessibilityPermission ? "Granted" : "Not granted")",
                    status: onboardingState.hasAccessibilityPermission ? .success : .warning
                )
            }
            .frame(maxWidth: 500)
            .padding(.top, 5)

            if needsRestart {
                Text("The app will restart to apply accessibility permissions")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 50)
                    .padding(.top, 8)
            }

            if !onboardingState.hasMicrophonePermission || !onboardingState.hasAccessibilityPermission {
                Text("⚠️ Some permissions were not granted.\nYou can configure them later in Settings.")
                    .font(.callout)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 50)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
    }
}

struct SummaryRow: View {
    enum Status {
        case success
        case warning
    }

    let icon: String
    let text: String
    let status: Status

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(status == .success ? .green : .orange)
                .frame(width: 20)

            Image(systemName: icon)
                .frame(width: 20)

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Navigation View

struct OnboardingNavigationView: View {
    @Bindable var state: OnboardingState
    let onComplete: () -> Void

    private var buttonLabel: String {
        if state.currentStep == .complete {
            return state.hasAccessibilityPermission ? "Restart" : "Finish"
        } else {
            return "Continue"
        }
    }

    var body: some View {
        HStack {
            // Back button
            Button(action: {
                state.previousStep()
            }) {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(state.currentStep == .welcome)

            Spacer()

            // Continue/Finish/Restart button
            Button(action: {
                if state.currentStep == .complete {
                    onComplete()
                } else {
                    state.nextStep()
                }
            }) {
                Text(buttonLabel)
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.canContinue())
        }
    }
}
