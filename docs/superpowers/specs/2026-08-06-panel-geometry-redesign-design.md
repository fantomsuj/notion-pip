# Panel Geometry Redesign

## Goal

Make the PiP panel's last completed user resize and move the single authority for
its geometry. Stashing and restoring must preserve the exact width, height, and
placement the user chose. Horizontal and Vertical provide intentional starting
shapes without competing with remembered geometry.

## Root Cause

The current coordinator maintains several independent geometry values:

- AppKit's autosaved window frame
- `preferredWorkingContentSize`
- `preservedFrameAnchor`
- `preferredVisibleFrame`
- `stashedPanelFrame`
- the persisted `lastExplicitWorkingContentSize`

Stashing captures the exact panel frame, but restoring does not restore that
frame. It calls `preferredPlacement`, which rebuilds a new frame from the
separate preferred content size and anchor. If those values differ from the
panel frame, a wide panel can reopen using a stale narrow width. The real-AppKit
geometry test covers stash but not the restore transition, so this regression is
not currently protected.

## User-Facing Behavior

- The most recent completed resize or move is remembered.
- Stash changes presentation only. It never changes geometry.
- Restore uses the exact remembered frame when its display is still available.
- Horizontal applies a 760 × 520 point content size.
- Vertical applies a 480 × 720 point content size and is the first-run fallback.
- Applying either built-in size preserves the nearest panel edges and commits the
  result as the new remembered geometry.
- Custom presets remain available. Applying one follows the same commit path.
- Compact, Comfortable, and Wide are replaced by Horizontal and Vertical.
- Presets do not automatically override remembered geometry at launch.
- Reset applies Vertical explicitly.

## Architecture

### Unified geometry value

Introduce a Codable `PanelGeometry` value containing:

- desired content size
- exact last visible frame
- the visible frame of the display on which it was committed
- the nearest horizontal and vertical edge anchor

This is one coherent snapshot, written atomically. The panel coordinator owns
the current value in memory. A `PanelGeometryStore` persists it in
`UserDefaults`.

### Geometry policy

`PanelGeometryPolicy` is a pure calculation boundary. It:

- captures a geometry snapshot from a panel frame and current screens
- resolves the exact frame when the saved display is still present
- resolves from the saved anchor and desired size when displays change
- clamps only the effective frame when the desired size cannot fit
- retains the desired content size so reconnecting a larger display can restore
  it

The policy has no AppKit window ownership and is testable with Core Graphics
values and injected content/frame conversion closures.

### Coordinator flow

`PiPPanelCoordinator` remains the owner of the retained `NSPanel`, but delegates
geometry decisions to the unified snapshot and policy.

- First presentation loads the unified snapshot. If none exists, it performs a
  one-time legacy migration or uses Vertical.
- `NSWindow.didEndLiveResizeNotification` commits the exact current geometry.
- completed moves commit the exact current geometry after corner snapping has
  settled
- applying a preset resolves a new size at the current anchor, sets the frame,
  and commits the resulting geometry
- stash commits once, presents the handle, and hides the panel
- restore resolves the saved geometry and presents the panel
- screen changes resolve the saved geometry without overwriting its desired size

The stashed state stores no independent frame. It contains only presentation
state and handle placement.

### Animation ordering

Stash animation receives a transition generation. Restoring or starting another
transition invalidates the previous generation. A stale animation completion
cannot order out, move, or reset the frame of a panel that has already been
restored.

### AppKit boundary

AppKit remains responsible for the actual `NSPanel`, content/frame conversion,
window notifications, and animation. Swift value types own geometry state.
AppKit frame autosave is read only during migration and is no longer a runtime
source of truth after unified geometry is saved.

## Persistence And Migration

The unified store uses a versioned Codable payload.

On the first launch without unified geometry:

1. Read the legacy AppKit autosaved frame if one was restored.
2. Use the legacy last explicit content size when valid; otherwise derive content
   size from the restored frame.
3. Capture the corresponding display and anchor.
4. Persist the unified geometry.
5. Stop reading the legacy values during normal operation.

Custom presets are retained. Legacy built-in default identifiers map as follows
when decoding existing preferences:

- Compact and Comfortable map to Vertical.
- Wide maps to Horizontal.

Corrupt, unsupported, non-finite, undersized, or oversized geometry falls back
to Vertical on the current pointer display. A persistence failure keeps the
in-memory geometry usable and reports through the existing panel-size validation
message rather than preventing panel presentation.

## Display Changes

The policy first matches the committed display's visible frame. If it still
exists, the exact saved frame is restored. If it does not, the policy chooses the
display with the largest intersection or nearest center and reconstructs the
frame from the saved desired size and edge anchor.

If the desired size cannot fit, only the visible frame is clamped. The stored
desired size is not replaced. Reconnecting a suitable display can therefore
restore the user's original dimensions.

## Testing

Tests will protect these user-visible contracts:

- a manually sized horizontal panel restores to the exact same frame
- a manually sized vertical panel restores to the exact same frame
- the real AppKit panel keeps its exact width through stash and restore
- a stale preferred or legacy size cannot override the committed frame
- Horizontal and Vertical preserve the nearest edges and become remembered
- custom preset application becomes remembered geometry
- a disconnected small display clamps without losing desired size
- reconnecting a suitable display restores desired size and anchor
- rapid restore invalidates a pending stash completion
- legacy preferences and AppKit autosave migrate once
- corrupt unified geometry falls back to Vertical

Validation uses:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The staged app will also be launched with:

```sh
./script/build_and_run.sh --verify
```

The manual check resizes the panel horizontally, stashes it, restores it from the
edge handle, repeats vertically, and confirms both exact frames are retained.

## Constraints

- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Keep the PiP's retained, floating, all-Spaces `NSPanel` behavior.
- Keep changes focused on sizing, geometry persistence, and stash ordering.
- Do not require Node.js, secrets, a Notion token, or signing certificates.
