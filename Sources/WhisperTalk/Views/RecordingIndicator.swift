import SwiftUI
import AppKit

/// Floating window that appears during recording to show the user that audio is being captured
/// Uses native macOS design patterns for a polished, system-integrated look
struct RecordingIndicator: View {

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            // Pulsing red recording dot with smooth animation
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [.red, Color.red.opacity(0.8)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 6
                    )
                )
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.7 : 1.0)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("Recording")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    init() {
        // Create window once during initialization
        setupWindow()
    }

    private func setupWindow() {
        // Create hosting view
        let contentView = NSHostingView(rootView: RecordingIndicator())

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 130, height: 36),
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

        // Position near top-center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 65 // Half of window width
            let y = screenFrame.maxY - 52  // From top
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Start hidden
        window.alphaValue = 0
        window.orderOut(nil)

        self.window = window
    }

    /// Show the recording indicator
    func show() {
        guard let window = window else { return }

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

