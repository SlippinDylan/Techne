# Scroll Policy And Standard Quit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify scroll indicator behavior behind a single macOS-aware policy layer and restore standard `Cmd+Q` quitting behavior, including when the menu bar menu is open.

**Architecture:** Add one focused scrolling module that translates product-facing surface roles into AppKit scroller configuration while still respecting the user's macOS scroll-bar preference. Apply that module to every app-owned `ScrollView` and `List`, then simplify app termination back to the system model by removing the custom `Cmd+Q` interceptor and locking the menu bar extra to explicit menu semantics.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, `xcodebuild`

---

## File Structure

**Create**
- `Apps/Views/Shared/Scrolling/AppScrollerPolicy.swift`
  Maps high-level surface roles to concrete AppKit scroller configuration.
- `Apps/Views/Shared/Scrolling/AppScrollChrome.swift`
  SwiftUI modifier plus AppKit bridge that finds the underlying `NSScrollView` and applies policy.
- `TechneTests/App/AppScrollerPolicyTests.swift`
  Unit tests for policy resolution and system-preference fallback behavior.

**Modify**
- `Apps/ContentView.swift`
  Apply standard scroll chrome to the sidebar `List` and settings `ScrollView`.
- `Apps/Views/ProjectListView.swift`
  Apply standard scroll chrome to the main project content area.
- `Apps/Views/Log/LogView.swift`
  Apply standard scroll chrome to the log `List`.
- `Apps/Views/CommandConfigView.swift`
  Apply compact scroll chrome to the command-config collection.
- `Apps/Views/CommandConfig/Components/CommandConfigEditSheet.swift`
  Apply compact scroll chrome to the edit sheet form.
- `Apps/Views/DevEnvironment/Components/Sheets/BrowserInstancesSheet.swift`
  Apply compact scroll chrome to the browser-instance sheet.
- `Apps/Views/Shared/Components/TerminalPanel.swift`
  Apply compact scroll chrome to terminal output.
- `Apps/TechneApp.swift`
  Restore standard termination commands and pin the menu bar extra to menu style.
- `Apps/Views/MenuBarView.swift`
  Give the quit row an explicit `Cmd+Q` shortcut so the open menu handles quit immediately.
- `Apps/AppDelegate.swift`
  Remove the custom `Cmd+Q` event monitor and keep only lifecycle responsibilities that still belong in the delegate.

## Implementation Notes

- Use two surface roles only:
  - `mainContent`: dense but primary app content. Respect `NSScroller.preferredScrollerStyle`; only use overlay autohide when the system preference is already overlay.
  - `utilityPanel`: sheets, forms, terminal panes, and other tight utility surfaces. Keep the same visibility policy as the system preference, but use a lighter scroller control size.
- Do **not** force hidden scrollers when the system preference is legacy or always-visible. That would violate the design decision already made for the user at the OS level.
- Do **not** add per-screen ad hoc `NSScrollView` code. Every scroll surface must go through `appScrollChrome(_:)`.
- Do **not** keep context-sensitive quit behavior. After this change, `Cmd+Q` is a single global contract again.

### Task 1: Introduce The Shared Scroller Policy

**Files:**
- Create: `Apps/Views/Shared/Scrolling/AppScrollerPolicy.swift`
- Create: `Apps/Views/Shared/Scrolling/AppScrollChrome.swift`
- Test: `TechneTests/App/AppScrollerPolicyTests.swift`

- [ ] **Step 1: Write the failing tests for policy resolution**

```swift
import AppKit
import Testing
@testable import Techne

struct AppScrollerPolicyTests {
    @Test
    func mainContentFollowsLegacySystemPreference() {
        let configuration = AppScrollerPolicy.configuration(
            for: .mainContent,
            preferredStyle: .legacy
        )

        #expect(configuration.scrollerStyle == .legacy)
        #expect(configuration.autohidesScrollers == false)
        #expect(configuration.controlSize == .regular)
    }

    @Test
    func utilityPanelUsesOverlayAutohideWhenSystemPrefersOverlay() {
        let configuration = AppScrollerPolicy.configuration(
            for: .utilityPanel,
            preferredStyle: .overlay
        )

        #expect(configuration.scrollerStyle == .overlay)
        #expect(configuration.autohidesScrollers)
        #expect(configuration.controlSize == .small)
    }
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/AppScrollerPolicyTests
```

