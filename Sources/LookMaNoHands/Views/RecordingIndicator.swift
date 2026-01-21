import SwiftUI
import AppKit
import Combine

/// Floating window that appears during recording to show the user that audio is being captured
/// Shows live transcription text at the cursor position (Apple-style)
struct RecordingIndicator: View {

    @State private var isPulsing = false
    @State private var borderRotation: Double = 0
    @State private var borderOpacity: Double = 1.0
    @Binding var transcriptionText: String

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing microphone icon
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            // Live transcription (last 50 chars)
            if !transcriptionText.isEmpty {
                Text(String(transcriptionText.suffix(50)))
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .foregroundColor(.primary)
            } else {
                Text("Listening...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .overlay(
            // Thin Siri-style animated multi-color border
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.3, green: 0.6, blue: 1.0),   // Blue
                            Color(red: 0.8, green: 0.3, blue: 1.0),   // Purple
                            Color(red: 1.0, green: 0.3, blue: 0.6),   // Pink
                            Color(red: 1.0, green: 0.5, blue: 0.3),   // Orange
                            Color(red: 0.3, green: 1.0, blue: 0.6),   // Green
                            Color(red: 0.3, green: 0.6, blue: 1.0)    // Blue (loop)
                        ]),
                        center: .center,
                        angle: .degrees(borderRotation)
                    ),
                    lineWidth: 2  // Thinner border
                )
                .opacity(borderOpacity)
        )
        .onAppear {
            isPulsing = true

            // Start continuous rotation animation for the border
            withAnimation(
                .linear(duration: 3.0)
                .repeatForever(autoreverses: false)
            ) {
                borderRotation = 360
            }

            // Pulsing opacity for the border
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                borderOpacity = 0.6
            }
        }
        .onDisappear {
            isPulsing = false
        }
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
    @Published var transcriptionText: String = ""
}

/// Controls the floating indicator window - persistent window approach
class RecordingIndicatorWindowController {

    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingIndicator>?
    private let windowWidth: CGFloat = 300  // Wider for transcription text
    private let windowHeight: CGFloat = 32
    private var positionUpdateTimer: Timer?
    private let state = RecordingIndicatorState()

    init() {
        // Create window once during initialization
        setupWindow()
    }

    private func setupWindow() {
        // Create a binding manually
        let binding = Binding<String>(
            get: { self.state.transcriptionText },
            set: { self.state.transcriptionText = $0 }
        )

        // Create hosting view with binding to transcription text
        let contentView = NSHostingView(rootView: RecordingIndicator(transcriptionText: binding))
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

    /// Update transcription text displayed in the indicator
    func updateTranscription(_ text: String) {
        DispatchQueue.main.async {
            self.state.transcriptionText = text
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

    /// Update window position using fixed positioning (fallback)
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
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Show the recording indicator
    func show() {
        guard let window = window else { return }

        // Try cursor positioning first, fallback to fixed positioning
        if let cursorRect = CursorPositionService.shared.getCursorScreenPosition() {
            updatePosition(for: cursorRect)
            print("RecordingIndicator: Using cursor-based positioning")

            // Start periodic position updates (in case cursor moves)
            startPositionUpdates()
        } else {
            updatePositionFixed()
            print("RecordingIndicator: Using fixed positioning (cursor detection failed)")
        }

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
        // Update position every 200ms while recording
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let cursorRect = CursorPositionService.shared.getCursorScreenPosition() {
                self.updatePosition(for: cursorRect)
            }
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

        // Clear transcription text
        state.transcriptionText = ""

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

