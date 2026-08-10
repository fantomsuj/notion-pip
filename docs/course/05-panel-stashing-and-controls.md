# Lecture 5 — Panel Stashing and Global Controls

**Estimated duration:** 75 minutes

Notion PiP behaves less like a document window and more like an open notebook
kept beside the current task. This lecture follows that product idea through
AppKit window roles, pure screen-geometry policies, the retained panel and edge
handle, global shortcuts, the menu-bar fallback, and saved size presets.

> **Source-state note:** This lecture uses
> `29d5fa80e0ac70080d52e22388a6c4881d3d0484` as its starting product baseline.
> During course production, the working tree also contained uncommitted
> stash/handle animation work in `PiPPanelCoordinator.swift` and
> `PiPStashHandleController.swift`, plus global-shortcut implementation and test
> edits in `GlobalShortcutRegistrar.swift` and `GlobalShortcutTests.swift`.
> Those edits are not presented as baseline behavior here. The baseline does
> include the existing 0.18-second corner-snap frame animation in
> `KeyCapablePiPPanel`; committed stashing itself presents the handle and orders
> the panel out without an entrance/exit animation.

## Learning objectives

By the end of this lecture, you should be able to:

1. explain why the primary PiP is an `NSPanel`, why it can become key, and why
   the stash handle deliberately cannot;
2. distinguish the roles of AppKit window configuration, pure frame/stash
   policy, main-actor coordination, and SwiftUI controls;
3. describe the intentional all-Spaces and full-screen-overlay behavior without
   misreporting it as an `NSPanel` defect;
4. trace visible → stashed → dragged handle → restored without creating a new
   panel or loading the page again;
5. predict first-use placement, autosaved-frame compatibility, display
   clamping, corner snapping, and preferred-size restoration;
6. explain tap-versus-hold behavior for the panel shortcut and the independent
   Quick Capture shortcut;
7. describe how the status item remains a recovery path when global shortcut
   registration fails;
8. explain built-in and custom size presets, including the distinction between
   changing a default and applying it; and
9. choose an automated test seam while naming which real-window claims still
   need the [manual matrix](../MANUAL_TEST_MATRIX.md).

This is a mixed-level lecture. New macOS developers should read **Foundation**
in full. Experienced AppKit developers can begin at **Repository tour**, but
should still note the repository-specific retained-panel and shortcut semantics.

## Before you begin

Recommended prerequisites:

- [Lecture 1](01-product-and-user-experience.md), especially the open-notebook
  model and stash/peek journey;
- [Lecture 3](03-application-lifecycle.md) for the accessory activation policy,
  AppKit event loop, and `@MainActor`;
- [Lecture 4](04-composition-and-runtime.md) for `AppComposition`, `AppRuntime`,
  controller boundaries, and retained ownership; and
