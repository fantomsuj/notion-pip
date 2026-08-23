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
