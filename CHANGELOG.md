# Changelog

## Unreleased

### Fixed

- The hover strip that reveals the top controls now covers only the top
  corner, so it no longer catches clicks on Notion's scrollbar.
- Panel spring animations use `NSAnimationContext` and stay smooth at 120 Hz.
  A cancelled animation always finishes, so later drags are never ignored.
- Space-change key hints are filtered before any work is scheduled, so
  ordinary typing no longer spawns a task per keystroke.
- Perch's typing, scroll, and content-ready bridges run in an isolated
  JavaScript world, so scripts on a page can't fake their messages.
- Custom pinned URLs no longer run Notion-only scripts, and they get the same
  single automatic reload as Notion pages when the web content crashes.
- Agent text is inserted with the browser's `insertText` editing command,
  falling back to a direct insert only when the command does nothing.

### Removed

- Context Suggestions (frontmost-app page matching and reveal-time exact-page
  detection) has been removed. Perch no longer requests Accessibility access.

## 0.1.3 - 2026-08-26

### Added

- Settings → Install Agent Skill now writes the same agent-neutral skill for
  Claude Code, Codex, and Cursor, with expanded protocol documentation for
  routes, status, cancellation, errors, and idempotency.
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
