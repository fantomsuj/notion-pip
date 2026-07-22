# Global Shortcut Toggle Design

## Goal

Make the existing `Command-Shift-P` global shortcut show or hide the currently pinned Notion PiP instead of reading a URL from the clipboard. If no page is pinned, the shortcut opens and focuses the existing URL prompt.

## Interaction

- When a page is pinned and its PiP is hidden, the shortcut brings the same panel to the front.
- When a page is pinned and its PiP is visible, the shortcut hides it.
- When no page is pinned, the shortcut opens and focuses the URL prompt.
- The shortcut never reads the clipboard.
- Hiding and showing the PiP preserves the pinned page, WebView, navigation state, and session.

## Architecture

The panel coordinator remains the source of truth for panel visibility. It exposes a toggle operation that checks its retained current page and the underlying panel's visibility. Toggling changes only window presentation: it calls the existing present path when hidden and the existing order-out path when visible.

`PinCoordinator` exposes this behavior as `toggleCurrentPage() -> Bool`. A `true` result means a pinned panel was toggled. A `false` result means there is no current page.

`AppRuntime` registers the global shortcut with one action: try `toggleCurrentPage()`, and ask the existing page-URL presenter to present and focus only when it returns `false`. Existing URL entry, page search, external-route, and explicit page activation paths remain unchanged.

Clipboard parsing can remain available as an independent coordinator capability, but it is no longer part of global-shortcut dispatch.

## Error and Edge-Case Behavior

- Runtime `activePage` is not used to decide whether a panel can toggle; the panel coordinator's `currentPage` is authoritative.
- A panel containing a loading or failed page still toggles normally.
- A shortcut registration failure retains the existing logging behavior.
- Opening the URL prompt when no page is pinned does not synthesize validation feedback or mutate page state.

## Testing

Automated tests will verify:

- a shortcut shows a hidden pinned panel;
- a shortcut hides a visible pinned panel;
- toggling retains the same current page;
- showing an existing panel does not reactivate or replace the page;
- a shortcut with no pinned page presents and focuses the URL prompt;
- shortcut dispatch does not read the clipboard.

The full Swift test suite will be run after the focused regression tests pass.

## Out of Scope

- Changing the `Command-Shift-P` key combination.
- Persisting the pinned page across launches.
- Changing menu-bar icon behavior or command menus.
- Removing clipboard support from unrelated flows.
