import AppKit
import SwiftUI
import AVFoundation

/// AppDelegate handles menu bar setup and application lifecycle
/// This is where we configure the app to run as a menu bar app without a dock icon
class AppDelegate: NSObject, NSApplicationDelegate {

    // Menu bar status item
    private var statusItem: NSStatusItem?

    // Popover for menu bar content (alternative to dropdown menu)
    private var popover: NSPopover?

    // Reference to the transcription state (shared across the app)
    private let transcriptionState = TranscriptionState()

    // Services
    private let keyboardMonitor = KeyboardMonitor()
    private let audioRecorder = AudioRecorder()
    private let whisperService = WhisperService()
    private let textFormatter = TextFormatter.with(preset: .standard)
    private let ollamaService = OllamaService() // Optional - for advanced formatting
    private let textInsertionService = TextInsertionService()

    // UI
    private let recordingIndicator = RecordingIndicatorWindowController()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Set up the menu bar
        setupMenuBar()

        // Check permissions on launch
        checkPermissions()

        // Load Whisper model
        loadWhisperModel()

        // Optional: Check if Ollama is available (for advanced AI formatting)
        // checkOllamaStatus()

        // Start keyboard monitoring
        setupKeyboardMonitoring()

        print("WhisperTalk launched successfully")
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        // Create the status item (menu bar icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use system microphone icon
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "WhisperTalk")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create the menu
        let menu = NSMenu()
        
        // Status section
        let statusItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recording control
        menu.addItem(NSMenuItem(
            title: "Start Recording (Caps Lock)",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Permissions section
        let permissionsItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permissionsSubmenu = NSMenu()
        permissionsSubmenu.addItem(NSMenuItem(
            title: "Microphone: Checking...",
            action: nil,
            keyEquivalent: ""
        ))
        permissionsSubmenu.addItem(NSMenuItem(
            title: "Accessibility: Checking...",
            action: nil,
            keyEquivalent: ""
        ))
        permissionsItem.submenu = permissionsSubmenu
        menu.addItem(permissionsItem)
        
        // Ollama status
        menu.addItem(NSMenuItem(
            title: "Ollama: Checking...",
            action: nil,
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit WhisperTalk",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        
        self.statusItem?.menu = menu
    }
    
    // MARK: - Actions
    
    @objc private func togglePopover() {
        // Currently using menu instead of popover
        // This method can be expanded to show a popover UI if desired
    }
    
    @objc private func toggleRecording() {
        handleTriggerKey()
    }
    
    @objc private func openSettings() {
        // Open the Settings window
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Permission Checks
    
    private func checkPermissions() {
        // Check microphone permission
        checkMicrophonePermission()
        
        // Check accessibility permission
        checkAccessibilityPermission()
    }
    
    private func checkMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.transcriptionState.hasMicrophonePermission = granted
                print("Microphone permission: \(granted ? "Granted" : "Denied")")

                // Update menu item
                if let menu = self?.statusItem?.menu {
                    if let permissionsItem = menu.items.first(where: { $0.title == "Permissions" }),
                       let submenu = permissionsItem.submenu {
                        for item in submenu.items {
                            if item.title.starts(with: "Microphone:") {
                                item.title = "Microphone: \(granted ? "✓ Granted" : "✗ Denied")"
                                break
                            }
                        }
                    }
                }

                if !granted {
                    self?.showAlert(
                        title: "Microphone Permission Required",
                        message: "WhisperTalk needs microphone access to record audio. Please grant permission in System Settings > Privacy & Security > Microphone."
                    )
                }
            }
        }
    }
    
    private func checkAccessibilityPermission() {
        // Check if we have accessibility permissions
        let trusted = AXIsProcessTrusted()
        transcriptionState.hasAccessibilityPermission = trusted
        print("Accessibility permission: \(trusted ? "Granted" : "Not granted")")

        // Update menu item
        if let menu = statusItem?.menu {
            if let permissionsItem = menu.items.first(where: { $0.title == "Permissions" }),
               let submenu = permissionsItem.submenu {
                for item in submenu.items {
                    if item.title.starts(with: "Accessibility:") {
                        item.title = "Accessibility: \(trusted ? "✓ Granted" : "✗ Not granted")"
                        break
                    }
                }
            }
        }

        if !trusted {
            // Prompt user to grant accessibility permission
            promptForAccessibilityPermission()
        }
    }
    
    private func promptForAccessibilityPermission() {
        // Open System Preferences to Accessibility pane
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "WhisperTalk needs Accessibility permission to insert text into other applications.\n\nClick 'Open System Preferences' and add WhisperTalk to the allowed apps."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Preferences > Privacy & Security > Accessibility
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ollama Check

    private func checkOllamaStatus() {
        Task {
            let available = await ollamaService.isAvailable()
            await MainActor.run {
                transcriptionState.isOllamaAvailable = available
                print("Ollama status: \(available ? "Available" : "Not available")")

                // Update menu item
                if let menu = statusItem?.menu {
                    for item in menu.items {
                        if item.title.starts(with: "Ollama:") {
                            item.title = "Ollama: \(available ? "✓ Running" : "✗ Not running")"
                            break
                        }
                    }
                }
            }
        }
    }

    // MARK: - Whisper Model Loading

    private func loadWhisperModel() {
        Task {
            // Prefer tiny model for speed (3-4x faster than base with good accuracy)
            let preferredModels = ["tiny", "base", "small"]
            var modelToLoad: String?

            for model in preferredModels {
                if WhisperService.modelExists(named: model) {
                    modelToLoad = model
                    break
                }
            }

            if let model = modelToLoad {
                // Load existing model
                do {
                    try await whisperService.loadModel(named: model)
                    print("Whisper model '\(model)' loaded successfully")
                } catch {
                    await MainActor.run {
                        showAlert(title: "Model Load Error", message: "Failed to load Whisper model: \(error.localizedDescription)")
                    }
                }
            } else {
                // No model found - prompt user to download
                await promptModelDownload()
            }
        }
    }

    /// Prompt user to download a Whisper model
    private func promptModelDownload() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Whisper Model Required"
            alert.informativeText = "WhisperTalk needs a Whisper model to transcribe audio. Would you like to download one now?\n\nRecommended: 'tiny' model (75 MB) - fastest transcription for dictation."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download Tiny Model (Recommended)")
            alert.addButton(withTitle: "Choose Model...")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Download tiny model
                Task {
                    await downloadModelWithProgress(modelName: "tiny")
                }
            } else if response == .alertSecondButtonReturn {
                // Show model selection
                showModelSelectionDialog()
            }
        }
    }

    /// Show model selection dialog
    private func showModelSelectionDialog() {
        let alert = NSAlert()
        alert.messageText = "Select Whisper Model"
        alert.informativeText = "Choose a model to download:\n\ntiny (75 MB) - Fastest (Recommended for dictation)\nbase (142 MB) - Good balance\nsmall (466 MB) - Better accuracy\nmedium (1.5 GB) - High accuracy\nlarge-v3 (3.1 GB) - Best quality"
        alert.alertStyle = .informational

        let models = WhisperService.getAvailableModels()
        for model in models {
            alert.addButton(withTitle: "\(model.name) - \(model.size)")
        }
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response.rawValue >= NSApplication.ModalResponse.alertFirstButtonReturn.rawValue,
           response.rawValue < NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + models.count {
            let selectedIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let selectedModel = models[selectedIndex].name

            Task {
                await downloadModelWithProgress(modelName: selectedModel)
            }
        }
    }

    /// Download model with progress indication
    private func downloadModelWithProgress(modelName: String) async {
        print("Starting download of \(modelName) model...")

        do {
            try await WhisperService.downloadModel(named: modelName) { progress in
                print("Download progress: \(Int(progress * 100))%")
            }

            // After download, try to load it
            try await whisperService.loadModel(named: modelName)

            await MainActor.run {
                showAlert(title: "Success", message: "Whisper model '\(modelName)' downloaded and loaded successfully!")
            }
        } catch {
            await MainActor.run {
                showAlert(title: "Download Failed", message: "Failed to download model: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Keyboard Monitoring Setup

    private func setupKeyboardMonitoring() {
        keyboardMonitor.startMonitoring { [weak self] in
            self?.handleTriggerKey()
        }
    }

    // MARK: - Recording Workflow

    /// Handle Caps Lock key press - toggles recording
    private func handleTriggerKey() {
        print("handleTriggerKey called, current state: \(transcriptionState.recordingState)")

        if transcriptionState.isRecording {
            print("Stopping recording...")
            stopRecordingAndTranscribe()
        } else if transcriptionState.recordingState == .idle {
            print("Starting recording...")
            startRecording()
        } else {
            print("Ignoring trigger - currently processing")
        }
    }

    /// Start recording audio
    private func startRecording() {
        // Check permissions first
        guard transcriptionState.hasAccessibilityPermission else {
            showAlert(title: "Permission Required", message: "Accessibility permission is required to insert text.")
            return
        }

        // Update state
        transcriptionState.startRecording()
        updateMenuBarIcon(isRecording: true)

        // Show recording indicator
        recordingIndicator.show()

        // Start audio recording
        do {
            try audioRecorder.startRecording()
            print("Recording started")
        } catch {
            transcriptionState.setError("Failed to start recording: \(error.localizedDescription)")
            updateMenuBarIcon(isRecording: false)

            // Hide indicator with slight delay to ensure proper cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.recordingIndicator.hide()
            }
        }
    }

    /// Stop recording and begin transcription pipeline
    private func stopRecordingAndTranscribe() {
        // Stop recording and get audio samples
        let audioSamples = audioRecorder.stopRecording()

        // Update UI immediately
        transcriptionState.stopRecording()
        updateMenuBarIcon(isRecording: false)
        recordingIndicator.hide()

        print("Recording stopped, processing \(audioSamples.count) samples")

        // Process the audio in background
        Task {
            await processRecording(samples: audioSamples)
        }
    }

    /// Process recorded audio: transcribe and format
    private func processRecording(samples: [Float]) async {
        // Wrap entire processing in autorelease pool to prevent memory buildup
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Transcribe with Whisper
                let rawText = try await self.whisperService.transcribe(samples: samples)
                await MainActor.run {
                    self.transcriptionState.setTranscription(rawText)
                }

                print("Transcription: \(rawText)")

                // Step 2: Format text using rule-based formatter (fast, no AI needed)
                let formattedText = self.textFormatter.format(rawText)
                await MainActor.run {
                    self.transcriptionState.setFormattedText(formattedText)
                }
                print("Formatted text: \(formattedText)")

                // Step 3: Insert text
                await MainActor.run {
                    autoreleasepool {
                        self.textInsertionService.insertText(formattedText)
                        self.transcriptionState.completeProcessing()
                    }
                }

                print("Text inserted successfully")

            } catch {
                await MainActor.run {
                    self.transcriptionState.setError("Processing failed: \(error.localizedDescription)")
                }
                print("Processing error: \(error)")
            }
        }.value
    }

    /// Show an alert dialog
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Menu Bar Icon Updates

    /// Update menu bar icon based on recording state
    func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }

        if isRecording {
            button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")
            // Could also change the color here using button.contentTintColor
        } else {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "WhisperTalk")
        }
    }
}
