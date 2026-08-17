# PiP Trackpad Move Design

## Goal

Let someone reposition the visible Perch PiP with a two-finger trackpad
gesture while the pointer is over its top controls area. The gesture works
over both the visible 36-point toolbar and the hidden 16-point reveal strip,
without changing scrolling inside the Notion page.

## Interaction

- Existing native click-drag window movement remains available.
- A precise two-finger scroll gesture may begin anywhere in the top 36 points
  of the PiP content. This includes the hidden reveal strip and the entire
  visible toolbar.
- Once a qualifying gesture begins, the PiP consumes that gesture until its
  ended or cancelled phase, including stationary events, even if the moving
  panel changes the event's local pointer position.
- Horizontal and vertical scrolling deltas move the panel in both axes and
  honor the user's macOS scrolling-direction preference.
- The panel stops when the physical gesture ends. Momentum events are consumed
  but never move the panel or leak into the Notion web view.
- Mouse-wheel events and scroll events outside the top region retain their
  existing behavior.
- A zoomed or full-screen PiP does not respond to the move gesture.
- The panel remains reachable on the display where the gesture began. Native
  click-dragging remains the way to move Perch between displays.
- Existing delayed corner snapping runs after gesture movement stops.

## Architecture

Add a focused `TopEdgeTrackpadMoveController` in the platform layer. It owns a
small gesture state machine and accepts value-type inputs describing event
phase, momentum phase, precision, pointer position, content bounds, panel
state, content coordinate orientation, and scrolling delta. It returns one of
three decisions: forward the event, consume it without moving, or consume it
and move by a translation.
This isolates gesture qualification and momentum suppression from AppKit event
construction.

`KeyCapablePiPPanel.sendEvent(_:)` remains the single AppKit integration point.
For scroll-wheel events it converts `NSEvent` fields into the controller input,
applies accepted translations to the current frame, and constrains the result
to the visible frame of the display captured when the gesture begins. Other
events continue through `super.sendEvent(_:)`. Moving the actual panel already
posts `NSWindow.didMoveNotification`, so `PiPPanelCoordinator` continues to own
geometry persistence, panel-position state, snap-target presentation, and
corner snapping without a parallel code path. The panel exposes whether the
trackpad gesture remains active so the coordinator defers its existing delayed
snap until the physical gesture ends.

`PiPChromeView.topControlsHeight` uses the controller's shared 36-point active
height so the rendered toolbar and the panel-level gesture zone cannot drift.
No transparent SwiftUI gesture layer or application-wide event monitor is
added; toolbar buttons therefore retain normal hit testing and event handling.

## Reachability and Failure Behavior

The gesture captures the panel's current display when its began event is
accepted. Every proposed frame is clamped inside that display's visible frame,
which prevents trackpad motion from pushing the PiP behind the menu bar, Dock,
or completely offscreen. If no screen can be resolved at gesture start, the
event is forwarded and no gesture state is retained.

Ended and cancelled events clear active movement. Momentum is suppressed until
its own ended or cancelled phase, after which unrelated scrolling is forwarded
normally. Stationary and zero-delta gesture events are consumed while active
but do not issue redundant frame changes. Ordering the panel out resets an
interrupted gesture so stale activity cannot affect a later presentation.

## Testing

Deterministic controller tests cover:

- starting in the hidden 16-point strip and elsewhere in the 36-point toolbar;
- rejecting the exact lower boundary and ordinary Notion content;
- rejecting non-precise mouse-wheel input and expanded panels;
- latching an accepted gesture through changed and ended phases;
- consuming zero-delta events without moving;
- suppressing every momentum phase and resetting afterward;
- forwarding unrelated scroll input after reset.

AppKit-facing tests cover translation of a real panel in both axes, clamping to
the starting display, and retaining existing event behavior when the gesture
is rejected. The full Swift test suite remains the release gate:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Manual verification uses a trackpad with the pointer first over the hidden top
strip and then over visible toolbar controls. It confirms direct two-axis
movement, immediate stopping, normal button clicks, unchanged Notion scrolling,
reachability at display edges, and existing corner snapping.
