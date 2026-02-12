import AppKit
import SwiftUI
import AVFoundation

/// AppDelegate handles menu bar setup and application lifecycle
/// This is where we configure the app to run as a menu bar app without a dock icon
class AppDelegate: NSObject, NSApplicationDelegate {

    // Menu bar status item
    private var statusItem: NSStatusItem?
    private var recordingMenuItem: NSMenuItem?
    private var hotkeyToggleMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var meetingWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    // Track if we just completed onboarding to avoid double-prompting
    private var justCompletedOnboarding = false

    // Track meeting recording state for close warning
    var isMeetingRecording = false

    // Pre-captured initial prompt (captured at recording start, before any insertion)
    private var capturedInitialPrompt: String?

    // Popover for menu bar content (alternative to dropdown menu)
    private var popover: NSPopover?

    // Reference to the transcription state (shared across the app)
    private let transcriptionState = TranscriptionState()

    // Services
    private let keyboardMonitor = KeyboardMonitor()
    private let hotkeyToggleMonitor = HotkeyToggleMonitor()
    private let audioRecorder = AudioRecorder()
    private let whisperService = WhisperService()
    private let textFormatter = TextFormatter.with(preset: .standard)
    private let ollamaService = OllamaService() // Optional - for advanced formatting
    private let textInsertionService = TextInsertionService()
    private let updateService = UpdateService()
    private let mediaControlService = MediaControlService()

    // UI
    private let recordingIndicator = RecordingIndicatorWindowController()
    private let launchSplash = LaunchSplashWindowController()
    private let hotkeyToggleSplash = HotkeyToggleSplashWindowController()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // FIRST: Install crash handlers before anything else
        CrashReporter.shared.install()

        // Start memory monitoring
        MemoryMonitor.shared.startMonitoring()
        MemoryMonitor.shared.onMemoryWarning = { memoryMB in
            Logger.shared.warning("Memory warning callback: \(memoryMB)MB", category: .memory)
        }
        MemoryMonitor.shared.onMemoryCritical = { memoryMB in
            Logger.shared.fault("Memory critical callback: \(memoryMB)MB - consider stopping recording", category: .memory)
        }

