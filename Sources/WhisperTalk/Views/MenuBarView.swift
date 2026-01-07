import SwiftUI

/// View displayed in the menu bar popover (if we switch from menu to popover)
/// Currently not used - menu bar uses NSMenu directly in AppDelegate
struct MenuBarView: View {
    @ObservedObject private var settings = Settings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Ready")
                    .font(.headline)
            }
            
            Divider()
            
            // Quick actions
            Button("Start Recording") {
                // TODO: Trigger recording
            }
            .keyboardShortcut("r", modifiers: [])
            
            Divider()
            
            // Settings shortcut
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 200)
    }
}
