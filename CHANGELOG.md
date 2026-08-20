# Changelog

## Unreleased

### Added

- Context Suggestions can connect a user-initiated Perch reveal to the exact
  Notion page focused in supported browsers or the native Notion app.
- Empty Perch sessions open a strictly validated detected page through the
  existing activation pipeline. Occupied sessions reveal immediately and show
  a dismissible **Open Here** action without automatic replacement.
- Global shortcut, menu-bar Show, status-item peek, edge-handle restore, edge
  pull, and Restore Current shelf paths invalidate older asynchronous results.

### Privacy

- Exact-page checks reuse the existing opt-in Accessibility permission, inspect
  only focused `AXDocument`/`AXURL` attributes on a bounded path, and never read
  page contents, clipboard data, or titles for exact-page inference.
