import SwiftUI
import AppKit
import Combine

/// Waveform visualization using animated frequency bars
struct WaveformBarsView: View {
    @Binding var frequencyBands: [Float]
    @Environment(\.colorScheme) var colorScheme
    var fixedWidth: CGFloat? = nil  // Optional fixed width for floating indicator

    var body: some View {
        Canvas { context, size in
            let barCount = frequencyBands.count
            let barSpacing: CGFloat = 2  // Closer together
            let totalSpacing = CGFloat(barCount - 1) * barSpacing
            let barWidth = (size.width - totalSpacing) / CGFloat(barCount)

            for (index, level) in frequencyBands.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                // IMPROVED: Balanced scaling to show dynamic range without constant peaking
                // Audio is already amplified 50x in AudioRecorder, so values are often near 1.0
                // Use power of 2.5 to compress high values more than low values
                // This creates more perceptual dynamic range
                let normalizedLevel = pow(CGFloat(level), 2.5)
                let barHeight = max(normalizedLevel * size.height, 3.0) // Minimum 3pt
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                // Less rounded corners - barWidth / 4 instead of barWidth / 2
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 4)

                // IMPROVED: Automatic light/dark mode color adaptation
                let color: Color
                if colorScheme == .dark {
                    // Dark mode: blue to purple gradient (original)
                    color = Color(
                        red: 0.3 + Double(level) * 0.5,
                        green: 0.6 - Double(level) * 0.3,
                        blue: 1.0
                    )
                } else {
                    // Light mode: deeper blue with better contrast
                    color = Color(
                        red: 0.1 + Double(level) * 0.3,
                        green: 0.4 - Double(level) * 0.2,
                        blue: 0.9 - Double(level) * 0.2
                    )
                }

                context.fill(path, with: .color(color.opacity(colorScheme == .dark ? 0.8 : 0.9)))
            }
        }
        .frame(width: fixedWidth, height: 38)
    }
}

/// Floating window that appears during recording to show the user that audio is being captured
/// Shows animated waveform visualization at the cursor position (Apple-style)
/// IMPORTANT: Only shown in dictation mode, NOT in meeting transcription mode
struct RecordingIndicator: View {

    @ObservedObject var state: RecordingIndicatorState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // Just the waveform visualization
        WaveformBarsView(frequencyBands: $state.frequencyBands, fixedWidth: 300)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 5, x: 0, y: 2)
        )
        .overlay(
            // IMPROVED: Border color adapts to light/dark mode
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color(red: 0.3, green: 0.6, blue: 1.0)  // Light blue for dark mode
                        : Color(red: 0.1, green: 0.4, blue: 0.8), // Deeper blue for light mode
                    lineWidth: 2
                )
                .opacity(0.8)
        )
    }
}

