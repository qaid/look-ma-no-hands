import AppKit

/// Resolves the correct NSAppearance for the current theme setting.
/// Always returns a concrete value to avoid the stale-appearance race condition
/// that occurs when LSUIElement apps transition from .accessory to .regular
/// activation policy. Under hardened runtime (notarized builds),
/// NSApp.effectiveAppearance may not update before window display, causing
/// windows to render with the wrong appearance. Reading AppleInterfaceStyle
/// from UserDefaults is reliable regardless of activation policy state.
enum AppearanceResolver {
    static func resolved() -> NSAppearance? {
        switch Settings.shared.appearanceTheme {
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        case .system:
            let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
    }
}
