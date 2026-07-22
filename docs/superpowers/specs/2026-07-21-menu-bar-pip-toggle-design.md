# Menu-Bar PiP Toggle Design

## Goal

Make the menu-bar icon act as the fastest path back to the pinned Notion page. When a page is already pinned, a regular click toggles the floating PiP panel. Users must still have a visible, discoverable way to reach every command currently available from the menu-bar window.

## Research and Design Rationale

Apple describes a menu-bar extra as a way to expose app-specific functionality while the app is not frontmost. Its current Human Interface Guidelines recommend displaying a menu when someone clicks a menu-bar extra and recommend exposing the same functionality in other ways. Apple also warns against making modifier-driven or otherwise hidden behavior the only way to perform an action.

This feature intentionally makes the regular click a direct PiP toggle because showing and hiding the pinned page is the app's primary repeated action. To preserve discoverability despite that departure from the default menu behavior, the complete command menu will be available from a visible toolbar button inside the PiP. A right-click on the menu-bar icon will open the same command menu as a secondary shortcut, not as the only way to reach it.

References:

- [Apple Human Interface Guidelines: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [Apple Developer Documentation: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)

## Interaction Model

### Regular click

- If a Notion page is pinned and the PiP panel is hidden, show the existing panel and bring it to the front.
- If a Notion page is pinned and the PiP panel is visible, hide it.
- If no Notion page is pinned, open the existing setup/options surface so the user can paste or search for a page.
- Repeated clicks must toggle only panel visibility. They must not reload the WebView, replace the page, or discard its navigation/session state.

### Command access

- Add a visible app-menu button to the PiP toolbar using the `ellipsis.circle` SF Symbol and the accessibility label "Notion PiP menu."
- Clicking that button opens the full app command menu.
- Right-clicking the menu-bar icon opens the same command menu without changing PiP visibility.
- The two menus share one command definition so their labels, enabled states, keyboard shortcuts, and actions cannot drift.

### Command menu contents

The shared command menu contains these groups in order:

1. **Quick Capture** — opens the existing Quick Capture window.
2. **Change Pinned Page…** — opens the existing menu-bar setup/options surface. The ellipsis communicates that another interface is required.
3. **Settings…** — opens Settings.
4. **Quit Notion PiP** — terminates the app.

Workspace search and URL entry remain in the setup/options surface opened by **Change Pinned Page…**. They are not duplicated inside the compact command menu.

## Architecture

### Status-item controller

Replace the declarative `MenuBarExtra` click handling with a small AppKit status-item controller built around `NSStatusItem`. It owns only menu-bar event routing and presentation of the shared command menu.

The controller will:

- render the existing `rectangle.on.rectangle` symbol as a template image;
- listen for both left-mouse and right-mouse events on the status-item button;
- send a regular click to a runtime-level toggle action;
- present the shared command menu for a right-click;
- retain a new setup/options presenter used when no page is pinned or when **Change Pinned Page…** is chosen.

This controller must not own the pinned page or WebView. Those remain in `AppRuntime` and `PiPPanelCoordinator`.

### PiP visibility API

Extend `PiPPanelWindow` and `PiPPanelCoordinating` with explicit visibility and toggle behavior. The coordinator is the source of truth for whether the panel is onscreen because it owns the `NSPanel`.

The API needs to support:

- reading whether the panel is visible;
- showing the already-loaded current page without activating it again;
- hiding the panel;
- toggling visibility when a current page exists.

`PinCoordinator` exposes the panel toggle through a narrow `toggleCurrentPage() -> Bool` operation. It returns `false` when the panel has no current page. `AppRuntime` exposes a single menu-bar activation method that calls this operation and asks the setup/options presenter to show on `false`. Existing page activation paths continue to call `PinCoordinator.pin(page:)` and show the panel immediately.

### Setup/options presenter

The current setup/options surface exists only as the content of `MenuBarExtra`; it does not yet have an independent presenter. Add a small presenter backed by a transient AppKit popover or panel that hosts `MenuBarRootView` and anchors it to the status item. It provides explicit show, hide, and toggle operations.

Refactor `MenuBarRootView` so Quick Capture and Settings are injected actions instead of relying on scene-only environment actions. This keeps the existing surface and feature logic reusable when hosted by the new presenter.

### Shared command model

Define command identity, labels, grouping, and actions once in a small app-command model owned at the app composition root. Both the AppKit status-item menu and the SwiftUI `Menu` in `PiPChromeView` render from that model.

The command model coordinates presentation but does not duplicate feature logic:

- Quick Capture uses a dedicated presenter for the existing Quick Capture view and session. This replaces the `openWindow` dependency that is only available inside the current SwiftUI scene.
- Change Pinned Page uses the setup/options presenter.
- Settings opens the existing Settings scene through the platform Settings action or an equivalent dedicated presenter.
- Quit uses `NSApp.terminate(nil)`.

## State and Data Flow

```text
Regular status-icon click
          |
          v
AppRuntime.handleMenuBarActivation()
          |
     active page?
       /     \
     no       yes
     |         |
show setup   PiPPanelCoordinator.toggle()
surface       /                    \
          visible                hidden
             |                      |
            hide            show existing panel
                             without reloading page

Right-click status icon ----+
PiP toolbar menu button -----+--> shared app command menu
```

The WebView session stays alive while the panel is hidden because the existing panel and `NotionWebSession` are retained. Toggle operations change only window ordering and visibility.

## Presentation Details

- A regular click that shows the PiP activates the accessory app and makes the panel key, matching the behavior used when a page is first pinned.
- Hiding the PiP uses the existing `orderOut` path and does not clear `currentPage`.
- The visible toolbar menu button sits with the existing reload, browser, surface picker, and close controls. It appears before the close button so the close button remains the trailing destructive/dismissive control.
- The status item retains a tooltip such as "Show or hide Notion PiP. Right-click for menu." This helps explain the secondary shortcut without making it essential.
- The setup/options surface remains unchanged in scope and layout.

## Error and Edge-Case Behavior

- If runtime state says a page is active but the panel coordinator has no current page, treat the state as unavailable and open the setup/options surface instead of showing an empty panel.
- A right-click never toggles panel visibility, even when the panel is hidden.
- Choosing **Change Pinned Page…** does not hide the current PiP automatically. The user can compare the existing page while choosing a replacement; successfully pinning a replacement uses the current replacement path.
- A failed or loading WebView still counts as an active PiP and toggles normally. Existing retry UI remains responsible for navigation failures.
- Closing the PiP with its close button and hiding it with the menu-bar icon are equivalent; both preserve the loaded page.
- Status-item event routing must use the event type supplied by AppKit rather than relying on modifier keys or timing heuristics.

## Accessibility

- The menu-bar status item has an accessibility label that identifies Notion PiP and an accessibility help string describing the toggle behavior.
- The PiP toolbar app-menu button has an explicit accessibility label and a hit target consistent with the neighboring toolbar controls.
- All shared menu commands have textual labels, remain keyboard navigable, and preserve existing keyboard shortcuts where applicable.
- The toggle does not add animation, so Reduce Motion requires no special behavior.

## Testing

### Unit tests

- Regular activation with no active page presents the setup/options surface.
- Regular activation with a hidden active panel shows it without reloading the page.
- Regular activation with a visible active panel hides it.
- Hiding and showing preserves `currentPage`.
- Right-click routes to menu presentation and never changes panel visibility.
- Shared commands invoke Quick Capture, Change Pinned Page, Settings, and Quit actions exactly once.
- A runtime/panel state mismatch falls back to the setup/options surface.

### Integration checks

- Pin a page, hide the panel, click the status icon, and confirm the same WebView and navigation state return.
- Click the status icon again and confirm the panel hides.
- With no pinned page, click the status icon and confirm the setup/options surface opens.
- Open the command menu from the PiP toolbar and from a right-click; confirm both contain the same commands in the same order.
- Verify Quick Capture, Change Pinned Page, Settings, and Quit from the visible toolbar menu.
- Confirm left- and right-click behavior with VoiceOver focus on the status item and toolbar menu button.

## Out of Scope

- Persisting the pinned URL across app relaunches.
- Adding multiple simultaneous PiP panels.
- Redesigning workspace search, URL entry, Settings, or Quick Capture.
- Changing WebView authentication or navigation behavior.
