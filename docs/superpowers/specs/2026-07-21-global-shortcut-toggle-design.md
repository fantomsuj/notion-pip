# Global Shortcut Stash Design

## Goal

Make the existing `Command-Shift-P` global shortcut stash or restore the currently pinned Perch instead of reading a URL from the clipboard. If no page is pinned, the shortcut opens and focuses the existing URL prompt.

## Interaction

- When a page is pinned and its PiP is visible, the shortcut stashes it on the nearest horizontal screen edge.
- When a page is pinned and its PiP is stashed or otherwise hidden, the shortcut brings the same panel to the front.
- When no page is pinned, the shortcut opens and focuses the URL prompt.
- The shortcut never reads the clipboard.
- Hiding and showing the PiP preserves the pinned page, WebView, navigation state, and session.

## Architecture

The panel coordinator remains the source of truth for panel visibility. It exposes a shortcut-specific stash-or-restore operation that checks its retained current page and the underlying panel's visibility. A visible panel uses the edge-stash placement policy; a hidden or stashed panel uses the existing present path and dismisses any edge handle.

`PinCoordinator` exposes this behavior as `stashOrRestoreCurrentPage() -> Bool`. A `true` result means a pinned panel was stashed or restored. A `false` result means there is no current page. The existing `toggleCurrentPage() -> Bool` remains available to the menu-bar click so its show/hide interaction does not change.

`AppRuntime` registers the global shortcut with one action: try `stashOrRestoreCurrentPage()`, and ask the existing page-URL presenter to present and focus only when it returns `false`. Existing URL entry, page search, external-route, and explicit page activation paths remain unchanged.

Clipboard parsing can remain available as an independent coordinator capability, but it is no longer part of global-shortcut dispatch.

## Error and Edge-Case Behavior

- Runtime `activePage` is not used to decide whether a panel can stash or restore; the panel coordinator's `currentPage` is authoritative.
- A panel containing a loading or failed page still stashes and restores normally.
- A shortcut registration failure retains the existing logging behavior.
- Opening the URL prompt when no page is pinned does not synthesize validation feedback or mutate page state.

## Testing

Automated tests will verify:

- a shortcut shows a hidden or stashed pinned panel;
- a shortcut stashes a visible pinned panel;
- stashing and restoring retain the same current page;
- showing an existing panel does not reactivate or replace the page;
- a shortcut with no pinned page presents and focuses the URL prompt;
- shortcut dispatch does not read the clipboard.

The full Swift test suite will be run after the focused regression tests pass.

## Out of Scope

- Changing the `Command-Shift-P` key combination.
- Persisting the pinned page across launches.
- Changing menu-bar icon behavior or command menus.
- Removing clipboard support from unrelated flows.
