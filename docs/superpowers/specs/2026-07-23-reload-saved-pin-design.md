# Reload Saved Pin

## Problem

Notion can render its own “This page couldn't be found” screen inside the PiP even when the same page opens successfully in the user's regular browser. WebKit treats that Notion screen as a successful navigation, so `NotionWebSession` does not enter its native failure state.

Re-entering the page URL can recover the PiP, but the Change Pinned Page surface does not show the URL that the app already persists. In addition, selecting a page with the same page ID follows the existing reselection path, which does not generally force a new navigation.

## Goals

- Make the currently saved pin URL visible and reusable from Change Pinned Page.
- Provide a one-click recovery that navigates to the saved canonical URL.
- Preserve the existing pin and persistence semantics.
- Keep the existing workflow for replacing the pin with a different URL.

## Non-goals

- Diagnose or alter the user's Notion account, workspace, permissions, or cookies.
- Detect Notion's in-page error screen by inspecting Notion's private DOM.
- Add a history of previously pinned pages.
- Clear WebKit website data or sign the user out of Notion.

## User Experience

When a pinned page exists, the page controls opened by **Change Pinned Page…** show that page's saved canonical URL in the URL field.

The page controls show two actions:

- **Reload Saved Pin** navigates the PiP directly to the saved canonical URL and closes the setup popover.
- **Pin** validates the field and keeps the existing behavior of pinning or replacing the page.

**Reload Saved Pin** is shown only when a saved pin exists. It uses the saved value owned by the runtime rather than uncommitted edits in the text field.

## Architecture

### Input state and presentation

`PageURLInputState` gains an optional saved page reference. Whenever `AppRuntime` activates or restores a pin, it synchronizes that page into the input state and fills the field with its canonical URL. The saved page reference remains separate from editable field text, so typing another URL cannot change the recovery target.

The shared `PageURLInputView` accepts an optional recovery callback and renders **Reload Saved Pin** alongside the normal **Pin** action only when a saved page and callback are available. The setup popover opened by **Change Pinned Page…** and the page section in Settings supply the runtime callback. `PageURLInputWindowContent` retains its current entry-only behavior because it is used when no page is pinned.

### Recovery command

`AppRuntime` exposes a dedicated `reloadSavedPin()` action. It reads the saved page reference from input state, delegates recovery through `PinCoordinator`, hides the setup popover, and leaves persistence untouched.

`PinCoordinator` and `PiPPanelCoordinating` gain narrowly named recovery operations. The panel coordinator presents the panel and asks the page loader to force-load the saved page even when its page ID matches the active page.

The loader API gains the corresponding operation. `NotionWebSession` implements it by:

1. Clearing transient new-page state.
2. Reaffirming the active page and saved URL identity.
3. Revealing native controls.
4. Loading a new `URLRequest` for `page.canonicalURL`.

It does not call `WKWebView.reload()`, because the WebView may currently be on a Notion-owned error or redirect route.

### Persistence

Recovery does not create a new recent entry or rewrite the pinned-page repository. It reuses the already persisted canonical URL and page ID. Replacing the pin through **Pin Page** retains the current persistence behavior.

## Error Handling

- If no active page exists, the recovery action is unavailable and performs no work.
- If the canonical navigation fails at the WebKit layer, the existing native failure banner and retry behavior remain responsible for feedback.
- If Notion renders the same in-page access error again, the app leaves the user on that page; this feature does not inspect or depend on Notion's DOM.

## Testing

- Activating or restoring a page synchronizes its canonical URL into page-input state.
- Page input without a saved page hides the recovery action.
- **Reload Saved Pin** loads the canonical URL even when the saved page ID matches the active page.
- Recovery shows the panel and closes the setup popover.
- Recovery does not enqueue a pinned-page persistence write.
- Editing the text field does not change the URL used by **Reload Saved Pin**.
- **Pin** continues to validate, replace, persist, and report invalid input as before.
- The WebSession test asserts that recovery issues a new `URLRequest` rather than calling WebView reload.
