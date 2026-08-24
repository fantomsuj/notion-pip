# Changelog

## Unreleased

### Added

- Context Suggestions can connect a user-initiated Perch reveal to the exact
  Notion page focused in supported browsers or the native Notion app.
- Empty Perch sessions open a strictly validated detected page through the
  existing activation pipeline. Occupied sessions reveal immediately and show
  a dismissible **Open Here** action without automatic replacement.
- Raw Accessibility candidates remain transient and unlogged; a contextually
  opened page follows the ordinary device-local page history and persistence
  flow.
- Global shortcut, menu-bar Show, status-item peek, edge-handle restore, edge
  pull, and Restore Current shelf paths invalidate older asynchronous results.

### Changed

- SwiftData schema migrates to V5, dropping the unused Quick Capture models
  (`CaptureDraftModel`, `CaptureRecordModel`, `QuickCaptureSettingsModel`) from
  the live schema. Existing stores migrate automatically via a lightweight
  V4→V5 stage; pinned pages, recents, active page, and scroll restoration are
  preserved.

### Fixed

- Dragging or trackpad-moving the PiP can travel past a left or right screen
  edge. Releasing with at least 40% of the panel hidden stashes it instead of
  snapping it back on-screen.
- Drag-to-stash now treats another display as blocking whenever the overhang
  actually enters that display, including gapped and overlapping arrangements.
- Releasing a drag below the 40% threshold pulls the panel back on-screen
  instead of leaving it hanging off the edge.
- Live horizontal travel is capped so the panel cannot disappear completely
  during a drag.

### Privacy

- Exact-page checks reuse the existing opt-in Accessibility permission, inspect
  only focused `AXDocument`/`AXURL` attributes on a bounded path, and never read
  page contents, clipboard data, or titles for exact-page inference.

### CI

- SwiftPM build artifacts are cached in CI and nightly reliability runs, keyed on
  `Package.resolved`, so Sparkle is not recompiled from scratch when dependencies
  are unchanged.
- Dependabot now monitors the SwiftPM dependency (Sparkle) in addition to
  GitHub Actions.
- The release configuration build now runs on pull requests, not only on push,
  so a broken release build is caught before merge.
