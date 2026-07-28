# Open in Notion and Stash PiP

## Problem

The PiP toolbar uses Safari’s system icon for an action that opens the current
Notion page using macOS’s default URL handler. That makes the destination look
browser-specific even though it may open the native Notion app. Once the page
is handed off, the PiP also remains on screen unnecessarily.

## Goals

- Replace the Safari glyph with a compact Notion-style template mark.
- Open the active page through the existing system URL route so macOS continues
  to choose the user’s preferred Notion app or browser.
- Immediately stash the currently visible PiP after the page-open action.
- Keep the existing accessible name for the action and the normal stash button.

## Non-goals

- Change the URL-routing policy or force a particular browser or app.
- Add a downloaded or remote icon asset.
- Change pinned-page persistence, page selection, or stash-handle behavior.

## Design

`PiPChromeView` gains a small reusable SwiftUI view that draws the Notion mark
from vector primitives and renders it as a template image. The toolbar button
uses this view in place of `Image(systemName: "safari")`; its visible size and
plain button styling stay consistent with the neighboring controls.

The button action becomes a view method. It calls
`NotionWebSession.openInBrowser()` first, retaining the current system URL
handler behavior, then invokes its existing `onStash` callback. The callback is
already wired by `PiPPanelCoordinator` to `stashOrRestoreCurrentPage()`; while
the toolbar is visible the panel is visible, so the PiP moves to its existing
edge stash handle. If no active page exists, both existing no-op safeguards
remain in effect.

## Error Handling

- No active page: URL opening remains a no-op and stashing reports no current
  page, leaving the view unchanged.
- No usable display frame: existing stash policy leaves the panel visible;
  opening the external page still succeeds.
- A default URL-handler failure remains owned by macOS and does not alter PiP
  session state.

## Testing

- A focused `PiPChromeView` test supplies an injected URL-opening session and
  stash callback, triggers the combined action, and asserts the page URL was
  opened once and the stash callback ran once.
- The full Swift package suite verifies no toolbar, session, or stash regression.
