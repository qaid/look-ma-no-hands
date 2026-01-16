import AppKit
import SwiftUI
import AVFoundation

/// AppDelegate handles menu bar setup and application lifecycle
/// This is where we configure the app to run as a menu bar app without a dock icon
class AppDelegate: NSObject, NSApplicationDelegate {

    // Menu bar status item
    private var statusItem: NSStatusItem?
    private var recordingMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var meetingWindow: NSWindow?
    private var onboardingWindow: NSWindow?

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
        NSLog("🚀 AppDelegate: applicationDidFinishLaunching called")

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
        NSLog("✅ AppDelegate: Set activation policy")

        // Register URL event handler for URL scheme support
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        NSLog("✅ AppDelegate: URL scheme handler registered")

        // Set up the menu bar
        setupMenuBar()
        NSLog("✅ AppDelegate: Menu bar setup complete")

        // Check if first launch
        if !Settings.shared.hasCompletedOnboarding {
            NSLog("🆕 First launch detected - showing onboarding")
            showOnboarding()
            return  // Skip rest of initialization until onboarding completes
        }

        // Normal initialization for returning users
        completeInitialization()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let onboardingView = OnboardingView(
            whisperService: whisperService,
            ollamaService: ollamaService,
            onComplete: {
                // Called when user clicks "Finish"
                self.onboardingWindow?.close()
                self.onboardingWindow = nil

                // Check if accessibility was granted during onboarding
                if AXIsProcessTrusted() {
                    // Restart app to activate accessibility monitoring
                    NSLog("🔄 Accessibility granted - restarting app")
                    self.restartApp()
                } else {
                    // Continue with normal initialization
                    self.completeInitialization()
                }
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Look Ma No Hands"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        self.onboardingWindow = window
    }

    private func completeInitialization() {
        checkPermissions()
        NSLog("✅ AppDelegate: Permissions checked")

        loadWhisperModel()
        NSLog("✅ AppDelegate: Whisper model load initiated")

        setupKeyboardMonitoring()
        NSLog("✅ AppDelegate: Keyboard monitoring setup complete")

        NSLog("🎉 Look Ma No Hands initialization complete")
    }

    // MARK: - URL Scheme Handling

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("❌ Invalid URL event received")
            return
        }

        NSLog("🔗 Received URL: \(url)")

