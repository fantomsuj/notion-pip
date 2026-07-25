# Consolidated Settings Design

## Goal

Give Notion PiP one reliable native Settings window that contains the current pinned-page controls, global shortcut configuration, personal Notion access, service health, and application information. Remove the overlapping `Change Pinned Page…` entry point.

## User Experience

### Settings window

`Settings…` opens a retained, explicitly presented native window. This replaces the current attempt to dispatch AppKit's `showSettingsWindow:` action to a SwiftUI-only `Settings` scene, which can leave the user with no visible settings UI.

The window presents these sections in order:

1. **Pinned Page** — the existing URL input, connected-workspace search, and active pinned-page summary. Submitting or selecting a page retains the current replacement behavior.
2. **Global Shortcut** — a shortcut recorder showing the current global shortcut, with reset-to-default. The default remains Command-Shift-P. A valid new shortcut takes effect immediately; if macOS cannot register it, the UI keeps the prior working shortcut and reports the existing shortcut-health issue.
3. **Personal Notion Access** — the existing connect, reconnect, disconnect, and token-state UI.
4. **Service Health** — existing recoverable service issues, when any exist.
5. **About** — existing app and system information.

The Settings window is reusable: choosing Settings while it is already open brings it forward rather than creating a second copy.

### Menu-bar behavior

The shared command menu removes `Change Pinned Page…`; it retains `Settings…`, Quick Capture, New Notion Page, and Quit. Both the PiP ellipsis menu and menu-bar right-click menu continue to use the same command model.

When a normal click on the menu-bar icon occurs with no pinned page, the app opens the consolidated Settings window, focused on the Pinned Page section. With a pinned page, the existing show/hide behavior is unchanged.

## Architecture

### Explicit settings presenter

Introduce a small `SettingsWindowPresenter` backed by the existing AppKit window-presenter abstraction. `AppComposition` owns it, passes it to `AppCommandActionRelay`, and injects it into `AppRuntime` for the no-page menu-bar fallback.

The native window hosts `SettingsView(runtime:)`. It is retained for the app lifetime, centered on first presentation, made key/front on later presentation, and uses standard titled/closable/resizable window behavior. The SwiftUI `Settings` scene and its environment-based `openSettings` action are removed so there is one authoritative presentation path.

### Settings view composition

Extract the page-selection controls currently hosted in the setup popover into a reusable Settings section. The section receives the existing runtime and reuses its URL validation, search, and page-pinning APIs. No page-selection behavior is reimplemented.

Remove `SetupOptionsPopoverPresenter` and the now-obsolete `MenuBarRootView` once their page-selection content has moved. The status item no longer needs a popover anchor.

### Shortcut model and persistence

Define a Codable shortcut value with a Carbon virtual key code and supported modifier flags, validate it against an intentionally limited set of non-empty modifier combinations, and persist the user choice in `UserDefaults`. Its default is Command-Shift-P.

`CarbonGlobalShortcutRegistrar` accepts a shortcut when registering. It unregisters the prior Carbon registration before attempting a replacement, and restores the known-good registration if the new registration fails. `AppRuntime` owns applying the selection, publishing the chosen shortcut for the Settings view, and surfacing the existing global-shortcut recovery health issue when registration cannot be completed.

The recorder captures a key-down event while it is active, rejects modifier-only keys and unsupported inputs with clear inline feedback, and does not use Accessibility permission or any third-party hotkey framework.

## Error Handling

- Settings presentation failure is avoided by using a retained explicit window; repeat invocations foreground the existing window.
- A new shortcut that is unavailable or rejected leaves the previous shortcut active and displays the registration problem in Service Health.
- An invalid recorded key combination never changes the saved shortcut.
- The existing URL validation, disconnected-search messaging, token handling, and service-health recovery behaviors remain unchanged.

## Testing

Focused tests will cover:

- invoking Settings opens or foregrounds one settings window;
- the command model no longer exposes `Change Pinned Page…` and Settings invokes its presenter;
- no-pinned-page menu-bar activation opens Settings;
- persisted shortcut decoding/defaulting and validation;
- applying a new shortcut unregisters/re-registers correctly;
- failed replacement retains the previous registration and reports health;
- resetting restores Command-Shift-P.

The full Swift test suite and the project build/launch verification will run after focused tests pass.

## Out of Scope

- Additional appearance, startup, or PiP behavior preferences that do not exist today.
- Multiple user-defined shortcuts.
- Accessibility-permission-dependent shortcut capture.
- Changes to the PiP lifecycle, Notion authentication, or Quick Capture behavior.
