import SwiftUI

/// Splash screen that briefly appears when hotkey toggle state changes
/// Shows app icon, enabled/disabled status, and visual feedback
struct HotkeyToggleSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 12) {
            // App Icon - using hands-up emoji to match app icon
            Text("🙌🏾")
                .font(.system(size: 56))
                .opacity(isEnabled ? 1.0 : 0.4)
                .accessibilityLabel("Look Ma No Hands app icon")

            // Status Title
            Text(isEnabled ? "Hotkey Enabled" : "Hotkey Disabled")
                .font(.title2)
                .fontWeight(.semibold)

            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isEnabled ? .green : .red)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(isEnabled ? "Active" : "Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hotkey \(isEnabled ? "active" : "paused")")

            Divider()
                .padding(.horizontal, 20)

            // Descriptive Text
            VStack(spacing: 4) {
                if isEnabled {
                    Text("Press \(Settings.shared.effectiveHotkey.displayString) to record")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Dictation hotkey is paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Use Cmd+Shift+D to re-enable")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isEnabled ? "Press \(Settings.shared.effectiveHotkey.displayString) to start recording" : "Dictation hotkey is paused. Use Command Shift D to re-enable")
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(width: 280, height: 220)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15),
                    radius: 10,
                    x: 0,
                    y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.1)
                        : Color.black.opacity(0.05),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hotkey toggle notification")
        .accessibilityHint("Click or press any key to dismiss")
    }
}

// MARK: - Preview

struct HotkeyToggleSplashView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            HotkeyToggleSplashView(isEnabled: true)
            HotkeyToggleSplashView(isEnabled: false)
        }
        .frame(width: 400, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
