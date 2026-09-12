# Console Boundary Repair Design

## Goal

Preserve the console-panel componentization introduced by commit `18a36519` while removing three boundary regressions:

1. Global scroll-bar behavior must continue to respect macOS system preference outside console-specific viewports.
2. Structured logs must optimize for readability before visual uniformity.
3. `ContentView.preview()` and its tests must use isolated, deterministic dependencies with no real persistence or background refresh side effects.

## Scope

In scope:

- `AppScrollerPolicy` and `AppScrollChrome` behavior for `mainContent`, `utilityPanel`, and `consoleViewport`
- `StructuredLogTableView` layout behavior
- Preview-only dependency construction used by `ContentView.preview()`
- Targeted tests covering the three regressions above

Out of scope:

- Redesigning console panel visual language
- Reworking production startup dependency injection across the entire app
- Replacing `NSTableView` with a different log rendering technology

## Design

### 1. Scroll policy boundaries

`consoleViewport` keeps an explicit console-specific scroller treatment because those viewports are backed by dedicated AppKit scroll views (`ConsoleViewportScrollView`).

`mainContent` and `utilityPanel` keep the app's explicit window-level scroll chrome requirement: overlay scrollers, no legacy border treatment, and auto-hide when idle.

This remains bounded because the styling only applies to explicitly marked app surfaces. We still do not recurse into arbitrary descendant scroll views.

`AppScrollChrome` will stop recursively styling arbitrary descendant scroll views. Its responsibility is limited to the enclosing SwiftUI-managed scroll view for the host surface.

### 2. Structured log readability

`StructuredLogTableView` remains the structured log host, but each row must wrap and grow vertically for long content. The viewport keeps the new shared console chrome; only the row layout changes.

The table view should compute row height from available column width and the monospaced log string attributes. Rows should no longer truncate to a single line.

### 3. Hermetic preview environment

`ContentView.preview()` will stop instantiating live app services directly. A dedicated preview-only environment builder will:

- create isolated persistence services rooted under the temporary directory
- construct `CommandConfigService` and `ProjectService` from those isolated stores
- disable initial persistence restore / refresh side effects for preview rendering
- provide the navigation coordinator needed by the view

The preview environment object will be internal so tests can verify the boundary contract directly.

## Verification

- `AppScrollerPolicyTests` verify system-preference behavior for `mainContent` and `utilityPanel`, and explicit console behavior for `consoleViewport`.
- `ConsolePanelStyleTests` verify long structured log rows expand beyond the single-line baseline.
- `ContentViewPreviewTests` verify preview dependencies use temporary isolated storage and do not begin loading work on construction.
