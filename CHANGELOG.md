# Changelog

## Unreleased

### Removed

- Deleted the unused Quick Copy prototype (the Accessibility selection
  monitor, its controller, button, and tests). Nothing in the app started it,
  and it is still in git history if it is ever needed again.

## 0.1.4 - 2026-10-22

### Added

- Custom Pins (beta): turn it on in Settings to keep a non-Notion HTTPS site,
  such as Canvas, in the panel. Your last Notion page stays saved, and both
  Settings and the panel controls offer a one-click return to Notion. While a
  custom pin is open, sign-in redirects stay in the panel so SSO can finish.
- Settings has a toggle to hide the stash icon at the screen edge. The panel
  still stashes normally, and the global shortcut brings it back.
- Onboarding spells the default shortcut out as Cmd + Shift + P instead of
  ⌘⇧P, so the Shift symbol is no longer mistaken for an arrow key.

### Changed

- Switching pages, or between a page and a custom URL, now navigates the one
  live web view instead of destroying it and building a new one, so a switch
  no longer starts a new web content process or throws away its warm caches.
  The view is still destroyed on eviction.
- Dragging the panel, or moving it with the two-finger top-edge gesture, now
  saves its position once when the move ends instead of on every frame of the
  drag. The panel position menu only updates when its values change, and
  trackpad scrolling no longer looks up screen frames on every event.
- A hidden Perch now gives its Notion web view back after 10 minutes, or right
  away when macOS warns about memory pressure. Showing the panel again restores
  the page and its scroll position.
- If WebKit's page process exits while Perch is hidden, the page now reloads
  the next time you show the panel instead of straight away in the background.
- Perch now remembers whether the panel was stashed. A launch (including
  Launch at Login) after quitting with the panel tucked away restores it
  stashed behind the edge handle and does not build the web view or load the
  page until the panel is shown.
- Launch picks one restore target before showing anything: the last custom
  URL when one was open, otherwise the saved Notion page. Perch no longer
  starts loading the Notion page only to replace it; the Notion page stays the
  return target.
- The retired personal-token Keychain cleanup runs once per install behind a
  done flag instead of on every launch. It still deletes the items without
  reading them, and a failed pass retries on the next launch.

### Fixed

- When the panel's web view is replaced while it is on screen (for example a
  page switch while Notion recovers from a web content crash), the panel shows
  the new view instead of possibly staying blank on the removed one.
- Quitting Perch, or turning off Local Agents, no longer hangs when a local
  process has opened an agent connection and sent nothing. Stopping the
  listener now closes every open connection, and each connection gets a
  5-second read and write timeout (idle clients receive `408
  request_timeout`).
- The local agent listener serves at most 8 connections at once and answers
  extras with `503 server_busy` and `Retry-After`.
- The bearer token is checked before the shared rate limit, so other local
  processes without the token can no longer cause `429` responses for the real
  agent. `429` responses now include `Retry-After`.
- Oversized agent requests get a `413 payload_too_large` response instead of a
  silent close.
- Quickly turning Local Agents off and on no longer lets the old listener's
  shutdown clear the new listener's state.
- Saved scroll positions now read Notion's own page scroller instead of the
  window, which Notion never scrolls, so returning to a page lands where you
  left it. The active page's position is also saved when you quit.
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
- Agent streaming is sturdier: stale notification accepts are ignored, stream
  acknowledgements are smaller, expired streams are cleaned up on schedule,
  and the ready overlay is more compact.

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