Expected: FAIL because `AppScrollerPolicy` does not exist yet.

- [ ] **Step 3: Implement the policy type and SwiftUI modifier**

Create `Apps/Views/Shared/Scrolling/AppScrollerPolicy.swift`:

```swift
import AppKit

enum AppScrollSurfaceRole {
    case mainContent
    case utilityPanel
}

struct AppScrollerConfiguration: Equatable {
    let scrollerStyle: NSScroller.Style
    let autohidesScrollers: Bool
    let controlSize: NSControl.ControlSize
}

enum AppScrollerPolicy {
    static func configuration(
        for role: AppScrollSurfaceRole,
        preferredStyle: NSScroller.Style = NSScroller.preferredScrollerStyle
    ) -> AppScrollerConfiguration {
        switch (role, preferredStyle) {
        case (.mainContent, .legacy):
            return AppScrollerConfiguration(
                scrollerStyle: .legacy,
                autohidesScrollers: false,
                controlSize: .regular
            )

        case (.mainContent, .overlay):
            return AppScrollerConfiguration(
                scrollerStyle: .overlay,
                autohidesScrollers: true,
                controlSize: .regular
            )

        case (.utilityPanel, .legacy):
            return AppScrollerConfiguration(
                scrollerStyle: .legacy,
                autohidesScrollers: false,
                controlSize: .small
            )

        case (.utilityPanel, .overlay):
            return AppScrollerConfiguration(
                scrollerStyle: .overlay,
                autohidesScrollers: true,
                controlSize: .small
            )
        @unknown default:
            return configuration(for: role, preferredStyle: .overlay)
        }
    }
}
```

Create `Apps/Views/Shared/Scrolling/AppScrollChrome.swift`:

```swift
import SwiftUI
import AppKit

struct AppScrollChrome: ViewModifier {
    let role: AppScrollSurfaceRole

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.automatic)
            .background(AppScrollViewConfigurator(role: role))
    }
}

extension View {
    func appScrollChrome(_ role: AppScrollSurfaceRole) -> some View {
        modifier(AppScrollChrome(role: role))
    }
}

private struct AppScrollViewConfigurator: NSViewRepresentable {
    let role: AppScrollSurfaceRole

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyConfiguration(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(from: nsView)
        }
    }

    private func applyConfiguration(from hostView: NSView) {
        guard let scrollView = sequence(first: hostView.superview, next: \.superview)
            .compactMap({ $0 as? NSScrollView })
            .first
        else {
            return
        }

        let configuration = AppScrollerPolicy.configuration(for: role)
        scrollView.scrollerStyle = configuration.scrollerStyle
        scrollView.autohidesScrollers = configuration.autohidesScrollers
        scrollView.verticalScroller?.controlSize = configuration.controlSize
        scrollView.horizontalScroller?.controlSize = configuration.controlSize
    }
}
```

