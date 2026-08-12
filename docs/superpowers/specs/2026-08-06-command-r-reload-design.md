# Command-R Reload Design

## Goal

Let a user press `Command-R` while interacting with the Perch panel to reload the URL currently displayed by its embedded `WKWebView`, including a Notion sign-in page.

## Scope

- Add a standard macOS `View` menu containing `Reload` with the `Command-R` key equivalent.
- Route the action through AppKit's responder chain so the focused `WKWebView` handles `reload:`.
- Preserve the existing "Re-pin current Notion page" action, which intentionally reloads the saved canonical page and clears restoration state.
- Do not register `Command-R` as a system-wide shortcut.
- Do not include the unrelated SwiftData store-location collision in this change.

## Approaches Considered

### 1. AppKit responder-chain command (selected)

Add a targetless `Reload` menu item whose action is `reload:`. `WKWebView` already implements that action, so AppKit enables and routes it only when an appropriate responder is focused. This matches normal macOS browser behavior with minimal new state or wiring.

### 2. Shared application command model

Add a reload command to `AppCommandModel` and wire it directly to `NotionWebSession.reload()`. This would also expose Reload in the menu-bar and panel command menus, but it duplicates responder-chain behavior and requires lifecycle and enablement plumbing that the requested shortcut does not need.

### 3. Carbon global shortcut

Register `Command-R` through the existing global shortcut registrar. This would intercept a ubiquitous shortcut across every application and is therefore inappropriate.

## Components and Data Flow

`AppMainMenuFactory` creates a `View` menu with a targetless `Reload` item. When the user presses `Command-R`, `NSApplication` sends `reload:` through the active window's responder chain. The focused `WKWebView` handles the action and reloads its current URL using its existing cookie and session state.

## Error Handling

The menu uses AppKit auto-enablement. When no responder can reload, the command is disabled rather than invoking a no-op application callback. Network and authentication failures remain visible inside Notion's web UI and use existing WebKit behavior.

## Testing

Extend `AppMainMenuTests` to verify that:

- the `View` menu exists;
- `Reload` uses the `reload:` selector;
- the menu item has no explicit target;
- its key equivalent is `r` with the Command modifier; and
- a `WKWebView` accepts the routed action.

Run the focused test first for the red-green cycle, then run the full Swift suite with the repository-mandated Xcode toolchain.