        // Handle lookmanohands:// URLs
        if url.scheme == "lookmanohands" {
            switch url.host {
            case "toggle":
                NSLog("📞 URL command: toggle recording")
                handleTriggerKey()
            case "start":
                NSLog("📞 URL command: start recording")
                if !transcriptionState.isRecording && transcriptionState.recordingState == .idle {
                    startRecording()
                }
            case "stop":
                NSLog("📞 URL command: stop recording")
                if transcriptionState.isRecording {
                    stopRecordingAndTranscribe()
                }
            default:
                NSLog("⚠️ Unknown URL command: \(url.host ?? "none")")
            }
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        // Create the status item (menu bar icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use system microphone icon
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Look Ma No Hands")
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
        let recordingItem = NSMenuItem(
            title: "Start Recording (Caps Lock)",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        self.recordingMenuItem = recordingItem
        menu.addItem(recordingItem)

        menu.addItem(NSMenuItem.separator())

        // Meeting transcription
        menu.addItem(NSMenuItem(
            title: "Start Meeting Transcription...",
            action: #selector(openMeetingTranscription),
            keyEquivalent: "m"
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
            title: "Quit Look Ma No Hands",
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
        NSLog("📋 Opening Settings window...")

        // If window already exists, just bring it to front
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create settings window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Look Ma No Hands Settings"
        window.center()
        window.isReleasedWhenClosed = false

        // Create SwiftUI settings view and wrap it in NSHostingView
        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView

        self.settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSLog("✅ Settings window created and displayed")
    }

    @objc private func openMeetingTranscription() {
        NSLog("🎙️ Opening Meeting Transcription window...")

        // Check if macOS 13+ is available (required for ScreenCaptureKit)
        guard #available(macOS 13.0, *) else {
            showAlert(
                title: "macOS 13+ Required",
                message: "Meeting transcription requires macOS 13 or later for system audio capture."
            )
            return
        }

        // If window already exists, just bring it to front
        if let window = meetingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create meeting window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Meeting Transcription"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)
        window.delegate = self

        // Create SwiftUI meeting view and wrap it in NSHostingView
        let meetingView = MeetingView(whisperService: whisperService)
        let hostingView = NSHostingView(rootView: meetingView)
        window.contentView = hostingView

        self.meetingWindow = window

        // Change activation policy to regular app so window appears in Cmd+Tab
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSLog("✅ Meeting Transcription window created and displayed")
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
                        message: "Look Ma No Hands needs microphone access to record audio. Please grant permission in System Settings > Privacy & Security > Microphone."
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
        alert.informativeText = "Look Ma No Hands needs Accessibility permission to insert text into other applications.\n\nClick 'Open System Preferences' and add Look Ma No Hands to the allowed apps."
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
            alert.informativeText = "Look Ma No Hands needs a Whisper model to transcribe audio. Would you like to download one now?\n\nRecommended: 'tiny' model (75 MB) - fastest transcription for dictation."
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
        let success = keyboardMonitor.startMonitoring { [weak self] in
            self?.handleTriggerKey()
        }

        if success {
            NSLog("✅ Keyboard monitoring started successfully")
        } else {
            NSLog("❌ Keyboard monitoring failed to start - accessibility permission may not be granted")
            // Try again after a delay in case permissions were just granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                NSLog("🔄 Retrying keyboard monitoring setup...")
                if self?.keyboardMonitor.startMonitoring(onTrigger: { [weak self] in
                    self?.handleTriggerKey()
                }) == true {
                    NSLog("✅ Keyboard monitoring started on retry")
                }
            }
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
            handleMissingAccessibilityPermission()
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

    /// Handle missing accessibility permission with smart detection
    private func handleMissingAccessibilityPermission() {
        // Double-check if permission is actually granted in System Preferences
        // but the app hasn't been restarted yet
        let systemPrefsGranted = AXIsProcessTrusted()

        if systemPrefsGranted {
            // Permission is granted in System Preferences but app needs restart
            showRestartRequiredAlert()
        } else {
            // Permission not granted - prompt user to grant it
            showAccessibilityPermissionAlert()
        }
    }

    /// Show alert when accessibility permission is granted but restart is needed
    private func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "App Restart Required"
        alert.informativeText = "Accessibility permission has been granted, but Look Ma No Hands needs to be restarted (not your computer) for the changes to take effect.\n\nWould you like to restart the app now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart App Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            restartApp()
        }
    }

    /// Show alert to prompt for accessibility permission
    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Look Ma No Hands needs accessibility permission to:\n\n• Monitor the Caps Lock key\n• Insert transcribed text into other apps\n\nClick 'Open System Settings' to grant permission, then restart the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openAccessibilityPreferences()
        }
    }

    /// Restart the application
    private func restartApp() {
        // Get the path to the application bundle
        let bundlePath = Bundle.main.bundlePath

        // Use NSWorkspace to relaunch the app
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

    /// Open System Preferences to Accessibility settings
    private func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Look Ma No Hands")
        }

        // Update menu item text
        updateRecordingMenuItem(isRecording: isRecording)
    }

    /// Update the recording menu item text based on recording state
    private func updateRecordingMenuItem(isRecording: Bool) {
        if isRecording {
            recordingMenuItem?.title = "Stop Recording (Caps Lock)"
        } else {
            recordingMenuItem?.title = "Start Recording (Caps Lock)"
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // If the meeting window is closing, revert to accessory mode
        if window === meetingWindow {
            NSApp.setActivationPolicy(.accessory)
            print("Meeting window closed - reverted to accessory mode")
        }
    }
}
