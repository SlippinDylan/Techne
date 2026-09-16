# Console Boundary Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the scroll-policy, structured-log, and preview-isolation regressions without discarding the console component architecture added in commit `18a36519`.

**Architecture:** Keep console-specific chrome inside dedicated console viewport primitives, restore general app scrolling to system-derived behavior, and introduce a preview-only dependency builder that isolates persistence and startup work. Validate each behavior with targeted tests before production edits.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, `xcodebuild`

---

### Task 1: Lock in regression tests

**Files:**
- Modify: `TechneTests/App/AppScrollerPolicyTests.swift`
- Modify: `TechneTests/Views/ConsolePanelStyleTests.swift`
- Modify: `TechneTests/App/ContentViewPreviewTests.swift`

- [ ] Add failing assertions for system-respecting scroll policy, multi-line structured log rows, and hermetic preview dependencies.
- [ ] Run the targeted tests and confirm they fail for the expected reasons.

### Task 2: Restore scroll-policy boundaries and log readability

**Files:**
- Modify: `Apps/Views/Shared/Scrolling/AppScrollerPolicy.swift`
- Modify: `Apps/Views/Shared/Scrolling/AppScrollChrome.swift`
- Modify: `Apps/Views/Shared/Components/StructuredLogTableView.swift`

- [ ] Restore the intended app-window overlay/autohide scroll policy for explicitly marked surfaces without reintroducing descendant scroll-view bleed.
- [ ] Keep console-only scroller styling inside `ConsoleViewportScrollView`.
- [ ] Replace fixed single-line structured log rows with wrapped dynamic-height rows.
- [ ] Run the focused scroll/log tests and confirm they pass.

### Task 3: Build hermetic preview dependencies

**Files:**
- Modify: `Apps/ContentView.swift`
- Modify: `Apps/Services/ProjectService.swift`
- Modify: `Apps/Services/Shared/PersistenceService.swift` if a preview helper is needed there

- [ ] Introduce a preview dependency builder with isolated temporary persistence.
- [ ] Add an explicit startup mode for `ProjectService` so preview construction does not load or refresh real state.
- [ ] Update `ContentView.preview()` to consume that builder.
- [ ] Run the preview tests and the existing targeted regression suite.