- [ ] **Step 4: Run the tests again**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/AppScrollerPolicyTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Apps/Views/Shared/Scrolling/AppScrollerPolicy.swift Apps/Views/Shared/Scrolling/AppScrollChrome.swift TechneTests/App/AppScrollerPolicyTests.swift
git commit -m "feat: add shared scroller policy"
```

### Task 2: Apply Scroll Chrome To All App-Owned Scroll Surfaces

**Files:**
- Modify: `Apps/ContentView.swift`
- Modify: `Apps/Views/ProjectListView.swift`
- Modify: `Apps/Views/Log/LogView.swift`
- Modify: `Apps/Views/CommandConfigView.swift`
- Modify: `Apps/Views/CommandConfig/Components/CommandConfigEditSheet.swift`
- Modify: `Apps/Views/DevEnvironment/Components/Sheets/BrowserInstancesSheet.swift`
- Modify: `Apps/Views/Shared/Components/TerminalPanel.swift`
- Test: `TechneTests/App/AppScrollerPolicyTests.swift`

- [ ] **Step 1: Extend the tests with a regression for utility surfaces**

Add this test to `TechneTests/App/AppScrollerPolicyTests.swift`:

```swift
@Test
func utilityPanelKeepsLegacyVisibilityWhenSystemWantsVisibleScrollBars() {
    let configuration = AppScrollerPolicy.configuration(
        for: .utilityPanel,
        preferredStyle: .legacy
    )

    #expect(configuration.scrollerStyle == .legacy)
    #expect(configuration.autohidesScrollers == false)
    #expect(configuration.controlSize == .small)
}
```

- [ ] **Step 2: Run the tests to confirm current coverage still fails if the policy changes incorrectly**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/AppScrollerPolicyTests
```

Expected: PASS before wiring views. This keeps the policy locked while the surface rollout happens.

- [ ] **Step 3: Apply the modifier consistently**

Use `mainContent` on primary browsing surfaces:

```swift
List(SidebarItem.allCases, selection: $selectedItem) { item in
    Label(item.rawValue, systemImage: item.icon)
        .tag(item)
        .padding(.vertical, 4)
}
.listStyle(.sidebar)
.appScrollChrome(.mainContent)
```

```swift
ScrollView {
    VStack(spacing: AppConfig.UI.extraLargePadding) {
        // existing content
    }
    .padding(AppConfig.UI.extraLargePadding)
}
.appScrollChrome(.mainContent)
```

```swift
List(filteredLogs, selection: $selection) { log in
    Text(formatLogLine(log))
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(logColor(for: log.level))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
}
.listStyle(.inset)
.appScrollChrome(.mainContent)
```

Use `utilityPanel` on compact forms and sheets:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: AppConfig.UI.largePadding) {
        // existing form fields
    }
    .padding(AppConfig.UI.extraLargePadding)
}
.appScrollChrome(.utilityPanel)
```

```swift
ScrollView {
    VStack(spacing: AppConfig.UI.largeSpacing) {
        ForEach(instances) { instance in
            InstanceDetailCard(instance: instance)
        }
    }
    .padding(AppConfig.UI.extraLargePadding)
}
.appScrollChrome(.utilityPanel)
```

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 0) {
        Text(displayedText)
            .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
            .foregroundStyle(output.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConfig.UI.mediumSpacing)

        Color.clear
            .frame(height: 1)
            .id("terminalBottom")
    }
}
.appScrollChrome(.utilityPanel)
```

- [ ] **Step 4: Build and manually verify every scroll surface**

Run:

```bash
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Manual verification checklist:
- Main window sidebar uses system-style scroll bars and hides them when the macOS preference is overlay.
- Project list, settings, and logs no longer have mixed scroll behavior.
- Command config sheet, browser instance sheet, and terminal output use lighter scrollers without layout clipping.
- No scroll view loses wheel, trackpad, or keyboard scrolling.

Expected: BUILD SUCCEEDED and all checklist items pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/ContentView.swift Apps/Views/ProjectListView.swift Apps/Views/Log/LogView.swift Apps/Views/CommandConfigView.swift Apps/Views/CommandConfig/Components/CommandConfigEditSheet.swift Apps/Views/DevEnvironment/Components/Sheets/BrowserInstancesSheet.swift Apps/Views/Shared/Components/TerminalPanel.swift TechneTests/App/AppScrollerPolicyTests.swift
git commit -m "feat: unify app scroll chrome"
```

### Task 3: Restore Standard Quit Semantics And Menu Bar Shortcut Routing

**Files:**
- Modify: `Apps/TechneApp.swift`
- Modify: `Apps/Views/MenuBarView.swift`
- Modify: `Apps/AppDelegate.swift`

- [ ] **Step 1: Remove the custom quit interceptor and restore standard app termination**

