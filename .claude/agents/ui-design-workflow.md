# UI Design Workflow — HTML → Figma → SwiftUI

## Overview

The `preview/` directory contains browser-renderable HTML pages representing every app screen. **HTML is the design source of truth.** Review and iterate here before writing any SwiftUI code.

## Serving the catalog

```bash
bash scripts/run.sh          # starts http://localhost:8420 and opens browser
```

Or open individual files directly in Safari/Chrome — they work without a server.

## Screen inventory

| Screen | File | SwiftUI source | Dimensions |
|---|---|---|---|
| Launch Splash | `screens/launch-splash.html` | `LaunchSplashView.swift` | 280×220 |
| Recording Indicator | `screens/recording-indicator.html` | `RecordingIndicator.swift` | 340×60 floating |
| Menu Bar | `screens/menu-bar.html` | `AppDelegate.swift` (NSMenu) | 200px wide |
| Onboarding | `screens/onboarding.html` | `OnboardingView.swift` | 600×520 |
| Settings | `screens/settings.html` | `SettingsView.swift` | 750×450 |
| Meeting Record | `screens/meeting-record.html` | `MeetingRecordTab.swift` | 700×500 |
| Meeting Analyze | `screens/meeting-analyze.html` | `MeetingAnalyzeTab.swift` | 700×500 |
| Meeting Library | `screens/meeting-library.html` | `MeetingLibraryTab.swift` | 700×500 |

## Design files

| File | Purpose |
|---|---|
| `preview/design-tokens.css` | All colors, spacing, radii, shadows — single source of truth |
| `preview/components.css` | Reusable component styles (pills, cards, buttons, rows) |

## HTML → Figma round-trip

1. Open `preview/index.html` in Chrome
2. Use Figma DevMode to inspect the rendered page at `http://localhost:8420/screens/<screen>.html`
3. Figma renders the HTML as a design frame
4. Iterate on the HTML (colors, spacing, layout) — changes immediately visible in browser
5. When design is approved, update SwiftUI to match

## HTML → SwiftUI mapping conventions

Each HTML file includes `data-swiftui-file` attributes to trace sections back to Swift source:

```html
<div data-swiftui-file="LaunchSplashView.swift">...</div>
<div data-swiftui-file="SettingsView.swift#generalTab">...</div>
```

### Color mapping

| CSS token | SwiftUI equivalent |
|---|---|
| `--color-bg` | `Color(nsColor: .windowBackgroundColor)` |
| `--color-surface` | `Color(nsColor: .controlBackgroundColor)` |
| `--color-material` | `.ultraThinMaterial` |
| `--color-separator` | `.separator` |
| `--color-text-primary` | `.primary` |
| `--color-text-secondary` | `.secondary` |
| `--color-accent` | `.accentColor` |
| `--color-recording-red` | `Color(red: 1.0, green: 0.23, blue: 0.19)` |
| `--color-orange` | `Color.orange` (systemOrange) |

### Spacing mapping

| CSS token | SwiftUI equivalent |
|---|---|
| `--space-1` (4px) | 4 |
| `--space-2` (8px) | 8 |
| `--space-3` (12px) | 12 |
| `--space-4` (16px) | 16 |
| `--space-6` (24px) | 24 |

### Radius mapping

| CSS token | SwiftUI equivalent |
|---|---|
| `--radius-lg` (8px) | `cornerRadius: 8` |
| `--radius-xl` (12px) | `cornerRadius: 12` |

## Adding a new screen

1. Create `preview/screens/<screen-name>.html`
2. Link `../design-tokens.css` and `../components.css`
3. Add a window container with the exact `width` and `height` matching the SwiftUI `.frame()`
4. Add `data-swiftui-file="NewView.swift"` attributes
5. Add an entry to `preview/index.html` catalog grid
6. Add an entry to this table above

## State toggling

Screens with multiple states use minimal JavaScript to switch visible sections:

```html
<div class="state-controls">
  <button class="state-btn active" onclick="showState('idle', this)">Idle</button>
  <button class="state-btn" onclick="showState('active', this)">Active</button>
</div>
<div class="state-content active" id="state-idle">...</div>
<div class="state-content" id="state-active">...</div>

<script>
function showState(id, btn) {
  document.querySelectorAll('.state-content').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.state-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('state-' + id).classList.add('active');
  btn.classList.add('active');
}
</script>
```

## Design principles

- **Dark mode default** — mirrors the app's default (macOS dark)
- **Exact window dimensions** — not responsive; matches SwiftUI `.frame()` constraints
- **No frameworks** — vanilla HTML/CSS + minimal JS only
- **SF Symbols approximated** with Unicode or emoji where SVG isn't practical
- **Each file is standalone** — can be opened directly without the server
