# UI Stop Flow Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify ADB deploy UI with existing project UI patterns, close Techne-managed browser instances when a dev service project stops, and make mini app terminal output on-demand and collapsible without spreading display logic across unrelated modules.

**Architecture:** Reuse existing visual language by extracting shared surface components instead of copying color and border rules into more views. Keep browser discovery, browser launch, browser instance persistence, and browser instance termination as separate responsibilities by introducing a lifecycle-focused service for managed browser instances. Keep mini app terminal expand/collapse state in the view layer so project persistence remains process-centric and does not absorb presentation state.

**Tech Stack:** Swift, SwiftUI, AppKit, Observation, existing `ProjectService` / `BrowserLaunchService` / `BrowserInstanceStore` services, Swift Testing

---

## File Structure

**Modify**
- `Apps/Views/ADBDeployView.swift`
- `Apps/Views/ProjectCard.swift`
- `Apps/Services/ProjectService.swift`
- `Apps/Services/ChromeDetectionService.swift`

**Create**
- `Apps/Views/Shared/Components/InteractivePathField.swift`
- `Apps/Views/Shared/Components/TerminalPanel.swift`
- `Apps/Services/ManagedBrowserInstanceService.swift`
- `TechneTests/Browser/ManagedBrowserInstanceServiceTests.swift`

**Maybe Modify If Extraction Scope Expands**
- `Apps/Views/AddProjectSheet.swift`
- `Apps/Views/CommandConfig/Components/CommandConfigEditSheet.swift`

## Design Decisions

1. **Do not theme ADB locally.**
   The APK selector and ADB terminal must consume the same shared surface rules that already define project path fields and the mini app terminal. This avoids a third visual system and guarantees light/dark consistency through system colors.

2. **Do not let `ProjectService` depend on `ChromeDetectionService` UI state.**
   `ProjectService` should invoke a browser lifecycle service that reads tracked instance records directly from persistence and terminates matching instances. UI refresh remains the responsibility of `ChromeDetectionService`.

3. **Only close Techne-managed browser instances.**
   Use tracked instance metadata (`launchTarget.projectPath`) as the authority. This prevents accidental termination of unrelated user browser windows that happen to target the same port.

4. **Keep mini app terminal collapse state out of `Project`.**
   `Project` stores process state and output, not card presentation. Use local SwiftUI state in `ProjectCard`.

5. **Hide the mini app divider and terminal panel until there is an active or historical session to show.**
   Recommended visibility rule:
   - show toggle and panel when `project.transitionState != .idle`
   - or `project.isRunning`
   - or `project.terminalOutput` is not empty

## Task 1: Extract Shared UI Surfaces

**Files:**
- Create: `Apps/Views/Shared/Components/InteractivePathField.swift`
- Create: `Apps/Views/Shared/Components/TerminalPanel.swift`
- Modify: `Apps/Views/AddProjectSheet.swift`
- Modify: `Apps/Views/ADBDeployView.swift`
- Modify: `Apps/Views/ProjectCard.swift`

- [ ] Build `InteractivePathField` as a reusable container for click-to-select and drag-target scenarios.
  It should expose:
  - `leadingIcon`
  - `text`
  - `placeholder`
  - `trailingContent`
  - `action`
  - optional drop handler hook
  Visual rules must match the existing project path field exactly:
  - `Color(nsColor: .controlBackgroundColor)` background
  - `RoundedRectangle` with `AppConfig.UI.mediumCornerRadius`
  - `Color(nsColor: .separatorColor)` stroke at `0.5`
  - placeholder text in `.secondary`
  - content text in `.primary`

- [ ] Build `TerminalPanel` as a reusable terminal/log surface.
  It should own:
  - scroll-to-bottom behavior
  - empty text rendering
  - monospaced text
  - text selection enablement
  - the light/dark terminal surface matching mini app terminal styling
  It should accept:
  - `output`
  - `emptyText`
  - optional `height`
  - optional toolbar slot for copy/clear buttons

- [ ] Replace the inline project path field visuals in `AddProjectSheet` with `InteractivePathField` or a shared surface modifier.
  The goal is to make ADB reuse the source of truth, not visually imitate it.

- [ ] Replace the custom APK selector surface in `ADBDeployView` with the shared path field.
  Preserve current behavior:
  - click to choose file
  - drag `.apk`
  - show selected path
  - show file size pill if desired

- [ ] Replace the ADB console box with `TerminalPanel`.
  Keep the existing copy/clear actions, but move them into the panel toolbar slot so only the chrome differs from the mini app card, not the terminal surface itself.

- [ ] Replace the mini app terminal rendering in `ProjectCard` with `TerminalPanel`.
  This ensures requirement 1 and requirement 3 both land on the same component instead of two parallel implementations.

## Task 2: Add Managed Browser Lifecycle Service

**Files:**
- Create: `Apps/Services/ManagedBrowserInstanceService.swift`
- Modify: `Apps/Services/ChromeDetectionService.swift`
- Modify: `Apps/Services/ProjectService.swift`
- Test: `TechneTests/Browser/ManagedBrowserInstanceServiceTests.swift`

- [ ] Introduce `ManagedBrowserInstanceService` as the service that owns termination of tracked browser instances.
  Responsibilities:
  - load tracked instance records from `BrowserInstanceStore`
  - normalize project paths before matching
  - filter instances by `launchTarget.projectPath`
  - terminate matching PIDs
  - remove matching tracked records after confirmed exit
  - return a structured result containing total matched, terminated, and failed PIDs