        // Check for previous crash and notify user
        if let lastCrash = CrashReporter.shared.getLastCrashReport() {
            Logger.shared.warning("Previous crash detected: \(lastCrash.url.lastPathComponent)", category: .crash)
            // Show crash report dialog after a short delay to allow UI to initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showCrashRecoveryDialog(crashReport: lastCrash)
            }
        }

        Logger.shared.info("AppDelegate: applicationDidFinishLaunching called", category: .app)

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
        Logger.shared.info("AppDelegate: Set activation policy to accessory", category: .app)

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

        // Check if first launch (but not if we just completed onboarding in this session)
        NSLog("🔍 Onboarding check: hasCompletedOnboarding=%@, justCompletedOnboarding=%@",
              Settings.shared.hasCompletedOnboarding ? "true" : "false",
              justCompletedOnboarding ? "true" : "false")

        if !Settings.shared.hasCompletedOnboarding && !justCompletedOnboarding {
            NSLog("🆕 First launch detected - showing onboarding")
            showOnboarding()
            return  // Skip rest of initialization until onboarding completes
        }

        // If we just completed onboarding, don't show it again
        if justCompletedOnboarding {
            NSLog("✅ Onboarding was just completed in this session - skipping")
        }

        // Normal initialization for returning users
        completeInitialization()

        // Request notification permission
        Task {
            _ = await NotificationService.shared.requestPermission()
        }

        // Show launch splash if enabled and not coming from onboarding
        if Settings.shared.showLaunchConfirmation {
            // Small delay to ensure app is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.launchSplash.show()
            }
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        NSLog("🎬 showOnboarding() - Creating onboarding window")

        // Switch to regular app mode so window appears in Dock and Cmd+Tab
        NSApp.setActivationPolicy(.regular)
        NSLog("   ✓ Set activation policy to .regular")

        let onboardingView = OnboardingView(
            whisperService: whisperService,
            ollamaService: ollamaService,
            onComplete: {
                NSLog("🎬 Onboarding onComplete callback triggered")

                // Called when user clicks "Finish"
                self.onboardingWindow?.close()
                self.onboardingWindow = nil

                // Mark that we just completed onboarding
                self.justCompletedOnboarding = true

                // Revert to accessory mode (menu bar only)
                NSApp.setActivationPolicy(.accessory)

                // Check if accessibility was granted during onboarding
                if AXIsProcessTrusted() {
                    // Restart app to activate accessibility monitoring
                    NSLog("🔄 Accessibility granted - restarting app")
                    self.restartApp()
                } else {
                    // Continue with normal initialization
                    // (won't show accessibility prompt since we just did onboarding)
                    self.completeInitialization()
                }
            },
            bringToFront: { [weak self] in
                // Bring onboarding window to front after system permission dialogs close
                self?.onboardingWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        )
        NSLog("   ✓ Created OnboardingView")

        let hostingController = NSHostingController(rootView: onboardingView)
        NSLog("   ✓ Created NSHostingController")

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Look Ma No Hands"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal  // Use normal level so system permission dialogs appear above
        NSLog("   ✓ Configured NSWindow")

        self.onboardingWindow = window

        // Bring window to front and activate app
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSLog("   ✓ Made window key and front")

        // Ensure window stays on top
        window.orderFrontRegardless()
        NSLog("✅ Onboarding window should now be visible")
    }

    private func completeInitialization() {
        checkPermissions()
        NSLog("✅ AppDelegate: Permissions checked")

        loadWhisperModel()
        NSLog("✅ AppDelegate: Whisper model load initiated")

        setupKeyboardMonitoring()
        NSLog("✅ AppDelegate: Keyboard monitoring setup complete")

        // Set up global toggle shortcut
        hotkeyToggleMonitor.startMonitoring { [weak self] in
            self?.toggleHotkeyEnabled()
        }

        // Listen for hotkey state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyEnabledStateDidChange),
            name: .hotkeyEnabledChanged,
            object: nil
        )

        // Check for updates if enabled (silent, non-blocking)
        if Settings.shared.checkForUpdatesOnLaunch {
            Task {
                await checkForUpdatesOnLaunch()
            }
        }

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
                startOrStopRecording()
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
            // Use emoji icon
            button.image = emojiImage(from: "🙌🏾")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create the menu
        let menu = NSMenu()

        // Status section
        let statusMenuItem = NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.tag = 999 // Tag for easy lookup
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())

        // Recording control
        let hotkeyName = Settings.shared.effectiveHotkey.displayString
        let recordingItem = NSMenuItem(
            title: "Start Recording (\(hotkeyName))",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        self.recordingMenuItem = recordingItem
        menu.addItem(recordingItem)

        menu.addItem(NSMenuItem.separator())

        // Hotkey toggle control
        let toggleItem = NSMenuItem(
            title: "Enable Dictation Hotkey",
            action: #selector(toggleHotkeyEnabled),
            keyEquivalent: ""
        )
        toggleItem.state = Settings.shared.hotkeyEnabled ? .on : .off
        self.hotkeyToggleMenuItem = toggleItem
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Meeting transcription
        menu.addItem(NSMenuItem(
            title: "Start Meeting Transcription...",
            action: #selector(openMeetingTranscription),
            keyEquivalent: "m"
        ))

        menu.addItem(NSMenuItem.separator())

        // Settings
        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))

        // Check for Updates
        menu.addItem(NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesManually),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        // Developer Reset
        menu.addItem(NSMenuItem(
            title: "Developer Reset",
            action: #selector(developerReset),
            keyEquivalent: ""
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
        startOrStopRecording()
    }

    @objc private func toggleHotkeyEnabled() {
        // Prevent disable during recording
        if transcriptionState.isRecording {
            let alert = NSAlert()
            alert.messageText = "Recording In Progress"
            alert.informativeText = "Cannot disable hotkey while recording. Stop recording first."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Toggle state - notification handler will update UI and show splash
        let newState = !Settings.shared.hotkeyEnabled
        Settings.shared.hotkeyEnabled = newState

        NSLog("🔀 Hotkey monitoring %@", newState ? "enabled" : "disabled")
    }

    @objc private func openSettings() {
        NSLog("📋 Opening Settings window...")

        // Switch to regular app mode so window appears in Dock and Cmd+Tab
        NSApp.setActivationPolicy(.regular)

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
        window.delegate = self

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

        // Create meeting window with improved dimensions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Look Ma No Hands - Meeting Transcription"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 450)
        window.maxSize = NSSize(width: 1400, height: 1200)
        window.setFrameAutosaveName("MeetingTranscriptionWindow")
        window.delegate = self

        // Create SwiftUI meeting view and wrap it in NSHostingView
        let meetingView = MeetingView(whisperService: whisperService, recordingIndicator: recordingIndicator, appDelegate: self)
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

        if !trusted && !justCompletedOnboarding {
            // Prompt user to grant accessibility permission
            // (but not if we just finished onboarding, which already prompted)
            promptForAccessibilityPermission()
        }

        // Reset the flag after checking
        justCompletedOnboarding = false
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

    // MARK: - Whisper Model Loading

    private func loadWhisperModel() {
        Task {
            // Update menu to show loading state
            await MainActor.run {
                updateMenuBarStatus("Loading model...")
            }

            // Try loading the model configured in Settings (respects user's choice from onboarding/settings)
            let configuredModel = Settings.shared.whisperModel.rawValue
            NSLog("🔍 loadWhisperModel: Attempting to load configured model: \(configuredModel)")
            NSLog("🔍 loadWhisperModel: hasCompletedOnboarding: \(Settings.shared.hasCompletedOnboarding)")

            do {
                // Try to load the configured model - WhisperKit will download it if needed
                try await whisperService.loadModel(named: configuredModel)
                NSLog("✅ Whisper model '\(configuredModel)' loaded successfully")

                // Update menu to show ready state
                await MainActor.run {
                    updateMenuBarStatus("Ready")
                }
            } catch {
                // Model load failed - try fallback models or prompt for download
                NSLog("⚠️ Failed to load configured model '\(configuredModel)': \(error.localizedDescription)")

                // Try fallback models
                let fallbackModels = ["tiny", "base", "small", "medium", "large-v3-turbo"]
                var loadedFallback = false

                for model in fallbackModels where model != configuredModel {
                    do {
                        NSLog("🔄 Trying fallback model: \(model)")
                        try await whisperService.loadModel(named: model)
                        NSLog("✅ Fallback model '\(model)' loaded successfully")
                        loadedFallback = true
                        break
                    } catch {
                        NSLog("⚠️ Fallback model '\(model)' also failed: \(error.localizedDescription)")
                    }
                }

                if !loadedFallback {
                    // No model could be loaded - prompt user to download
                    NSLog("❌ No model could be loaded - prompting user to download")
                    await MainActor.run {
                        updateMenuBarStatus("Model not found")
                    }
                    await promptModelDownload()
                } else {
                    // Fallback model loaded successfully
                    await MainActor.run {
                        updateMenuBarStatus("Ready")
                    }
                }
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

        await MainActor.run {
            updateMenuBarStatus("Downloading \(modelName)...")
        }

        do {
            try await WhisperService.downloadModel(named: modelName)

            await MainActor.run {
                updateMenuBarStatus("Loading \(modelName)...")
            }

            // After download, try to load it
            try await whisperService.loadModel(named: modelName)

            await MainActor.run {
                updateMenuBarStatus("Ready")
                showAlert(title: "Success", message: "Whisper model '\(modelName)' downloaded and loaded successfully!")
            }
        } catch {
            await MainActor.run {
                updateMenuBarStatus("Download failed")
                showAlert(title: "Download Failed", message: "Failed to download model: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Keyboard Monitoring Setup

    private func setupKeyboardMonitoring() {
        // Get the configured hotkey from settings
        let hotkey = Settings.shared.effectiveHotkey

        NSLog("🎯 Setting up keyboard monitoring...")
        NSLog("   Trigger key setting: %@", Settings.shared.triggerKey.rawValue)
        NSLog("   Custom hotkey: %@", Settings.shared.customHotkey?.displayString ?? "nil")
        NSLog("   Effective hotkey: %@ (isSingleModifier: %@)",
              hotkey.displayString,
              hotkey.isSingleModifierKey ? "YES" : "NO")

        let success = keyboardMonitor.startMonitoring(hotkey: hotkey) { [weak self] in
            self?.handleHotkeyTrigger()
        }

        // Set up ESC key cancellation callback
        keyboardMonitor.setCancellationCallback { [weak self] in
            self?.handleCancelKey()
        }

        if success {
            NSLog("✅ Keyboard monitoring started successfully")
        } else {
            NSLog("❌ Keyboard monitoring failed to start - accessibility permission may not be granted")
            // Try again after a delay in case permissions were just granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                NSLog("🔄 Retrying keyboard monitoring setup...")
                let retryHotkey = Settings.shared.effectiveHotkey
                if self?.keyboardMonitor.startMonitoring(hotkey: retryHotkey, onTrigger: { [weak self] in
                    self?.handleHotkeyTrigger()
                }) == true {
                    NSLog("✅ Keyboard monitoring started on retry for %@", retryHotkey.displayString)
                }
            }
        }

        // Listen for hotkey configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyConfigurationDidChange),
            name: .hotkeyConfigurationChanged,
            object: nil
        )
    }

    /// Handle hotkey configuration changes from Settings
    @objc private func hotkeyConfigurationDidChange() {
        let newHotkey = Settings.shared.effectiveHotkey

        NSLog("📢 Hotkey configuration change notification received")
        NSLog("   Trigger key setting: %@", Settings.shared.triggerKey.rawValue)
        NSLog("   Custom hotkey: %@", Settings.shared.customHotkey?.displayString ?? "nil")
        NSLog("   New effective hotkey: %@ (isSingleModifier: %@)",
              newHotkey.displayString,
              newHotkey.isSingleModifierKey ? "YES" : "NO")

        keyboardMonitor.setHotkey(newHotkey)

        // Update menu item text
        updateRecordingMenuItem(isRecording: transcriptionState.isRecording)
    }

    /// Handle hotkey enabled state changes
    @objc private func hotkeyEnabledStateDidChange() {
        let enabled = Settings.shared.hotkeyEnabled
        keyboardMonitor.setEnabled(enabled)
        hotkeyToggleMenuItem?.state = enabled ? .on : .off
        updateMenuBarIconForHotkeyState(enabled: enabled)

        // Show splash screen feedback for all toggle sources
        hotkeyToggleSplash.show(isEnabled: enabled)
    }

    // MARK: - Contextual Prompt Building

    /// Build an initial_prompt for Whisper based on the active app and field context
    /// Token budget: ~224 tokens (~890 chars) total
    ///   ~50 tokens: app-context prompt
    ///   ~50 tokens: existing field text
    ///   ~124 tokens: custom vocabulary terms
    private func buildInitialPrompt() -> String? {
        var parts: [String] = []

        // 1. App-context prompt (~200 chars / ~50 tokens)
        let appName = textInsertionService.getFocusedAppName()
        if let prompt = contextPrompt(forApp: appName) {
            parts.append(prompt)
        }

        // 2. Custom vocabulary terms (~500 chars / ~124 tokens)
        let vocabTerms = Settings.shared.customVocabulary
            .filter { $0.enabled }
            .map { $0.replacement }
        if !vocabTerms.isEmpty {
            parts.append("Technical terms: " + vocabTerms.joined(separator: ", "))
        }

        // 3. Existing field text for continuation context (~200 chars / ~50 tokens)
        // DISABLED: Including existing text causes Whisper to echo/duplicate it in output (Issue #100)
        // if let existingText = textInsertionService.getExistingFieldText(maxLength: 200) {
        //     parts.append(existingText)
        // }

        let prompt = parts.joined(separator: " ")
        // Trim to ~890 chars to stay within 224 token limit
        let trimmed = String(prompt.prefix(890))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Map frontmost app name to a contextual prompt style
    private func contextPrompt(forApp appName: String?) -> String? {
        guard let app = appName?.lowercased() else { return nil }

        // Email apps
        if ["mail", "outlook", "spark", "airmail"].contains(where: { app.contains($0) }) {
            return "Hi Sarah, I wanted to follow up on our Q4 discussion. Please find the attached report. Best regards, John."
        }

        // Chat/messaging apps
        if ["slack", "discord", "messages", "telegram", "whatsapp", "teams"].contains(where: { app.contains($0) }) {
            return "hey can you send me that link you mentioned earlier? thanks!"
        }

        // IDEs and code editors
        if ["xcode", "visual studio code", "sublime text", "nova", "bbedit", "textmate", "cursor"].contains(where: { app.contains($0) }) {
            return "Define function processPayment with parameters amount and currency. The API returns a JSON response."
        }

        // Document editors
        if ["pages", "word", "google docs", "notion", "craft"].contains(where: { app.contains($0) }) {
            return "The quarterly results indicate a significant improvement in operational efficiency across all departments."
        }

        // No specific context for other apps
        return nil
    }

    // MARK: - Recording Workflow

    /// Handle hotkey press (Caps Lock, etc.) - toggles recording
    /// This method respects the hotkeyEnabled setting
    private func handleHotkeyTrigger() {
        guard Settings.shared.hotkeyEnabled else {
            NSLog("⚠️ Hotkey disabled - ignoring trigger")
            return
        }

        startOrStopRecording()
    }

    /// Start or stop recording (used by menu bar, URL scheme, and hotkey)
    /// This method bypasses the hotkeyEnabled check - it's for manual user actions
    private func startOrStopRecording() {
        print("startOrStopRecording called, current state: \(transcriptionState.recordingState)")

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

    /// Handle ESC key press - cancels recording without transcribing
    private func handleCancelKey() {
        NSLog("⎋ ESC key pressed - canceling recording")

        guard transcriptionState.isRecording else {
            NSLog("⎋ Not recording - ignoring ESC key")
            return
        }

        // Stop the audio recorder without saving (discard samples)
        _ = audioRecorder.stopRecording()

        // Update state to idle (skips processing)
        transcriptionState.cancelRecording()

        // Update UI
        updateMenuBarIcon(isRecording: false)
        recordingIndicator.hide()

        // Resume system media if we paused it
        if Settings.shared.pauseMediaDuringDictation {
            MusicPlayerController.shared.resumePreviouslyPlayingPlayers()
            mediaControlService.resumeMedia()
        }

        NSLog("✅ Recording canceled - no text will be inserted")
    }

    /// Start recording audio
    private func startRecording() {
        // Check permissions first
        guard transcriptionState.hasAccessibilityPermission else {
            handleMissingAccessibilityPermission()
            return
        }

        // Check if Whisper model is ready
        if !whisperService.isModelLoaded {
            if whisperService.isModelLoading {
                showAlert(
                    title: "Model Loading",
                    message: "The Whisper model is still loading. Please wait a moment and try again."
                )
            } else {
                showAlert(
                    title: "Model Not Ready",
                    message: "The Whisper model is not loaded. Please check Settings to download a model."
                )
            }
            return
        }

        // Capture field context NOW, before any previous transcription could contaminate it
        capturedInitialPrompt = buildInitialPrompt()

        // Update state
        transcriptionState.startRecording()
        updateMenuBarIcon(isRecording: true)

        // Connect recorder to indicator for waveform
        recordingIndicator.setAudioRecorder(audioRecorder)

        // Show recording indicator
        recordingIndicator.show()

        // Start audio recording FIRST
        do {
            try audioRecorder.startRecording()
            print("Recording started")

            // CRITICAL: Pause media AFTER starting AVAudioEngine (not before)
            // This ensures we re-pause even if AVAudioEngine.start() triggers a system event that resumes media
            if Settings.shared.pauseMediaDuringDictation {
                // Small delay to let AVAudioEngine fully initialize (non-blocking)
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

                    // Use AppleScript to explicitly pause music players (Spotify, Apple Music)
                    MusicPlayerController.shared.pauseAllPlayers()

                    // Send explicit pause command (not toggle) for browsers and other media sources
                    // Uses MediaRemote framework's MRMediaRemoteSendCommand(kMRPause) which is safe:
                    // - If media is playing: pauses it
                    // - If nothing is playing: no-op (won't launch Music app) (#128)
                    self.mediaControlService.pauseMedia()
                }
            }
        } catch {
            // More detailed error message for audio session failures
            let errorMessage: String
            if (error as NSError).domain == NSOSStatusErrorDomain {
                errorMessage = "Failed to configure audio: \(error.localizedDescription)"
            } else {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }

            transcriptionState.setError(errorMessage)
            updateMenuBarIcon(isRecording: false)

            // Resume media if we paused it before the failed recording attempt
            if Settings.shared.pauseMediaDuringDictation {
                MusicPlayerController.shared.resumePreviouslyPlayingPlayers()
                mediaControlService.resumeMedia()
            }

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
        let pipelineStart = Date()
        Logger.shared.info("⏹️ Stop recording triggered", category: .transcription)

        // Use prompt captured at recording start (avoids feedback loop from just-inserted text)
        let initialPrompt = capturedInitialPrompt
        capturedInitialPrompt = nil

        // Stop recording and get audio samples
        let audioSamples = audioRecorder.stopRecording()

        // Update UI immediately
        transcriptionState.stopRecording()
        updateMenuBarIcon(isRecording: false)

        // Hide indicator immediately to avoid frozen waveform
        // (waveform stops animating when isRecording = false)
        recordingIndicator.hide()

        // Resume system media if we paused it
        if Settings.shared.pauseMediaDuringDictation {
            MusicPlayerController.shared.resumePreviouslyPlayingPlayers()
            mediaControlService.resumeMedia()
        }

        Logger.shared.info("📊 Pipeline started: \(audioSamples.count) samples (\(String(format: "%.1f", Double(audioSamples.count) / 16000.0))s audio)", category: .transcription)

        // Process the audio in background
        Task {
            await processRecording(samples: audioSamples, pipelineStart: pipelineStart, initialPrompt: initialPrompt)
        }
    }

    /// Process recorded audio: transcribe, format, and insert
    private func processRecording(samples: [Float], pipelineStart: Date, initialPrompt: String? = nil) async {
        let audioLength = Double(samples.count) / 16000.0
        Logger.shared.info("⏱️ Starting processing for \(String(format: "%.1f", audioLength))s of audio", category: .transcription)

        // Use high priority to minimize latency
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                // Step 1: Transcribe with Whisper (with contextual prompt)
                let transcribeStart = Date()
                Logger.shared.info("🔄 Starting Whisper transcription...", category: .transcription)

                let rawText = try await self.whisperService.transcribe(samples: samples, initialPrompt: initialPrompt)
                let transcribeTime = Date().timeIntervalSince(transcribeStart)

                Logger.shared.info("📝 Whisper complete: \"\(rawText)\" (took \(String(format: "%.3f", transcribeTime))s, ratio: \(String(format: "%.1f", transcribeTime / audioLength))x)", category: .transcription)

                // Step 2: Apply text formatting (rule-based + vocabulary replacement)
                let formatStart = Date()
                let formattedText = self.textFormatter.format(rawText)
                let formatTime = Date().timeIntervalSince(formatStart)

                if formattedText != rawText {
                    Logger.shared.info("✏️ Formatted: \"\(rawText)\" → \"\(formattedText)\" (\(String(format: "%.3f", formatTime))s)", category: .transcription)
                }

                let stateUpdateStart = Date()
                await MainActor.run {
                    self.transcriptionState.setTranscription(rawText)
                }
                let stateUpdateTime = Date().timeIntervalSince(stateUpdateStart)
                Logger.shared.info("💾 State updated in \(String(format: "%.3f", stateUpdateTime))s", category: .transcription)

                // Step 3: Insert formatted text
                let insertStart = Date()
                Logger.shared.info("⌨️ Starting text insertion...", category: .transcription)

                await MainActor.run {
                    autoreleasepool {
                        self.textInsertionService.insertText(formattedText)
                        self.transcriptionState.setFormattedText(formattedText)
                        self.transcriptionState.completeProcessing()
                    }
                }
                let insertTime = Date().timeIntervalSince(insertStart)
                Logger.shared.info("✅ Text inserted in \(String(format: "%.3f", insertTime))s", category: .transcription)

                let totalTime = Date().timeIntervalSince(pipelineStart)
                Logger.shared.info("🎉 TOTAL PIPELINE: \(String(format: "%.3f", totalTime))s (whisper: \(String(format: "%.3f", transcribeTime))s, format: \(String(format: "%.3f", formatTime))s, state: \(String(format: "%.3f", stateUpdateTime))s, insert: \(String(format: "%.3f", insertTime))s)", category: .transcription)

            } catch {
                let failTime = Date().timeIntervalSince(pipelineStart)
                Logger.shared.error("❌ Processing failed after \(String(format: "%.2f", failTime))s: \(error.localizedDescription)", category: .transcription)

                await MainActor.run {
                    self.transcriptionState.setError("Processing failed: \(error.localizedDescription)")
                }
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

    /// Show crash recovery dialog when a previous crash is detected
    private func showCrashRecoveryDialog(crashReport: (url: URL, content: String)) {
        let alert = NSAlert()
        alert.messageText = "Previous Crash Detected"
        alert.informativeText = "Look Ma No Hands crashed during the previous session. Would you like to view the crash report?\n\nThis information can help diagnose the issue."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "View Report")
        alert.addButton(withTitle: "Open Log Folder")
        alert.addButton(withTitle: "Dismiss")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // View report - open in TextEdit
            NSWorkspace.shared.open(crashReport.url)
        case .alertSecondButtonReturn:
            // Open log folder
            NSWorkspace.shared.open(CrashReporter.shared.crashDirectoryURL)
        default:
            break
        }

        // Archive the crash report so we don't show it again
        let archiveName = "viewed-\(crashReport.url.lastPathComponent)"
        let archiveURL = crashReport.url.deletingLastPathComponent().appendingPathComponent(archiveName)
        try? FileManager.default.moveItem(at: crashReport.url, to: archiveURL)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("App terminating normally", category: .app)
        MemoryMonitor.shared.stopMonitoring()
        Logger.shared.shutdown()
    }

    // MARK: - Menu Bar Icon Updates

    /// Create an NSImage from an emoji string
    private func emojiImage(from emoji: String, size: CGFloat = 18) -> NSImage? {
        let font = NSFont.systemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (emoji as NSString).size(withAttributes: attributes)

        let image = NSImage(size: NSSize(width: textSize.width + 4, height: textSize.height + 4))
        image.lockFocus()

        let rect = NSRect(x: 2, y: 2, width: textSize.width, height: textSize.height)
        (emoji as NSString).draw(in: rect, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Update menu bar icon based on recording state
    func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }

        // Use same emoji for both states
        // Recording indicator window already shows recording status
        button.image = emojiImage(from: "🙌🏾")

        // Update menu item text
        updateRecordingMenuItem(isRecording: isRecording)
    }

    /// Update the recording menu item text based on recording state
    private func updateRecordingMenuItem(isRecording: Bool) {
        let hotkeyName = Settings.shared.effectiveHotkey.displayString
        if isRecording {
            recordingMenuItem?.title = "Stop Recording (\(hotkeyName))"
        } else {
            recordingMenuItem?.title = "Start Recording (\(hotkeyName))"
        }
    }

    /// Update the status menu item to show current state
    private func updateMenuBarStatus(_ status: String) {
        guard let menu = statusItem?.menu else { return }
        // Find the status menu item by tag
        if let statusMenuItem = menu.item(withTag: 999) {
            statusMenuItem.title = "Status: \(status)"
        }
    }

    /// Update menu bar icon based on hotkey enabled state
    private func updateMenuBarIconForHotkeyState(enabled: Bool) {
        guard let button = statusItem?.button else { return }

        if enabled {
            button.image = emojiImage(from: "🙌🏾")
        } else {
            let baseImage = emojiImage(from: "🙌🏾", size: 18)
            button.image = createDisabledIcon(from: baseImage)
        }
    }

    /// Create a grayed-out icon with red badge for disabled state
    private func createDisabledIcon(from baseImage: NSImage?) -> NSImage? {
        guard let base = baseImage else { return nil }

        let size = base.size
        let image = NSImage(size: size)

        image.lockFocus()

        // Draw base with 30% opacity
        base.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: base.size),
            operation: .sourceOver,
            fraction: 0.3
        )

        // Add red badge dot
        let badgeSize: CGFloat = 6
        let badgeRect = NSRect(
            x: size.width - badgeSize - 1,
            y: size.height - badgeSize - 1,
            width: badgeSize,
            height: badgeSize
        )

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    // MARK: - Update Checking

    /// Check for updates on app launch (silent, doesn't block UI)
    private func checkForUpdatesOnLaunch() async {
        // Throttle: only check once per day
        if let lastCheck = Settings.shared.lastUpdateCheckDate,
           Date().timeIntervalSince(lastCheck) < 86400 {
            return
        }

        do {
            if let updateInfo = try await updateService.checkForUpdates() {
                Settings.shared.lastUpdateCheckDate = Date()
                await NotificationService.shared.sendNotification(
                    title: "Update Available",
                    body: "Look Ma No Hands \(updateInfo.version) is available. Click \"Check for Updates\" in the menu bar to download."
                )
            } else {
                Settings.shared.lastUpdateCheckDate = Date()
            }
        } catch {
            Logger.shared.info("Update check failed: \(error.localizedDescription)", category: .app)
        }
    }

    /// Manually check for updates (user-initiated from menu)
    @objc private func checkForUpdatesManually() {
        Task {
            do {
                if let updateInfo = try await updateService.checkForUpdates() {
                    await MainActor.run {
                        Settings.shared.lastUpdateCheckDate = Date()
                        showUpdateDialog(updateInfo: updateInfo)
                    }
                } else {
                    await MainActor.run {
                        Settings.shared.lastUpdateCheckDate = Date()
                        let alert = NSAlert()
                        alert.messageText = "You're Up to Date"
                        alert.informativeText = "Look Ma No Hands \(updateService.getCurrentVersion()) is the latest version."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Update Check Failed", message: "Could not check for updates: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Show dialog offering to download update
    private func showUpdateDialog(updateInfo: UpdateService.UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available"

        let notes = updateInfo.releaseNotes
        let truncatedNotes = notes.count > 500 ? String(notes.prefix(500)) + "..." : notes

        alert.informativeText = """
        Look Ma No Hands \(updateInfo.version) is available (you have \(updateService.getCurrentVersion())).

        Release Notes:
        \(truncatedNotes)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            downloadAndOpenUpdate(from: updateInfo.downloadURL)
        } else if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/qaid/look-ma-no-hands/releases/tag/v\(updateInfo.version)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Download update DMG and open it
    private func downloadAndOpenUpdate(from url: URL) {
        Task {
            do {
                let localURL = try await updateService.downloadUpdate(from: url)

                await MainActor.run {
                    NSWorkspace.shared.open(localURL)

                    let alert = NSAlert()
                    alert.messageText = "Update Downloaded"
                    alert.informativeText = "The update has been downloaded and opened. Drag the new app to your Applications folder to replace the current version, then restart."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Download Failed", message: "Could not download update: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Developer Tools

    /// Reset app permissions and settings (for development)
    @objc private func developerReset() {
        let alert = NSAlert()
        alert.messageText = "Developer Reset"
        alert.informativeText = "This will:\n• Reset onboarding status\n• Clear all app settings\n• Restart the app\n\nYou'll need to grant permissions again on next launch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset & Restart")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Clear UserDefaults for this app
            if let bundleID = Bundle.main.bundleIdentifier {
                NSLog("🔄 Developer Reset: Clearing UserDefaults for bundle: %@", bundleID)
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
            } else {
                NSLog("⚠️ Developer Reset: No bundle identifier found!")
            }

            // Note: Cannot programmatically revoke system permissions (microphone, accessibility, screen recording)
            // User must manually revoke these in System Settings if needed
            NSLog("✅ Developer reset complete - app will now restart")

            // Restart the app to show onboarding
            restartApp()
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Check if meeting window is trying to close while recording
        guard sender === meetingWindow else { return true }
        guard isMeetingRecording else { return true }

        let alert = NSAlert()
        alert.messageText = "Recording in Progress"
        alert.informativeText = "Are you sure you want to stop recording and close this window? Any unsaved transcription will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop & Close")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // User confirmed - allow close
            isMeetingRecording = false
            return true
        } else {
            // User cancelled - prevent close
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // If the meeting window is closing, revert to accessory mode
        if window === meetingWindow {
            NSApp.setActivationPolicy(.accessory)
            print("Meeting window closed - reverted to accessory mode")
        }

        // If the settings window is closing, revert to accessory mode
        if window === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
            print("Settings window closed - reverted to accessory mode")
        }

        // If the onboarding window is closing, revert to accessory mode
        if window === onboardingWindow {
            NSApp.setActivationPolicy(.accessory)
            print("Onboarding window closed - reverted to accessory mode")
        }
    }
}
