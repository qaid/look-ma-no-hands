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

/// Waveform visualization using a smooth bezier curve line
struct WaveformLineView: View {
    @Binding var frequencyBands: [Float]
    @Environment(\.colorScheme) var colorScheme
    var width: CGFloat? = nil
    var height: CGFloat = 34

    var body: some View {
        Canvas { context, size in
            let count = frequencyBands.count
            guard count > 1 else { return }

            // Build sample points from frequency data
            var points: [CGPoint] = []
            let midY = size.height / 2
            for i in 0..<count {
                let x = (CGFloat(i) / CGFloat(count - 1)) * size.width
                let level = CGFloat(frequencyBands[i])
                // Compress with power curve, same as bars view
                let normalized = pow(level, 2.0)
                let amplitude = normalized * (size.height * 0.45)
                // Alternate above/below center for waveform shape
                let sign: CGFloat = i % 2 == 0 ? -1 : 1
                let y = midY + sign * amplitude
                points.append(CGPoint(x: x, y: y))
            }

            // Build smooth bezier path through points
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for i in 1..<points.count {
                let prev = points[i - 1]
                let cur = points[i]
                let cpx = (prev.x + cur.x) / 2
                path.addCurve(
                    to: cur,
                    control1: CGPoint(x: cpx, y: prev.y),
                    control2: CGPoint(x: cpx, y: cur.y)
                )
            }

            // Build fill path (close at bottom)
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()

            // Gradient colors that adapt to color scheme
            let gradient: Gradient
            let fillGradient: Gradient

            if colorScheme == .dark {
                // Dark mode: original vibrant colors
                gradient = Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.25, blue: 0.2).opacity(0.6), location: 0),
                    .init(color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.8), location: 0.35),
                    .init(color: Color(red: 0.4, green: 0.25, blue: 0.85).opacity(0.7), location: 1.0),
                ])

                fillGradient = Gradient(stops: [
                    .init(color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.15), location: 0),
                    .init(color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.0), location: 1.0),
                ])
            } else {
                // Light mode: deeper, more saturated colors for better visibility
                gradient = Gradient(stops: [
                    .init(color: Color(red: 0.9, green: 0.15, blue: 0.1).opacity(0.8), location: 0),
                    .init(color: Color(red: 0.1, green: 0.3, blue: 0.8).opacity(0.9), location: 0.35),
                    .init(color: Color(red: 0.3, green: 0.15, blue: 0.7).opacity(0.85), location: 1.0),
                ])

                fillGradient = Gradient(stops: [
                    .init(color: Color(red: 0.1, green: 0.3, blue: 0.8).opacity(0.2), location: 0),
                    .init(color: Color(red: 0.1, green: 0.3, blue: 0.8).opacity(0.0), location: 1.0),
                ])
            }

            // Draw fill
            context.fill(
                fillPath,
                with: .linearGradient(fillGradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))
            )

            // Draw stroke
            context.stroke(
                path,
                with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)),
                lineWidth: 2.5
            )
        }
        .frame(width: width, height: height)
    }
}

/// Floating window that appears during recording to show the user that audio is being captured
/// Shows a recording dot + smooth waveform line at the cursor position
/// IMPORTANT: Only shown in dictation mode, NOT in meeting transcription mode
struct RecordingIndicator: View {

    @ObservedObject var state: RecordingIndicatorState
    @ObservedObject private var settings = Settings.shared
    @Environment(\.colorScheme) var colorScheme

    /// Compute the effective color scheme based on user's theme preference
    private var effectiveColorScheme: ColorScheme? {
        switch settings.appearanceTheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil  // Use system default
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Static recording dot (no pulsing)
            Circle()
                .fill(Color(red: 1.0, green: 0.23, blue: 0.19))
                .frame(width: 10, height: 10)
                .shadow(color: Color(red: 1.0, green: 0.23, blue: 0.19).opacity(0.4), radius: 4, x: 0, y: 0)

            // Smooth waveform line
            WaveformLineView(frequencyBands: $state.frequencyBands, width: 260, height: 34)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.15), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.5)
                        : Color(red: 0.1, green: 0.4, blue: 0.8).opacity(0.4),
                    lineWidth: 1.5
                )
        )
        .preferredColorScheme(effectiveColorScheme)
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

        // Asymmetric smoothing: fast attack (show new peaks quickly) but fast
        // decay too (don't hold high values once audio quiets).
        // IMPORTANT: Create new array instead of modifying in place
        // so @Published detects the change
        var smoothedBands: [Float] = []
        for i in 0..<newBands.count {
            let old = frequencyBands[i]
            let new = newBands[i]
            // Attack: blend 60% old + 40% new; Decay: blend 35% old + 65% new
            let smoothed = new >= old
                ? old * 0.6 + new * 0.4   // rising — moderate follow
                : old * 0.35 + new * 0.65  // falling — drop back down quickly
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

