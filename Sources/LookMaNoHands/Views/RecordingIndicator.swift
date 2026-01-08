import SwiftUI
import AppKit

/// Floating window that appears during recording to show the user that audio is being captured
/// Uses native macOS design patterns for a polished, system-integrated look
struct RecordingIndicator: View {

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing red recording dot with smooth animation
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [.red, Color.red.opacity(0.8)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.7 : 1.0)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("Recording")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            isPulsing = true
        }
        .onDisappear {
            isPulsing = false
        }
    }
}

// MARK: - Window Controller

/// Controls the floating indicator window - persistent window approach
class RecordingIndicatorWindowController {

    private var window: NSWindow?
    private let windowWidth: CGFloat = 160
    private let windowHeight: CGFloat = 46

    init() {
        // Create window once during initialization
        setupWindow()
    }

    private func setupWindow() {
        // Create hosting view
        let contentView = NSHostingView(rootView: RecordingIndicator())

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

        // Position will be set when showing based on user preference
        updatePosition()

        // Start hidden
        window.alphaValue = 0
        window.orderOut(nil)

        self.window = window
    }

    /// Update window position based on user preference
    private func updatePosition() {
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

        // Update position in case settings changed
        updatePosition()

        // Make window visible first
        window.orderFront(nil)

        // Animate fade-in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    /// Hide the recording indicator
    func hide() {
        guard let window = window else { return }

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