/// Preview-compatible version without binding
struct RecordingIndicatorPreview: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
                .scaleEffect(isPulsing ? 1.2 : 1.0)

            Text("Listening...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Window Controller

/// Observable state for the recording indicator
class RecordingIndicatorState: ObservableObject {
    @Published var frequencyBands: [Float] = Array(repeating: 0.0, count: 40)

    // Exponential smoothing for fluid animation
    func updateFrequencyBands(_ newBands: [Float]) {
        guard frequencyBands.count == newBands.count else {
            frequencyBands = newBands
            return
        }

        // Smooth transition: 70% old + 30% new
        // IMPORTANT: Create new array instead of modifying in place
        // so @Published detects the change
        var smoothedBands: [Float] = []
        for i in 0..<newBands.count {
            let smoothed = frequencyBands[i] * 0.7 + newBands[i] * 0.3
            smoothedBands.append(smoothed)
        }

        // Assign new array to trigger @Published
        frequencyBands = smoothedBands
    }
}

/// Controls the floating indicator window - persistent window approach
class RecordingIndicatorWindowController {

    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingIndicator>?
    private let windowWidth: CGFloat = 340  // Adjusted for waveform-only layout
    private let windowHeight: CGFloat = 60
    private var positionUpdateTimer: Timer?
    private var audioUpdateTimer: DispatchSourceTimer?
    private weak var audioRecorder: AudioRecorder?
    private let state = RecordingIndicatorState()

    init() {
        // Create window once during initialization
        setupWindow()
    }

    /// Set audio recorder reference for waveform visualization
    func setAudioRecorder(_ recorder: AudioRecorder) {
        self.audioRecorder = recorder
    }

    private func setupWindow() {
        // Pass the state object directly so it can be observed
        let contentView = NSHostingView(rootView: RecordingIndicator(state: state))
        self.hostingView = contentView

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = contentView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hasShadow = false
        window.ignoresMouseEvents = true

        // Start hidden
        window.alphaValue = 0
        window.orderOut(nil)

        self.window = window
    }

    /// Start polling audio levels for waveform visualization
    private func startAudioLevelUpdates() {
        print("🎬 Starting audio level updates (30 FPS)")

        // Use DispatchSourceTimer instead of RunLoop timer
        // This runs on dispatch queue and isn't affected by menu tracking
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))  // ~30 FPS

        timer.setEventHandler { [weak self] in
            guard let self = self, let recorder = self.audioRecorder else {
                return
            }

            let bands = recorder.getFrequencyBands(bandCount: 40)  // More bars for thinner look
            self.state.updateFrequencyBands(bands)
        }

        timer.resume()
        audioUpdateTimer = timer

        print("✅ Audio update timer started with DispatchSource (30 FPS, 40 bands)")
    }

    /// Stop audio updates and reset to idle state
    private func stopAudioLevelUpdates() {
        audioUpdateTimer?.cancel()
        audioUpdateTimer = nil

        // Reset to idle state with explicit assignment
        DispatchQueue.main.async {
            self.state.frequencyBands = Array(repeating: 0.0, count: 40)
            print("🛑 Audio updates stopped, bands reset to zero")
        }
    }

    /// Update window position for cursor-based positioning
    func updatePosition(for cursorRect: NSRect) {
        guard let window = window else { return }

        // Position indicator below cursor with small offset
        var origin = NSPoint(
            x: cursorRect.midX - (windowWidth / 2),  // Center horizontally on cursor
            y: cursorRect.minY - windowHeight - 8     // 8pt below cursor
        )

        // Handle screen edge cases
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame

            // Too close to bottom edge? Show above cursor instead
            if origin.y < screenFrame.minY + 20 {
                origin.y = cursorRect.maxY + 8  // 8pt above cursor
            }

            // Too close to left edge?
            if origin.x < screenFrame.minX + 10 {
                origin.x = screenFrame.minX + 10
            }

            // Too close to right edge?
            if origin.x + windowWidth > screenFrame.maxX - 10 {
                origin.x = screenFrame.maxX - windowWidth - 10
            }
        }

        window.setFrameOrigin(origin)
    }

    /// Update window position using fixed positioning
    private func updatePositionFixed() {
        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - (windowWidth / 2) // Center horizontally
        let y: CGFloat

        // Get position preference from settings
        let position = Settings.shared.indicatorPosition

        switch position {
        case .top:
            y = screenFrame.maxY - 60  // Near top with some padding
        case .bottom:
            y = screenFrame.minY + 60  // Near bottom with some padding
        case .followCursor:
            // Should not reach here, but fallback to top if it does
            y = screenFrame.maxY - 60
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Show the recording indicator
    func show() {
        guard let window = window else { return }

        // Get user's position preference
        let position = Settings.shared.indicatorPosition

        // Position based on user preference
        switch position {
        case .followCursor:
            // Use cursor-based positioning with fallback
            if let cursorRect = CursorPositionService.shared.getCursorScreenPosition() {
                updatePosition(for: cursorRect)
                print("RecordingIndicator: Using cursor-based positioning")

                // Start periodic position updates to follow cursor
                startPositionUpdates()
            } else {
                // Fallback to top if cursor detection fails
                updatePositionFixed()
                print("RecordingIndicator: Cursor detection failed, falling back to fixed position")
            }

        case .top, .bottom:
            // Use fixed positioning at top or bottom
            updatePositionFixed()
            print("RecordingIndicator: Using fixed positioning at \(position.rawValue)")
            // Don't start position updates for fixed positions
        }

        // Start audio level updates
        startAudioLevelUpdates()

        // Make window visible first
        window.orderFront(nil)

        // Animate fade-in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    /// Start periodic position updates
    private func startPositionUpdates() {
        // Update position every 100ms to smoothly follow mouse cursor
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Always use mouse cursor position for smooth tracking
            let mouseLocation = NSEvent.mouseLocation
            let cursorRect = NSRect(
                x: mouseLocation.x,
                y: mouseLocation.y,
                width: 2,
                height: 20
            )

            self.updatePosition(for: cursorRect)
        }
    }

    /// Stop periodic position updates
    private func stopPositionUpdates() {
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
    }

    /// Hide the recording indicator
    func hide() {
        guard let window = window else { return }

        // Stop position updates
        stopPositionUpdates()

        // Stop audio updates
        stopAudioLevelUpdates()

        // Animate fade-out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}

