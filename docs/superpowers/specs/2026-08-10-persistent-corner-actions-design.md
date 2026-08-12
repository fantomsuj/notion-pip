# Persistent Corner Actions

## Goal

Give the user permanent, one-click controls for moving Perch to any corner
of its current display without keeping every toolbar action permanently visible.

## Selected Interaction

A lightweight, compact toolbar remains visible at the panel's top-left, above
the Notion web content. Its four persistent buttons appear in this order:

```text
[ top left ][ top right ][ bottom left ][ bottom right ]
```

Each button uses the matching directional SF Symbol and moves the panel
immediately: `arrow.up.left`, `arrow.up.right`, `arrow.down.left`, and
`arrow.down.right`. The control does not open a menu or popover.

Hovering the compact toolbar or resting the pointer at the top edge expands that
same toolbar. The corner buttons stay fixed while the existing new-page, page
switcher, reload, open-in-Notion, app-menu, and stash actions appear directly to
their right.

The toolbar uses one compact material background, separators, and semantic
colors. It remains fully visible in its lightweight state rather than fading
when idle. Each button has a normal pointer hit target of at least 24 by 24
points, help text, and an explicit accessibility label such as **Move Perch
to top left**.

## Positioning Behavior

- The target display is the display containing the largest portion of the panel,
  falling back to the nearest display when the panel does not intersect one.
- The action preserves the user's desired panel size.
- The target frame uses the display's visible frame, so it avoids the menu bar,
  Dock, and other system-reserved areas.
- Each edge uses the existing 24-point corner inset.
- If the panel is too large for the display, only the effective frame is reduced.
  The desired content size remains saved and can be restored on a larger display.
- The move animates through the panel's existing programmatic-frame path. Reduce
  Motion disables the animation.
- The selected corner receives a subtle selected state. If the user drags the
  panel away from an explicit corner, no button is selected.
- The explicit corner becomes the committed geometry anchor. Relaunching,
  resizing, stashing and restoring, or changing display topology preserves that
  corner relationship through the existing geometry store.
- If the PiP is stashed, the toolbar is not visible. Restoring the PiP retains
  the previously committed corner.

## Architecture

### Corner model and policy

Introduce a small `PanelCorner` value with four cases. It maps each user-facing
corner to the existing horizontal and vertical `PanelFrameAnchor` edges.

Extend the pure frame policy with an explicit-corner operation. Unlike the
current proximity-based `cornerSnapped` operation, this operation always returns
a frame at the requested corner. It reuses the existing target-display
selection, preferred-size fitting, 24-point inset, and anchor calculations.

A pure corner-detection operation reports a selected corner only when both frame
edges match the explicit 24-point anchor within a one-point geometry tolerance.
It therefore clears selection after a free move while remaining stable across
fractional AppKit coordinates.

### Position controller

Add a main-actor `PanelPositionController`, following the existing
`PanelSizeController` binding pattern. It exposes:

- the currently selected corner;
- whether positioning is available; and
- `move(to:)` for the four user actions.

The controller binds to a narrow `PanelPositioning` protocol implemented by
`PiPPanelCoordinator`. Coordinator callbacks refresh the selected corner after
an explicit move, completed manual move, resize, restore, or display-topology
change. The controller contains no AppKit window logic.

`AppComposition` creates one controller and passes it into the retained panel
coordinator. This keeps the position state shared by the AppKit owner and its
SwiftUI content without routing window geometry through `AppRuntime`.

### Panel coordinator

`PiPPanelCoordinator.movePanel(to:)`:

1. resolves the current display from the live panel frame;
2. resolves the desired size from committed geometry;
3. calculates the requested corner frame and anchor;
4. applies the frame through the existing guarded programmatic-frame path;
5. commits the geometry atomically; and
6. publishes the resulting selected corner.

The AppKit panel's animated frame setter checks
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` before creating an
animation context. This applies the same motion policy to the new explicit moves
and the existing automatic corner snap.

If there is no pinned page or no display can be resolved, the operation is a
no-op and positioning remains disabled. A geometry persistence failure uses the
existing failure callback; the in-memory move remains usable.

### SwiftUI chrome

Extract the four controls into a focused `PanelCornerControls` view. It renders
the direct buttons from `PanelCorner` without independent container chrome,
applies selected styling, and sends intent only to `PanelPositionController`.

`PiPChromeView` owns one leading-aligned material toolbar with three presentation
states: hidden when no position controller or revealed actions are available,
compact with the corner controls only, and expanded with the existing actions
appended on the right. The shared hover controller retains the existing delayed
reveal and dismissal behavior. The overlay continues to reserve no content
height, and its intrinsic width prevents it from covering the rest of the top
edge.

## Accessibility and Motion

- Buttons use unambiguous labels for all four destinations and matching help
  text.
- The selected corner is exposed as selected accessibility state, not only as a
  color change.
- Full Keyboard Access, VoiceOver, and Switch Control continue to keep the rest
  of the top controls available under the existing policy.
- With Reduce Motion enabled, the requested frame is applied without animation.
- Hit targets remain large enough for reliable pointer use even though the SF
  Symbols are visually compact.

## Testing

Pure geometry tests cover all four corner frames, 24-point insets, multi-display
selection, oversized-panel fitting, and fractional-coordinate corner detection.

Coordinator tests cover:

- one direct move to each corner;
- preserving desired content size;
- committing the requested anchor;
- selected-corner updates after explicit and manual moves;
- retaining the corner across resize, stash/restore, and display changes;
- no-screen and no-pinned-page no-ops;
- persistence failure without losing the in-memory frame; and
- Reduce Motion choosing the nonanimated frame path.

Controller and chrome tests cover action routing, enabled state, selected state,
stable button order, accessibility copy, compact and expanded toolbar states,
and unchanged delayed reveal/dismissal of the existing toolbar actions.

Validation uses:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./script/build_and_run.sh --verify
```

The manual check exercises every corner on each connected display, narrow and
wide panel sizes, keyboard and assistive access, Reduce Motion, dragging away
from a selected corner, stashing and restoring, and reconnecting a display.

## Out of Scope

- A popover, submenu, or second click before moving.
- Dedicated global shortcuts for the four corners.
- Moving the panel to a different display as part of a corner action.
- Center, edge-center, tiling, or percentage-based placements.
- User-configurable inset or toolbar location.
- Making the rest of the hover toolbar permanently visible.
