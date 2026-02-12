import SwiftUI
import AppKit

/// Main entry point for Look Ma No Hands
/// This app runs as a menu bar application (no dock icon)
@main
struct LookMaNoHandsApp: App {
    // Use AppDelegate for menu bar setup (requires AppKit bridging)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Settings window - opened from menu bar
        SwiftUI.Settings {
            SettingsView(whisperService: appDelegate.whisperServiceForSettings)
        }
    }
}