- [ ] Keep `BrowserInstanceStore` as persistence only.
  Do not move kill logic into the store; it should remain file-system focused.

- [ ] Update `ChromeDetectionService` to consume `ManagedBrowserInstanceService` for manual instance close operations if practical.
  This removes duplicated PID termination logic and keeps one code path for cleanup semantics.

- [ ] Update `ProjectService.stopServer(for:)` for `.devServer` projects so stop becomes a coordinated sequence:
  1. mark project as stopping
  2. stop server process
  3. if server stop succeeds, terminate managed browser instances for `project.path`
  4. refresh browser detection state
  5. post server stopped notification
  6. run cache cleanup if enabled

- [ ] Do not close browsers for `.miniApp`.
  The requirement is scoped to `开发服务与实例`.

- [ ] Decide and document failure semantics.
  Recommended behavior:
  - server stop success remains the main result
  - browser termination failures are logged clearly
  - if any managed browser instances remain, emit warning-level logs with PID list
  This avoids reporting the whole stop action as failed after the main process has already stopped.

## Task 3: Mini App Terminal Visibility and Collapse Behavior

**Files:**
- Modify: `Apps/Views/ProjectCard.swift`

- [ ] Add local view state for the mini app terminal expansion flag.
  Recommended property:
  - `@State private var isMiniAppTerminalExpanded = true`

- [ ] Add a computed visibility gate in `ProjectCard`.
  Recommended property:
  - `shouldShowMiniAppTerminalControls`
  - `shouldRenderMiniAppTerminalSection`
  Suggested rule:
  - false when idle and output empty and not running
  - true otherwise

- [ ] Add a collapse/expand action button beside the existing start/stop button cluster for mini app cards only.
  Recommended SF Symbols:
  - expanded: `chevron.up`
  - collapsed: `chevron.down`
  or
  - expanded: `rectangle.bottomthird.inset.filled`
  - collapsed: `rectangle.bottomthird.inset`
  Reuse `ActionButton` sizing and hover behavior.

- [ ] Remove the unconditional divider and terminal section for mini app cards.
  Only render them when the visibility gate is true and the expansion state is enabled.

- [ ] Preserve logs across collapse.
  Collapse is presentational only; it must not clear `project.terminalOutput`.

## Task 4: Verification

**Files:**
- Test: `TechneTests/Browser/ManagedBrowserInstanceServiceTests.swift`
- Manual verification against:
  - `Apps/Views/ADBDeployView.swift`
  - `Apps/Views/ProjectCard.swift`
  - `Apps/Services/ProjectService.swift`

- [ ] Add unit tests for path-based instance selection.
  Cases:
  - same logical path with symlink normalization still matches
  - unrelated project path does not match
  - records without `launchTarget.projectPath` are ignored for auto-stop

- [ ] Add unit tests for cleanup behavior after successful termination.
  Cases:
  - matched records are removed
  - unmatched records remain

- [ ] Manual UI verification in light mode.
  Check:
  - APK selector surface is visually identical to the add-project project path field
  - ADB terminal surface is visually identical to the mini app terminal surface
  - mini app card shows no divider or terminal before first start
  - terminal toggle appears in the action area after start/output
  - collapse hides panel without clearing logs

- [ ] Manual UI verification in dark mode.
  Check the same list above and verify there is no hardcoded black overlay left in ADB.

- [ ] Functional verification for stop flow.
  Check:
  - launch one or more browser instances from a dev service project
  - stop that project
  - all Techne-managed instances tied to that project terminate
  - unrelated tracked browser instances stay alive

## Risks To Avoid

- Do not read browser instances from the card layer to decide what `ProjectService` should terminate.
- Do not persist mini app collapse state into the `Project` model.
- Do not use port-only matching as the primary authority for project-scoped browser termination.
- Do not copy the path field and terminal colors inline into `ADBDeployView`; extraction is the requirement, not a nice-to-have.
- Do not make the ADB terminal permanently visible if the design target is the mini app terminal surface only.

## Implementation Notes

- The current ADB input surface in [ADBDeployView.swift](/Users/dylanwang/Repo/Apps.Private/Techne/Apps/Views/ADBDeployView.swift:90) is a custom button shell and should be replaced by the shared field surface.
- The current mini app terminal surface in [ProjectCard.swift](/Users/dylanwang/Repo/Apps.Private/Techne/Apps/Views/ProjectCard.swift:342) is the visual reference for the new shared terminal panel.
- The current add-project path field in [AddProjectSheet.swift](/Users/dylanwang/Repo/Apps.Private/Techne/Apps/Views/AddProjectSheet.swift:70) is the visual reference for the shared path field.
- The current dev server stop path in [ProjectService.swift](/Users/dylanwang/Repo/Apps.Private/Techne/Apps/Services/ProjectService.swift:282) does not coordinate browser shutdown and is the required integration point.
- The current browser close logic in [ChromeDetectionService.swift](/Users/dylanwang/Repo/Apps.Private/Techne/Apps/Services/ChromeDetectionService.swift:57) is UI-driven and should not remain the only browser termination entry point.

## Outcome

If implemented as above:
- ADB deploy adopts the same field and terminal language already used elsewhere in the app.
- Dev service stop becomes a true “project session stop” instead of “server PID stop only”.
- Mini app cards stay visually quiet until they actually have a running/output session, then expose a controlled collapsible terminal area.