- the [`NSPanel` glossary entry](GLOSSARY.md#nspanel) if AppKit window classes
  are new to you.

Keep four coordinate and lifetime facts visible while reading:

1. AppKit window frames use screen coordinates; displays may have negative or
   nonzero origins.
2. `NSScreen.frame` is the full display, while `visibleFrame` excludes occupied
   areas such as the menu bar and Dock.
3. A content size is not always a window-frame size because title-bar chrome
   contributes to the outer frame.
4. `orderOut` hides a retained window. It does not close its page session or
   construct a replacement.

The primary authority for this lecture is committed source, particularly
[`WindowRolePolicy.swift`](../../Sources/NotionPiP/Platform/WindowRolePolicy.swift),
[`PanelFramePolicy.swift`](../../Sources/NotionPiP/Platform/PanelFramePolicy.swift),
[`PanelStashPolicy.swift`](../../Sources/NotionPiP/Platform/PanelStashPolicy.swift),
and
[`PiPPanelCoordinator.swift`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift).
Historical stash design documents can explain intent, but they do not override
the current implementation.

**Manual-verification boundary:** do not infer actual Spaces, Stage Manager,
Mission Control, focus, or multi-display behavior merely from option flags or a
unit test. The source proves which behavior the app requests. Only a staged app
under the real WindowServer proves what the user observes.

## Foundation

### One feature, four layers

The panel system is easiest to understand as four cooperating layers:

| Layer | Question it answers | Repository examples |
|---|---|---|
| Value and geometry policy | “Given these rectangles or values, what should the result be?” | `PanelFramePolicy`, `PanelStashPolicy`, `PanelSizePreferences` |
| AppKit adapter | “Which real window exists, and how is it shown or hidden?” | `WindowRolePolicy`, `KeyCapablePiPPanel`, `PiPStashHandleController`, `StatusItemController`, Carbon registrar |
| Main-actor coordinator | “Which transition happens now, and what state must survive it?” | `PiPPanelCoordinator`, `PanelSizeController`, `AppRuntime`, `PinCoordinator` |
| SwiftUI surface | “Which controls and accessibility affordances does the user receive?” | `PiPChromeView`, `PiPStashHandleView`, `PanelSizeMenu`, `PanelSizeSettingsView` |

The pure layers receive values and return values. They do not inspect global
window state or activate applications. The AppKit and coordinator layers are
`@MainActor` because they own or drive UI objects. This separation lets tests
exercise geometry and state transitions without pretending that a fake window
is the macOS WindowServer.

### `NSWindow`, `NSPanel`, key status, and activation

An `NSWindow` is an on-screen container. An `NSPanel` is a specialized window
commonly used for auxiliary or floating UI. The class alone does not determine
the complete behavior: style mask, level, collection behavior, activation, and
overrides all matter.

“Key” means a window receives keyboard events for its application. It is not
the same as merely being visible or floating. The repository uses:

- `KeyCapableAppWindow`, an `NSWindow` whose `canBecomeKey` is `true`, for
  Settings, Quick Capture, and page input;
- `KeyCapablePiPPanel`, an `NSPanel` whose `canBecomeKey` is `true`, for the
  editable Notion overlay; and
- plain nonactivating `NSPanel` instances for the stash handle and its
  contextual recent-pages shelf, so passive hover does not seize keyboard
  focus.

Full panel presentation calls `NSApp.activate(ignoringOtherApps: true)` and
`makeKeyAndOrderFront`. Handle presentation uses `orderFrontRegardless` on a
nonactivating panel. This is the key focus contract: restore the editor as an
active typing surface, but leave the handle passive until clicked or accessed
through its button semantics.

### Collection behavior is requested product policy

The PiP, stash handle, and contextual shelf request:

```text
canJoinAllSpaces + fullScreenAuxiliary + transient + ignoresCycle
```

In product terms, the overlay is intended to follow work across Spaces, remain
eligible beside a full-screen app, stay out of ordinary window cycling, and act
as transient overlay UI. Quick Capture, Settings, and page input instead use
`moveToActiveSpace + fullScreenAuxiliary`.

The persistent all-Spaces panel is intentional. It must not be diagnosed as an
`NSPanel` defect. Conversely, source flags are not proof that every macOS,
Stage Manager, display, and “Displays have separate Spaces” combination behaves
identically. Those observations belong in the manual matrix.

### Hide, stash, close, and release are different verbs

- **Hide/order out:** remove a retained window from the screen.
- **Stash:** save the logical full-panel frame, show a 36×96 edge handle, notify
  the web lifecycle that the panel hid, and order the full panel out.
- **Close button on the PiP:** request the same stash transition; it does not
  discard the page.
- **Restore:** restore/clamp the saved frame, show the same panel, remove the
  handle, and notify the web lifecycle that the panel showed.
- **Release:** destroy an owned presentation resource. The PiP stash path does
  not do this.

That vocabulary matters because the app maintains one composition-owned
`PiPPanelCoordinator`, one retained PiP panel, and the shared `NotionWebSession`.
SwiftUI may host or unhost its web view according to session lifecycle, but
stashing is not permission to manufacture a second panel or a second live
Notion browser. Lecture 6 owns the detailed WebKit lifecycle model.

## Repository tour

### Window-role table

[`WindowRolePolicy.swift`](../../Sources/NotionPiP/Platform/WindowRolePolicy.swift)
centralizes construction policy rather than scattering flags among presenters:

| Role | Concrete kind | Level | Initial content | Minimum content | Space policy |
|---|---|---:|---:|---:|---|
| Quick Capture | key-capable `NSWindow` | floating | 520×520 | 440×400 | move to active Space; full-screen auxiliary |
| Settings | key-capable `NSWindow` | normal | 480×460 | 440×420 | move to active Space; full-screen auxiliary |
| Pin Page | key-capable `NSWindow` | floating | 440×180 | 440×180, also maximum | move to active Space; full-screen auxiliary |
| Picture in Picture | key-capable `NSPanel` | floating | 520×680 | 360×420 | all Spaces; full-screen auxiliary; transient; ignored by cycle |
| Stash handle | nonactivating borderless `NSPanel` | floating | zero before placement | zero | same overlay collection behavior as PiP |
| Stash shelf | nonactivating borderless `NSPanel` | floating | zero before attachment | zero | same overlay collection behavior as PiP |

Every policy also sets `hidesOnDeactivate = false` and
`isReleasedWhenClosed = false`. The PiP and application windows override
`close()` so the red close control orders out or invokes a feature-specific
handler instead of accepting AppKit's default destruction semantics.

[`WindowRolePolicyTests.swift`](../../Tests/NotionPiPTests/WindowRolePolicyTests.swift)
checks the constructed classes and configured values. It does **not** prove
cross-Space visibility, Mission Control exclusion, keyboard focus under another
app, or Stage Manager behavior.

### The coordinator owns the presentation state machine

[`PiPPanelCoordinator`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift)
implements both `PiPPanelCoordinating` and `PanelSizing`. Its minimal public
presentation state is:

```text
currentPage == nil                 → unavailable
currentPage != nil && panel visible → visible
currentPage != nil && panel hidden  → stashed
```

The implementation retains the panel, page loader, optional handle,
preferred working content size, saved stash frame, display/anchor preference,
and AppKit notification observers. `show(page:)` activates or reselects a page,
restores a saved frame if necessary, presents the retained panel, dismisses the
handle, and reports `panelDidShow`. Re-selecting the same canonical URL does not
activate a second page load.

Composition constructs exactly one `KeyCapablePiPPanel` and one
`PiPStashHandleController`. That controller owns the resting handle and the
contextual shelf panel, while the panel coordinator remains unaware of shelf
details. One `NSHostingView` contains `PiPChromeView`.
[`NotionPiPApp.swift`](../../Sources/NotionPiP/App/NotionPiPApp.swift) constructs
that coordinator once with the one shared `NotionWebSession`, then retains the
graph through `AppComposition` for the event-loop lifetime.

### Frame policy: requested size, effective frame, and anchor

[`PanelFramePolicy.swift`](../../Sources/NotionPiP/Platform/PanelFramePolicy.swift)
contains deterministic rectangle functions:

- `targetVisibleFrame` chooses the display with greatest frame intersection,
  breaking ties by center distance;
- `initialFrame` selects the display whose full frame contains the pointer,
  then positions against its visible frame at a 24-point top-right inset;
- `frameSize` and `contentSize` use injected AppKit conversion closures so
  title-bar dimensions are counted once;
- `clamped` normalizes minimum size, caps oversized dimensions to available
  space, and constrains the origin;
- `nearestAnchor` records left/right and bottom/top edge plus inset;
- `placement` returns the effective outer frame while retaining the requested
  content size and anchor; and
- `cornerSnapped` snaps only when both axes are within the 24-point inset plus
  a 72-point threshold.

The coordinator adds lifecycle policy around those functions. With no
autosaved frame, first placement is deferred until the first presentation so
the pointer's current display can be used. With an autosaved frame and saved
working size, the size is reapplied around the saved location. With only legacy
AppKit autosave data, the frame is clamped but remains authoritative. Screen
configuration changes reclamp visible panels and reposition visible handles.

A completed manual resize replaces `preferredWorkingContentSize` and is sent
to `PanelSizeController`. A move updates the preferred display and nearest
anchor. After a 140-millisecond quiet period, the coordinator waits until the
primary mouse button is up and may snap a near-corner frame. In committed
`HEAD`, that corner-snap frame change animates for 0.18 seconds with ease-out.

[`PanelFramePolicyTests.swift`](../../Tests/NotionPiPTests/PanelFramePolicyTests.swift)
protects negative-origin displays, pointer selection, title-bar conversion,
minimum and oversized clamping, corner behavior, and preferred-size restoration.
[`PinCoordinatorTests.swift`](../../Tests/NotionPiPTests/PinCoordinatorTests.swift)
protects coordinator use of those decisions with fake panels and handles.

### Stash policy and handle lifecycle

[`PanelStashPolicy.swift`](../../Sources/NotionPiP/Platform/PanelStashPolicy.swift)
has no AppKit dependency. For a full panel, it chooses the target visible
display, selects left when the panel center is on or left of the display center
and right otherwise, vertically centers the 36×96 handle on the panel, and
clamps it inside usable vertical space. For a dragged handle, it chooses a side
from the handle center, preserves the dragged vertical origin when possible,
and clamps at the top or bottom.

[`PiPStashHandleController.swift`](../../Sources/NotionPiP/Platform/PiPStashHandleController.swift)
turns that value into real handle and shelf windows. It installs a SwiftUI
handle for the current side, presents the handle at the policy frame, and
retains restore and placement-change callbacks only while visible. Hover or a
secondary click loads recent history and derives the shelf frame from
`PanelStashShelfPolicy`; the larger shelf frame never participates in drag
snapping. `orderOut()` cancels shelf work, hides both surfaces, and clears the
current placement and presentation callbacks.

[`PiPStashHandleView.swift`](../../Sources/NotionPiP/Views/PiPStashHandleView.swift)
combines SwiftUI appearance with an `NSViewRepresentable` interaction surface.
The AppKit view accepts first mouse, distinguishes a click from a drag after a
3-point Euclidean threshold, moves the panel during dragging, and reports the
final window frame on mouse-up. It exposes button role, label, help, tooltip,
and `accessibilityPerformPress` so restore is not pointer-only. On drag end,
the controller snaps to a valid display edge, reinstalls side-specific content,
and reports the new placement to the panel coordinator. If no visible display
can be resolved, it returns the handle to its previous frame.

The recent-page data and selection flow is:

```text
RecentPageModel history → PiPRecentPagesShelfController → shelf row
→ AppRuntime.activate(..., source: .pageSwitcher, restoration: ...)
→ PinCoordinator → retained PiP panel
```

Hovering only reads page identity, visit time, and restoration metadata. It
does not instantiate another WebView, activate the application, change the
current page, move the handle, or alter saved stash placement. A failed or
missing persistent store therefore suppresses only the shelf; the ordinary
handle remains a click and drag recovery surface.

Policy behavior is covered by
[`PanelStashPolicyTests.swift`](../../Tests/NotionPiPTests/PanelStashPolicyTests.swift);
the click/drag/accessibility split is covered by
[`PiPStashHandleInteractionTests.swift`](../../Tests/NotionPiPTests/PiPStashHandleInteractionTests.swift).

### Chrome, menus, status item, and activation routes

[`PiPChromeView.swift`](../../Sources/NotionPiP/Views/PiPChromeView.swift) exposes
the in-panel stash button and an **Open in Notion** action that opens the active
canonical URL before requesting stash. Its top controls appear after hover and
stay available for VoiceOver, Switch Control, or Full Keyboard Access. The
ellipsis embeds [`PiPAppCommandMenu`](../../Sources/NotionPiP/Views/PiPAppCommandMenu.swift),
including the shared [`PanelSizeMenu`](../../Sources/NotionPiP/Views/PanelSizeMenu.swift).

[`StatusItemController.swift`](../../Sources/NotionPiP/Platform/StatusItemController.swift)
creates the menu-bar item, observes effective visibility, and asks
[`AppKitCommandMenuFactory`](../../Sources/NotionPiP/Platform/AppKitCommandMenuFactory.swift)
for a fresh menu on either left- or right-mouse-up. The first command is derived
from current panel state:

| State at menu creation | Context command |
|---|---|
| unavailable | **Open Settings…** |
| visible | **Stash Notion PiP** |
| stashed | **Show Notion PiP** |

The runtime rechecks state before honoring a captured stash/show command, so a
menu opened before a state change does not accidentally invert the new state.
Both the status menu and panel ellipsis use the same command model and size
controller. The normal application Edit menu in
[`AppMainMenuFactory.swift`](../../Sources/NotionPiP/Platform/AppMainMenuFactory.swift)
routes Undo, Redo, Cut, Copy, Paste, and Select All through the AppKit responder
chain so the key web or text view can handle them.

### Shortcut registration and fallback

[`GlobalShortcut.swift`](../../Sources/NotionPiP/Platform/GlobalShortcut.swift)
defines validated, persistable Carbon key codes and modifiers. The defaults are:

- panel show/stash/peek: Command-Shift-P;
- Quick Capture: Command-Shift-N.

They have independent stores and may not be assigned the same combination.
[`CarbonGlobalShortcutRegistrar`](../../Sources/NotionPiP/Platform/GlobalShortcutRegistrar.swift)
registers pressed and released events, replaces an existing binding, and tries
to restore the previous known-good binding if replacement fails.

[`AppRuntime+Activation.swift`](../../Sources/NotionPiP/App/AppRuntime+Activation.swift)
interprets panel shortcut events:

- release before the 300-millisecond hold threshold is a tap;
- a tap stashes a visible current panel or restores a stashed one;
- a tap with no current page presents and focuses page URL input;
- a hold restores only a stashed panel as a temporary peek;
- release after such a peek stashes it again; and
- a hold that began while the panel was already visible leaves it visible on
  release.

If panel shortcut registration fails, runtime publishes
`.globalShortcutUnavailable`. If the user had hidden the menu-bar icon, runtime
temporarily forces its **effective** visibility on without changing the saved
preference. A successful retry clears the health issue and the forced override.
This prevents a failed shortcut plus a hidden icon from silently removing the
global recovery surface. The visible edge handle remains another restore route
while the panel is stashed.

Shortcut value/replacement behavior is protected by
[`GlobalShortcutTests.swift`](../../Tests/NotionPiPTests/GlobalShortcutTests.swift),
tap routing and status fallback by
[`RuntimeActivationAndMenuBarTests.swift`](../../Tests/NotionPiPTests/RuntimeActivationAndMenuBarTests.swift),
and hold-to-peek by
[`RuntimePinnedPagePersistenceTests.swift`](../../Tests/NotionPiPTests/RuntimePinnedPagePersistenceTests.swift).
Real Carbon registration conflicts and OS delivery remain manual.

### Size presets from value model to surfaces

[`PanelSizePreferences.swift`](../../Sources/NotionPiP/Domain/PanelSizePreferences.swift)
owns validated values and mutations:

| Built-in | Requested content size |
|---|---:|
| Compact | 420×520 |
| Comfortable | width = clamp(34% of screen, 480...560); height = clamp(70%, 560...720) |
| Wide | 680×720 |

All stored content sizes must be finite, at least 360×420, and no greater than
4096 on either axis. Custom sizes additionally use whole points. Names are
trimmed, contain 1–40 characters, and are unique case-insensitively; built-in
names are reserved. Up to 12 custom presets are allowed. Stable IDs survive
edits. Deleting the default custom preset selects Comfortable but does not
resize the panel.

[`PanelSizePreferencesStore.swift`](../../Sources/NotionPiP/Persistence/PanelSizePreferencesStore.swift)
stores versioned JSON in `UserDefaults`. Missing data returns `nil` so legacy
AppKit frame autosave can remain authoritative. Corrupt, invalid, or unsupported
stored data falls back to safe defaults.

[`PanelSizeController.swift`](../../Sources/NotionPiP/App/PanelSizeController.swift)
is the observable orchestration layer. It binds weakly to the coordinator's
`PanelSizing` surface, derives whether Apply is available, resolves adaptive
sizes against the panel's target display, persists the requested working size,
and converts model/storage errors to UI messages. Changing **Default Size**
persists only a future/default choice. The user must choose **Apply Default** or
**Reset to Default Size** to resize now.

Applying a size preserves the panel's nearest edge relationship. If the panel
is stashed, applying restores the retained panel and dismisses the handle
without a page reload. If a display temporarily cannot fit the request, the
effective frame clamps while the requested preferred content size survives for
restoration on a larger display. Manual resize persistence occurs only after
`NSWindow.didEndLiveResizeNotification`, not on every intermediate frame.

Settings uses
[`PanelSizeSettingsView.swift`](../../Sources/NotionPiP/Views/PanelSizeSettingsView.swift)
to manage defaults and custom values even when no page exists; Apply remains
disabled until a panel has a pinned page. Both native and SwiftUI menus use the
same preset order, default suffix, enablement, reset, and manage actions.

## Runtime trace

### Stash → drag → restore, end to end

Assume one page is active, the full panel is visible on the right half of a
display, and the user presses the in-panel stash button.

```mermaid
sequenceDiagram
    participant C as PiPChromeView
    participant P as PiPPanelCoordinator
    participant G as PanelStashPolicy
    participant H as PiPStashHandleController
    participant V as PiPStashHandleInteractionView
    participant W as NotionWebSession/page loader
    participant N as KeyCapablePiPPanel

    C->>P: stashOrRestoreCurrentPage()
    P->>G: placement(panel.frame, visibleFrames)
    G-->>P: right-side 36×96 placement
    P->>P: stashedPanelFrame = panel.frame
    P->>H: present(placement, restore, placementChange)
    P->>W: panelDidHide()
    P->>N: orderOut()
    V->>V: mouse drag passes 3 pt threshold
    V->>H: onDragEnded(handle window frame)
    H->>G: snappedPlacement(frame, visibleFrames)
    G-->>H: edge-snapped placement
    H->>P: onPlacementChange(placement)
    V->>H: click/accessibility activation
    H->>P: retained restore callback
    P->>P: preferredPlacement(saved full-panel frame)
    P->>N: setFrame(...); present()
    P->>H: orderOut(); clear callbacks
    P->>W: panelDidShow()
```

In concrete order:

1. `PiPChromeView.onStash` reaches
   `PiPPanelCoordinator.stashOrRestoreCurrentPage()`.
2. Because state is `.visible`, `stash` asks pure `PanelStashPolicy` for a
   placement. If there is no current page, no handle, or no visible screen,
   stashing returns `false` and the full panel stays visible.
3. The coordinator saves `panel.frame` as `stashedPanelFrame`. This is the
   logical restoration frame; the full panel is not resized into a tab.
4. It presents the incoming handle **before** ordering out the outgoing panel,
   preventing a transition with no visible representation.
5. It calls `pageLoader.panelDidHide()` and then `panel.orderOut()`. The current
   page and coordinator remain retained; no `activate(page:)` occurs.
6. During a drag, `PiPStashHandleInteractionView` moves the small handle window.
   Mouse-up reports the final frame only after the 3-point threshold has made
   the gesture a drag rather than restore.
7. The handle controller asks `snappedPlacement` to choose an edge/display and
   clamp vertical position. It updates the real handle and tells the panel
   coordinator which moved placement is active for later screen changes.
8. A later click, accessibility press, status command, or shortcut reaches a
   restore route. Direct handle activation calls `restoreFromStash`; global
   toggles call `showCurrentPage`.
9. The coordinator recomputes a safe frame from the saved logical frame,
   preferred size, preserved anchor, and current visible displays. It sets that
   frame before presentation.
10. `KeyCapablePiPPanel.present()` activates the app and calls
    `makeKeyAndOrderFront`, then the coordinator orders out the handle and
    reports `panelDidShow()`.
11. The loader's activated-page list is unchanged. The same coordinator,
    current page, and panel return; WebKit retention/resumption details continue
    in Lecture 6.

[`PinCoordinatorTests.swift`](../../Tests/NotionPiPTests/PinCoordinatorTests.swift)
checks frame retention, no reload, lifecycle notifications, representation
ordering, handle movement, screen changes, red-close behavior, and both toggle
directions with fakes.
[`PiPPanelGeometryTests.swift`](../../Tests/NotionPiPTests/PiPPanelGeometryTests.swift)
also constructs the real panel class and checks that stashing does not resize
it. Neither test proves real focus, Spaces, visual continuity, or retained
Notion editing under WindowServer; use the manual matrix for those claims.

## Deep dive

### Pure policy versus AppKit behavior

| Claim | Owning code | Automated evidence can establish | Still manual |
|---|---|---|---|
| Which display/edge/frame should be chosen | `PanelFramePolicy`, `PanelStashPolicy` | Exact rectangle output, negative origins, clamping, tie-breaking | Whether current `NSScreen` values match a physical Stage Manager/Dock setup at the instant of interaction |
| Which window flags are requested | `WindowRolePolicy` | Concrete class, masks, level, configured collection behavior | Actual all-Spaces presence, full-screen coexistence, Mission Control and Command-` behavior |
| Which representation transition is ordered | `PiPPanelCoordinator` with fakes | Handle-before-panel-out, panel-before-handle-out, retained current page, no loader activation | Visual continuity, focus, keyboard editing, timing under WindowServer |
| Click versus drag | AppKit interaction view | 3-point split, moved frame, accessibility callback | Pointer feel, trackpad behavior, VoiceOver announcement in the running app |
| Shortcut state machine | runtime plus fake registrar | tap/hold branching, fallback call, retained page | Carbon conflict, delivery while other apps/full-screen Spaces are active |
| Size validation and persistence | value model, controller, isolated defaults | Bounds, uniqueness, requested/effective separation, legacy fallback | Menu focus order, VoiceOver clarity, visual layout, cross-display resize feel |

The pattern is reusable: put computations behind explicit inputs, put mutable
transition ownership on the main actor, inject narrow window/registrar
protocols, and reserve WindowServer conclusions for manual evidence.

### Why preferred size is separate from effective frame

Suppose Wide requests 680×720 content, but the current display's visible area
cannot fit the corresponding outer frame. Throwing the request away would make
a temporary constraint permanent. Instead:

```text
requested preference: 680×720 content
        ↓ convert through frameRect(forContentRect:)
preferred outer frame around preserved edge anchor
        ↓ clamp to current visibleFrame
effective on-screen frame now
```

`PanelFramePlacement` carries the effective frame together with unchanged
preferred content size and anchor. The coordinator retains those logical values
across display changes. The size controller likewise stores the requested
working size after Apply, not the temporary effective content size. A completed
manual resize is different: it expresses a new user preference and replaces
the prior requested size.

### Autosave and preferences cooperate without breaking upgrades

There are three startup cases:

| Saved state | First-frame policy |
|---|---|
| No AppKit frame, no size preferences | Defer until show; use default Comfortable on pointer display, 24 points from visible top-right |
| AppKit frame exists, no size preferences | Keep legacy autosaved geometry, enforcing minimum and current-screen clamping |
| AppKit frame and explicit working size exist | Resolve the explicit content size around the autosaved location/edge and clamp temporarily if needed |

Returning `nil` for never-saved panel preferences is therefore intentional
compatibility behavior, not an absent default. Corrupt or unsupported stored
preferences are different: the store returns safe `.default` values.

### Transition invariants

The following invariants are more useful than memorizing individual methods:

1. `currentPage == nil` means neither stash nor size Apply may create a panel.
2. A visible full panel and visible handle are representations of one retained
   feature state, not two independent page windows.
3. Stash records the full panel frame before hiding it and never shrinks that
   frame to handle dimensions.
4. New representation first, old representation second: handle-present then
   panel-out; panel-present then handle-out.
5. Showing, replacing, reloading, applying size, and restoring all dismiss a
   stale handle.
6. Dragging the handle changes the active handle placement, not the saved full
   panel frame. A later new stash computes placement from the full panel again.
7. Page loading and presentation are separate: restore and resize may present
   without activating/reloading a page.
8. A missing screen result is not permission to hide the only visible
   representation.

### Failure and recovery paths

- **No page:** shortcut tap focuses page input; the status menu offers Settings;
  panel-size Apply is disabled while preset management remains available.
- **Stash placement unavailable:** `stash` returns `false`, leaving the full
  panel visible.
- **Dragged placement unavailable:** the handle returns to its previous frame.
- **Screen list temporarily empty while stashed:** the visible handle and its
  last placement remain until valid geometry returns.
- **Shortcut replacement fails:** the registrar attempts to restore the prior
  shortcut; runtime retains its published/stored value, reports health, and
  forces the menu-bar fallback visible when necessary.
- **Invalid size or name:** mutations occur on a copy and are committed only
  after validation and storage succeed; the controller publishes guidance.
- **Corrupt saved size data:** safe defaults replace invalid data; legacy
  absence remains distinct.

## Common misconceptions and failure modes

| Misconception | Correction | Start investigation at |
|---|---|---|
| “The PiP appears on every Space because `NSPanel` is broken.” | `.canJoinAllSpaces` is an intentional product policy on both PiP and handle. | `WindowRole.pictureInPicture` and `.stashHandle` |
| “Floating means the web editor automatically receives typing.” | Floating is a level. `canBecomeKey`, app activation, and `makeKeyAndOrderFront` establish the requested focus path. | `KeyCapablePiPPanel.present()` |
| “The handle should become key so clicks work.” | The nonactivating panel uses `acceptsFirstMouse`; restore should not steal focus merely because the tab is visible. | `PiPStashHandleInteractionView` |
| “Close destroys the PiP.” | `KeyCapablePiPPanel.close()` invokes the stash callback; the panel/page remain retained. | coordinator `panel.onClose` binding |
| “Stashing resizes the panel to 36×96.” | The full frame is saved unchanged; a separate handle panel receives that size. | `stash`, `PanelStashPolicy.handleSize`, geometry test |
| “Moving the handle moves the eventual full panel.” | Dragging updates handle placement for screen changes. Restore starts from the saved full-panel frame and preferred anchor. | `activeStashPlacement` versus `stashedPanelFrame` |
| “Any shortcut press immediately toggles.” | Press begins a 300 ms hold timer; release before it fires is a tap, while a hold peeks only from stashed state. | `handleGlobalShortcut` |
| “If the shortcut fails and the icon preference is off, the app is unreachable.” | Runtime temporarily forces effective icon visibility without overwriting the saved off preference. | `updateEffectiveMenuBarIconVisibility()` |
| “Selecting Wide as default resizes immediately.” | Setting the default persists only the selection. Apply Default or Reset performs the resize. | `PanelSizeController.setDefault` and `applyDefault` |
| “A small display should overwrite an oversized saved preset.” | Clamping is effective geometry; preferred requested dimensions and anchor remain for restoration. | `PanelFramePlacement` and controller clamp test |
| “AppKit frame autosave is obsolete now that presets exist.” | Missing preset data deliberately leaves legacy autosaved geometry authoritative. | `PanelSizePreferencesStore.load()` |
| “Unit tests prove Stage Manager, Spaces, and focus.” | They prove policy values and call order. Real WindowServer behavior is manual. | `docs/MANUAL_TEST_MATRIX.md` |

A particularly risky implementation mistake is merging pure geometry with
global `NSScreen` lookup inside the policy. That makes multi-display behavior
harder to test and obscures whether a failure is a rectangle decision or an
AppKit observation. Pass screen values into pure code, then make the coordinator
responsible for when to read AppKit state.

## Presenter notes

### Suggested 75-minute pacing

- **0–8 minutes:** open-notebook model; key versus visible; four layers.
- **8–18 minutes:** window roles, activation, collection behavior, and the
  all-Spaces product invariant.
- **18–30 minutes:** first placement, content/frame conversion, anchors,
  clamping, autosave compatibility, and corner snap.
- **30–42 minutes:** visible/stashed state machine and the stash-drag-restore
  trace.
- **42–51 minutes:** chrome, status item, menu fallback, and stale-command
  guards.
- **51–60 minutes:** Carbon tap/hold/peek behavior and failure recovery.
- **60–68 minutes:** built-in/custom sizes and requested-versus-effective state.
- **68–75 minutes:** test-boundary table, knowledge check, and exercise setup.

### Board plan

Draw four horizontal lanes: **pure values**, **main-actor coordinator**,
**AppKit**, and **SwiftUI/user**. Put `PanelFramePolicy` and `PanelStashPolicy`
in the first lane; `PiPPanelCoordinator`, runtime, and `PanelSizeController` in
the second; panel, handle, Carbon, and status item in the third; chrome and
settings in the fourth. Draw the stash trace vertically across the lanes.

Next draw two rectangles for state:

```text
[full retained panel + currentPage] ⇄ [same state represented by edge handle]
```

Do not draw the handle as a miniature copy of the web page. It is a second
AppKit representation controlling the same retained feature state.

### Source demonstration cues

1. Open `WindowRole.pictureInPicture` beside `.stashHandle`; ask which flags are
   shared and why only one can become key.
2. In `PiPPanelCoordinator` find `presentationState`, then follow the close
   callback into the same toggle used by the stash button.
3. In `stash`, point out `stashedPanelFrame`, handle-first ordering, lifecycle
   notification, and `orderOut`.
4. In `PiPStashHandleInteractionView`, compare a 2-point movement with a
   4-point movement and predict click versus drag.
5. In `PanelFramePolicy.placement`, circle the three outputs: frame, preferred
   content size, anchor.
6. In runtime shortcut handling, draw a press/release timeline at 299 ms and
   301 ms.
7. In `PanelSizeController`, compare `setDefault` with `apply`; then show where
   only end-of-live-resize persists a manual working size.
8. End with the pure/AppKit evidence table and the manual matrix, not with a
   claim based only on seeing collection flags.

### Safe live demonstration

Before a live demo, save work and quit any running Notion PiP before rebuilding;
the build script terminates existing `NotionPiP` processes. Use a non-sensitive
page in the user's own signed-in Notion session. Never request a password,
session cookie, or integration token.

If using the staged app, label the following as observations rather than unit
test conclusions: key focus, keyboard editing, Space/full-screen movement,
Mission Control exclusion, Command-` exclusion, Stage Manager, Dock avoidance,
monitor unplug/reconnect, Carbon delivery, VoiceOver, and WebView selection
retention. Record them against
[`MANUAL_TEST_MATRIX.md`](../MANUAL_TEST_MATRIX.md).

Because the working tree may include uncommitted stash animation changes, a
live build from that tree may not match the committed trace taught here. Either
demo a known committed build or state the difference explicitly. Do not present
uncommitted entrance/exit motion as established `HEAD` behavior.

## Knowledge check

1. Why does the main PiP subclass `NSPanel` yet override `canBecomeKey`?
2. Why is the stash handle a nonactivating panel?
3. Which collection behavior expresses intentional persistent all-Spaces
   overlay behavior?
4. What is the difference between `frame` and `visibleFrame` during first-use
   placement?
5. Why does `PanelFramePlacement` retain preferred content size separately from
   its effective frame?
6. Does dragging the stash handle rewrite the saved full-panel frame?
7. What happens on shortcut tap with no current page?
8. What happens when Command-Shift-P is held while the panel is stashed, and
   what happens if it is already visible?
9. Why can a hidden menu-bar preference still result in a visible icon?
10. Does changing the default panel-size preset resize the current panel?
11. Name two behaviors that automated policy/coordinator tests establish and
    two that require manual WindowServer verification.

### Answers

1. `NSPanel` supplies the auxiliary overlay role, while the override allows the
   hosted Notion editor to become the key typing surface when presented.
2. The handle should remain a passive all-Spaces restore affordance rather than
   taking keyboard focus merely by appearing. Its interaction view accepts the
   first mouse and exposes accessible button activation.
3. `.canJoinAllSpaces`; it is combined here with `.fullScreenAuxiliary`,
   `.transient`, and `.ignoresCycle` for the complete requested overlay role.
4. Full `frame` identifies the pointer's display even in its menu-bar area.
   `visibleFrame` supplies usable placement bounds that avoid menu bar and Dock.
5. A small display may force a temporary clamp. Keeping the request and anchor
   lets a later larger display restore intended size and edge relationship.
6. No. It updates active handle placement. `stashedPanelFrame` remains the
   logical full-panel restoration frame.
7. The tap cannot toggle a page, so runtime presents and focuses page URL input.
8. After the hold threshold, a stashed panel is restored as a peek and stashed
   again on release. A panel that was already visible remains visible.
9. A global shortcut registration failure forces **effective** icon visibility
   as a recovery route while preserving the saved off preference.
10. No. It changes the stored default only. Apply Default or Reset to Default
    Size performs a resize.
11. Automated examples: exact edge/clamp rectangle, tap/hold state transition,
    handle-before-panel call order, or no repeated page activation. Manual
    examples: actual key focus, cross-Space visibility, Stage Manager,
    Mission Control, Carbon conflicts, keyboard editing, or VoiceOver output.

## Hands-on exercise

### Exercise: classify and predict three changes

Without editing source, analyze these scenarios. For each, name the owning
layer, predicted call/state sequence, best automated regression, and remaining
manual check.

1. **Edge rule:** Product asks that a panel exactly centered on its display
   stash to the right instead of the left.
2. **Small display:** A user applies a custom 900×1000 preset while stashed on a
   display whose visible area is 800×600, then moves to a larger display.
3. **Recovery:** The user saved the menu-bar icon as hidden. On launch, the
   panel shortcut conflicts with another app; no page is currently pinned.

Use focused searches against committed source:

```sh
git grep -n "midX <=\|snappedPlacement" HEAD -- \
  Sources/NotionPiP/Platform Tests/NotionPiPTests
git grep -n "preferredWorkingContentSize\|lastExplicitWorkingContentSize" HEAD -- \
  Sources/NotionPiP Tests/NotionPiPTests
git grep -n "globalShortcutUnavailable\|effectiveMenuBarIconVisibility" HEAD -- \
  Sources/NotionPiP Tests/NotionPiPTests
```

Do not modify display settings or deliberately break a system-wide shortcut
during this source exercise.

### Expected answers and observations

**1. Edge rule**

- Owner: pure `PanelStashPolicy`, specifically the side comparison in
  `placement`; consider whether `snappedPlacement` should use the same rule.
- Current prediction: exact center uses left because the comparison is `<=`.
- Focused test: add exact-center cases to `PanelStashPolicyTests` for both full
  panel and dragged handle if the product rule covers both.
- Implementation effect: changing `<=` to `<` would select right at equality;
  no AppKit window mutation belongs in the policy.
- Manual remainder: confirm the chosen rule feels consistent at a real
  multi-display boundary and that the rendered side-specific tab shape is
  correct.

**2. Small display**

```text
PanelSizeController.apply(custom ID)
  → resolve requested content 900×1000
  → PiPPanelCoordinator.applyPanelContentSize
  → preferredWorkingContentSize = request
  → PanelFramePolicy.placement converts and clamps to visible space
  → panel frame changes; stashed frame clears; handle orders out
  → retained panel presents; panelDidShow; no page activate/reload
  → controller stores requested 900×1000 working size

larger display becomes target
  → reclampPanelFrame
  → preserved preferred size and anchor resolve to full requested frame
```

The value/controller/coordinator seams already suggest regression locations in
`PanelFramePolicyTests`, `PanelSizeControllerTests`, and `PinCoordinatorTests`.
Manual checks remain actual title-bar conversion, visual anchor preservation,
focus, editing, and selection survival on physical displays.

**3. Recovery**

```text
AppRuntime.start
  → register Command-Shift-P
  → registrar throws
  → report .globalShortcutUnavailable
  → saved icon visibility remains false
  → effective icon visibility becomes true and forced = true
  → StatusItemController observes and shows icon
  → no page means first menu command is Open Settings…
```

The strongest automated seam is a fake failing registrar plus isolated
`MenuBarIconPreferenceStore`, as in
`RuntimeActivationAndMenuBarTests`. The manual remainder is whether the real
status item appears, its menu opens, the conflict behaves as expected, and a
successful retry removes the override while keeping the saved preference off.

## Recap

- The main PiP is a retained, floating, key-capable `NSPanel`; the edge handle
  is a retained, floating, nonactivating `NSPanel`.
- Both request all-Spaces/full-screen overlay behavior intentionally. That
  persistence is product policy, not an `NSPanel` defect.
- Full presentation activates the app and requests key focus. Handle
  presentation stays passive but accepts first mouse and accessible press.
- Pure `PanelFramePolicy` and `PanelStashPolicy` decide rectangles from explicit
  inputs; main-actor coordinators decide when to read AppKit state and perform
  transitions.
- First-use placement is deferred to the pointer's display and uses a 24-point
  visible-frame inset. Legacy autosaved geometry remains authoritative when no
  size preferences have ever been saved.
- Preferred content size and anchor survive temporary clamping. A completed
  manual resize deliberately replaces that preference.
- Stashing saves the full frame, presents a separate 36×96 edge handle, reports
  the web lifecycle hide, and orders out the full panel without reloading or
  releasing the current page.
- The handle's 3-point threshold distinguishes restore clicks from drags; drag
  completion snaps the handle to a valid display edge.
- Command-Shift-P taps toggle, holds temporarily peek only from stashed state,
  and no-page taps focus page input. Command-Shift-N independently opens Quick
  Capture.
- The status menu derives Open Settings/Stash/Show from presentation state. A
  shortcut failure can force the menu-bar icon visible without changing the
  user's saved preference.
- Compact, adaptive Comfortable, Wide, and validated custom sizes share one
  value model and controller across Settings, panel, and status menus. Choosing
  a default is intentionally separate from applying it.
- Automated tests prove value rules, configured flags, and coordinator call
  order. Spaces, Stage Manager, Mission Control, focus, Carbon delivery,
  accessibility output, and real retained editing remain explicit manual
  boundaries.

Next, Lecture 6 in the [course navigation](README.md#course-navigation) follows
the one shared `NotionWebSession` inside this retained presentation shell and
explains navigation, interaction snapshots, restoration, and WebKit lifecycle.