In `Apps/TechneApp.swift`, remove the empty replacement of `.appTermination` and pin the menu bar extra to menu mode:

```swift
.commands {
    MainWindowNavigationCommands()
    TechneAppCommands()
}

MenuBarExtra("Techne", systemImage: "macbook.and.iphone") {
    MenuBarView()
        .environment(launchSettings)
        .environment(mainWindowNavigationCoordinator)
}
.menuBarExtraStyle(.menu)
```

In `Apps/AppDelegate.swift`, delete:

```swift
private var eventMonitor: Any?
private weak var activeToastView: NSView?
private var quitTimerTask: Task<Void, Never>?
private var lastQuitKeyTime: Date? = nil
setupQuitBehavior()
handleQuitAttempt()
showQuitHint()
hideQuitHint()
showFloatingQuitHint(with:)
preferredQuitHintTargetFrame()
createToastView(with:)
```

Keep only launch-mode handling, reopen handling, and cleanup that still exists after the monitor is removed.

- [ ] **Step 2: Make the menu bar menu advertise and handle `Cmd+Q` directly**

Update `Apps/Views/MenuBarView.swift`:

```swift
Button("退出 Techne") {
    NSApp.terminate(nil)
}
.keyboardShortcut("q", modifiers: .command)
```

This keeps the menu row explicit while also allowing the open menu bar menu to execute quit immediately from the keyboard.

- [ ] **Step 3: Build and verify quit behavior in all supported contexts**

Run:

```bash
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Manual verification checklist:
- With the main window focused, pressing `Cmd+Q` exits immediately.
- With only the menu bar menu open, pressing `Cmd+Q` exits immediately without needing the click target.
- Clicking the explicit `退出 Techne` row still exits.
- Login-item launch behavior still suppresses the main window on startup.
- Reopening from the menu bar still restores the main window correctly.

Expected: BUILD SUCCEEDED and all checklist items pass.

- [ ] **Step 4: Commit**

```bash
git add Apps/TechneApp.swift Apps/Views/MenuBarView.swift Apps/AppDelegate.swift
git commit -m "feat: restore standard quit behavior"
```

### Task 4: Final Cross-Version Verification

**Files:**
- Modify: none
- Test: existing build plus manual QA notes captured in the PR description or session notes

- [ ] **Step 1: Run the focused automated tests**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/AppScrollerPolicyTests
```

Expected: PASS.

- [ ] **Step 2: Run a full debug build**

Run:

```bash
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Verify on macOS 15 and current macOS 26 target environment**

Manual matrix:
- macOS 15 with system scroll bars set to automatic/overlay:
  - main content scroll indicators stay hidden until interaction
  - compact sheets use lighter scrollers
  - `Cmd+Q` exits from main window and menu bar menu
- macOS 15 with system scroll bars set to always visible:
  - app does not force-hide scroll bars
  - compact sheets still use lighter scroller size
- macOS 26 latest:
  - no regression in menu bar interaction
  - scroll chrome continues to feel native under the current platform visual style

- [ ] **Step 4: Commit any follow-up fixes**

```bash
git add -A -- .
git commit -m "test: verify scroll policy and quit regressions"
```

## Self-Review

- Spec coverage:
  - Global scroll behavior is addressed by Task 1 and Task 2.
  - Hiding scroll bars only when the OS is already using overlay behavior is explicit in the policy and verification matrix.
  - Direct `Cmd+Q` quitting from the menu bar menu is addressed by Task 3.
  - macOS 15 compatibility and current macOS 26 behavior are covered by Task 4.
- Placeholder scan:
  - No `TODO`, `TBD`, or implicit “handle later” text remains.
- Type consistency:
  - `AppScrollSurfaceRole`, `AppScrollerConfiguration`, `AppScrollerPolicy`, and `appScrollChrome(_:)` use one naming scheme throughout the plan.

Plan complete and saved to `docs/superpowers/plans/2026-05-22-scroll-policy-and-standard-quit.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
