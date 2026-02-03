import AppKit
import SwiftUI

/// Controls the launch splash window display and auto-dismissal
class LaunchSplashWindowController {
    private var window: NSWindow?
    private var dismissTimer: Timer?
    private var eventMonitor: Any?

    private let windowWidth: CGFloat = 280
    private let windowHeight: CGFloat = 220
    private let displayDuration: TimeInterval = 2.0

    /// Show the launch splash screen
    func show() {
        guard window == nil else {
            NSLog("⚠️ LaunchSplash: Window already exists, skipping show()")
            return
        }

        NSLog("🎬 LaunchSplash: Creating and showing launch splash")

        // Create SwiftUI content view
        let contentView = NSHostingView(rootView: LaunchSplashView())

        // Create borderless window
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
        window.isMovable = false

        // Position in upper third of screen
        positionWindow(window)

        self.window = window

        // Set up click and key handlers for immediate dismissal
        setupDismissHandlers()

        // Set up auto-dismiss timer
        setupAutoDismissTimer()

        // Show with fade-in animation
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        // Check if reduced motion is enabled
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if reduceMotion {
            // No animation - instant display
            window.alphaValue = 1.0
            NSLog("✅ LaunchSplash: Shown (no animation, reduced motion)")
        } else {
            // Smooth fade-in animation
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }
            NSLog("✅ LaunchSplash: Shown with fade-in animation")
        }
    }

    /// Position window in upper third of screen, centered horizontally
    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            NSLog("⚠️ LaunchSplash: No main screen found")
            return
        }

        let screenFrame = screen.visibleFrame

        // Center horizontally
        let x = screenFrame.midX - (windowWidth / 2)

        // Position in upper third (2/3 from bottom = 1/3 from top)
        let y = screenFrame.minY + (screenFrame.height * 2.0 / 3.0) - (windowHeight / 2)

        window.setFrameOrigin(NSPoint(x: x, y: y))

        NSLog("📍 LaunchSplash: Positioned at upper third of screen (x: \(Int(x)), y: \(Int(y)))")
    }

    /// Set up handlers for immediate dismissal on click or keypress
    private func setupDismissHandlers() {
        // Monitor for mouse clicks and key presses
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            NSLog("🖱️ LaunchSplash: User interaction detected - dismissing immediately")
            self?.dismiss(animated: true)
            return event
        }
    }

    /// Set up auto-dismiss timer
    private func setupAutoDismissTimer() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            NSLog("⏰ LaunchSplash: Auto-dismiss timer fired")
            self?.dismiss(animated: true)
        }
    }

    /// Dismiss the splash screen
    private func dismiss(animated: Bool) {
        guard let window = window else {
            return
        }

        // Clean up timer and event monitor
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Check if reduced motion is enabled
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if animated && !reduceMotion {
            // Fade-out animation
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0.0
            }, completionHandler: {
                window.orderOut(nil)
                self.window = nil
                NSLog("✅ LaunchSplash: Dismissed with fade-out animation")
            })
        } else {
            // No animation - instant dismissal
            window.alphaValue = 0.0
            window.orderOut(nil)
            self.window = nil
            NSLog("✅ LaunchSplash: Dismissed (no animation)")
        }
    }

    /// Public method to manually dismiss (called if needed)
    func hide() {
        dismiss(animated: true)
    }
}
