import SwiftUI

/// Launch splash screen that briefly appears when app launches
/// Shows app icon, name, and hotkey hint to confirm successful launch
struct LaunchSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            // App Icon - using hands-up emoji to match app icon
            Text("🙌")
                .font(.system(size: 56))
                .accessibilityLabel("Look Ma No Hands app icon")

            // App Name
            Text("Look Ma No Hands")
                .font(.title2)
                .fontWeight(.semibold)

            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text("Ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("App ready")

            Divider()
                .padding(.horizontal, 20)

            // Hotkey Hint - reflects actual settings
            VStack(spacing: 4) {
                Text("Press \(Settings.shared.effectiveHotkey.displayString) to record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Press \(Settings.shared.effectiveHotkey.displayString) to start recording")
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
        .accessibilityLabel("Launch confirmation")
        .accessibilityHint("Click or press any key to dismiss")
    }
}

// MARK: - Preview

struct LaunchSplashView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchSplashView()
            .frame(width: 400, height: 300)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
