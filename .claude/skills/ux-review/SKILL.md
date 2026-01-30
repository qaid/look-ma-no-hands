# UX Review

Perform a professional-grade UI/UX audit of Look Ma No Hands.

This skill evaluates the app against Apple Human Interface Guidelines, macOS menu bar app conventions, and Nielsen's usability heuristics to ensure a polished, native experience.

## Instructions

Conduct a thorough UI/UX review covering all categories below. Read the relevant SwiftUI view files and evaluate against each criterion.

For each finding, provide:
- **Rating**: Excellent / Good / Needs Work / Poor
- **Location**: File path and line number (if applicable)
- **Issue**: What could be improved
- **Recommendation**: Specific fix with code example if helpful

---

### 1. Apple Human Interface Guidelines Compliance

#### Menu Bar Presence
- [ ] App uses `LSUIElement = true` (no Dock icon for menu bar utility)
- [ ] Menu bar icon is a template image (adapts to light/dark menu bar)
- [ ] Icon is recognizable and distinct at 16x16 / 18x18 points
- [ ] Menu bar icon reflects app state (recording vs idle)
- [ ] Click behavior matches user expectations (popover or menu)

#### Floating Recording Indicator
- [ ] Window level is appropriate (`.floating` or `.statusBar`)
- [ ] Indicator is non-intrusive but clearly visible
- [ ] Position is sensible (near cursor, corner, or follows focus)
- [ ] Uses system-appropriate styling (vibrancy, blur, rounded corners)
- [ ] Animates smoothly for state changes
- [ ] Can be dismissed or repositioned if blocking content

#### Settings Window
- [ ] Uses standard macOS window chrome (title bar, close button)
- [ ] Follows tab-based layout for multiple settings categories
- [ ] Respects system appearance (light/dark mode)
- [ ] Window remembers position and size
- [ ] Uses native controls (toggles, pickers, buttons)

---

### 2. Nielsen's 10 Usability Heuristics

#### H1: Visibility of System Status
- [ ] Recording state is immediately obvious (visual + optional audio cue)
- [ ] Transcription progress is visible (processing indicator)
- [ ] Permission status is clearly communicated
- [ ] Model download progress shows percentage/status

#### H2: Match Between System and Real World
- [ ] Uses familiar terminology ("Recording", "Dictation", not jargon)
- [ ] Icons are universally recognizable (microphone, settings gear)
- [ ] Actions match mental models (Caps Lock = push-to-talk feel)

#### H3: User Control and Freedom
- [ ] Recording can be cancelled mid-stream
- [ ] User can easily stop/restart without consequences
- [ ] Settings changes are reversible
- [ ] No destructive actions without confirmation

#### H4: Consistency and Standards
- [ ] Follows macOS conventions (⌘, for preferences, ⌘Q to quit)
- [ ] Visual style matches system apps
- [ ] Terminology is consistent throughout
- [ ] Similar actions look and behave similarly

#### H5: Error Prevention
- [ ] Prevents recording when permissions not granted
- [ ] Validates settings before applying
- [ ] Guides user through permission setup flow

#### H6: Recognition Rather Than Recall
- [ ] Current state visible without memorization
- [ ] Settings show current values, not just labels
- [ ] Keyboard shortcut is displayed in menu

#### H7: Flexibility and Efficiency of Use
- [ ] Power users can trigger via keyboard only
- [ ] No unnecessary clicks for common actions
- [ ] Quick access from menu bar

#### H8: Aesthetic and Minimalist Design
- [ ] Only essential information displayed
- [ ] No visual clutter or unnecessary decorations
- [ ] Clean typography and spacing
- [ ] Appropriate use of whitespace

#### H9: Help Users Recognize and Recover from Errors
- [ ] Permission denial shows clear next steps
- [ ] Transcription failures explain what went wrong
- [ ] Error messages are human-readable, not technical

#### H10: Help and Documentation
- [ ] First-run experience guides setup
- [ ] Tooltips for non-obvious controls
- [ ] About/Help accessible from menu

---

### 3. macOS Menu Bar App Best Practices

- [ ] Hybrid approach: SwiftUI for views, AppKit for system integration
- [ ] `.menuBarExtraStyle(.window)` if using popover content
- [ ] Window uses `.collectionBehavior = .moveToActiveSpace`
- [ ] Popover/window dismisses when clicking outside
- [ ] No jarring delays when opening menu bar popover
- [ ] App feels like a "system utility", not a "floating app"

---

### 4. Visual Design Quality

#### Typography
- [ ] Uses SF Pro or system font
- [ ] Appropriate font weights (not all bold or all light)
- [ ] Text sizes follow Apple's type scale
- [ ] Sufficient contrast for readability

#### Color
- [ ] Uses semantic colors (`Color.primary`, `.secondary`, `.accentColor`)
- [ ] Works in both light and dark mode
- [ ] Accent color is appropriate (system blue or custom brand)
- [ ] No harsh or clashing colors

#### Spacing & Layout
- [ ] Consistent spacing (8pt grid system)
- [ ] Proper padding and margins
- [ ] Elements are aligned
- [ ] Touch targets are adequate size (44pt minimum for clickable)

#### Animation & Feedback
- [ ] State changes animate smoothly
- [ ] No jarring transitions
- [ ] Haptic or visual feedback for actions
- [ ] Loading states are indicated

---

### 5. Accessibility

- [ ] VoiceOver labels on all interactive elements
- [ ] Sufficient color contrast (4.5:1 minimum)
- [ ] Supports Dynamic Type / text scaling
- [ ] Keyboard navigation works
- [ ] Reduced Motion respected (`@Environment(\.accessibilityReduceMotion)`)
- [ ] No information conveyed by color alone

---

### 6. SwiftUI Code Quality (UX Impact)

- [ ] Views are appropriately decomposed (not monolithic)
- [ ] State management is clean (no UI glitches from state bugs)
- [ ] Previews exist for rapid design iteration
- [ ] No force unwraps that could crash and break UX
- [ ] Proper use of `@ViewBuilder` for conditional content

---

## Output Format

After analysis, provide:

1. **Overall UX Score**: X/10 with brief justification
2. **Strengths**: What the app does well
3. **Priority Improvements**: Top 3-5 issues to fix first
4. **Detailed Findings**: Full audit organized by category
5. **Quick Wins**: Easy fixes with high impact
6. **Polish Items**: Nice-to-haves for a premium feel

## References

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [The Menu Bar - Apple HIG](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [Designing macOS Menu Bar Extras - Bjango](https://bjango.com/articles/designingmenubarextras/)
- [Nielsen's 10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)
- [SwiftUI Best Practices 2025](https://howik.com/swiftui-best-practices-2025)
