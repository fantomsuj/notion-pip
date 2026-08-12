# Draggable Edge Stash Design

## Goal

Let someone reposition the stashed Perch by dragging its edge tab. A click still restores the live PiP; a drag moves the tab freely and, on release, snaps it to the nearest horizontal edge while keeping the chosen vertical position.

## Research and Rationale

Apple documents `NSWindow.performDrag(with:)` as the supported way for a view to hand a window drag to the Window Server, allowing the move to participate in Spaces and other system behaviors. Apple also warns that the method returns immediately and the view may not receive mouse-up. AppKit exposes `didMoveNotification`, but not an end-live-move notification. Existing macOS applications such as OpenClaw and iTerm2 use small AppKit interaction views for draggable surfaces; OpenClaw additionally separates a click from a drag with a short movement threshold.

Three approaches were considered:

1. Set `isMovableByWindowBackground` on the existing handle panel. This is small, but the full-size SwiftUI button consumes pointer events and makes click-to-restore versus drag behavior ambiguous.
2. Implement the move entirely with a SwiftUI `DragGesture`. This offers direct gesture state, but manually moving the panel bypasses the Window Server's native window-drag behavior and requires more coordinate and Spaces handling.
3. Add a narrow AppKit interaction surface that distinguishes click from drag, moves the small handle panel from global pointer deltas, and snaps through the existing pure geometry policy on mouse-up. This is the selected approach because it makes drag completion reliable, keeps the SwiftUI view presentational, and leaves both interaction state and placement math independently testable. The handle panel already joins all Spaces, so moving it directly does not change its cross-Space availability.

References:

- [Apple: `NSWindow.performDrag(with:)`](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:))
- [Apple: `NSWindow.didMoveNotification`](https://developer.apple.com/documentation/appkit/nswindow/didMoveNotification)
- [OpenClaw `TalkOverlayView.swift`](https://github.com/openclaw/openclaw/blob/5419a945875ba90fcbddd84a3b50866fd64716a8/apps/macos/Sources/OpenClaw/TalkOverlayView.swift)
- [iTerm2 `DraggableNSBox.swift`](https://github.com/gnachman/iTerm2/blob/a8eb089a227ee47dd0d0974e1592893667bad737/sources/TIps/DraggableNSBox.swift)

## Interaction

- `Command-Shift-P` continues to stash a visible PiP and restore a stashed PiP.
- Clicking the 36-by-96-point edge tab without crossing the drag threshold restores the same live PiP.
- Dragging at least 3 points begins a native window drag and does not restore the PiP.
- During the drag, the tab may move freely across the current display or onto another display.
- When the live move ends, the tab snaps to the nearest left or right edge of the display containing most of it.
- The snapped tab preserves its dropped vertical origin, clamped fully inside that display's visible frame.
- Dragging does not move, resize, show, reload, or navigate the retained main panel.
- The latest snapped placement lasts for the current stashed session. It is not persisted across app relaunches or a later stash operation.

## Architecture

`PanelStashPolicy` gains a second pure geometry entry point for a dragged handle frame. It resolves the target display with the existing `PanelFramePolicy`, selects the nearest horizontal edge from the handle center, preserves the handle's current vertical origin, and clamps it inside the visible frame. The existing initial stash placement remains centered on the retained main panel.

`PiPStashHandleView` remains responsible for appearance. Its button is replaced by a transparent `NSViewRepresentable` interaction surface that owns the same accessibility action. The AppKit view records the initial global pointer position and panel origin, treats movement below 3 points as a click, moves a qualifying drag by pointer delta, and reports the final frame on mouse-up.

`PiPStashHandleController` receives the final dragged frame from the interaction surface. It asks `PanelStashPolicy` for the snapped placement, applies the resulting frame, rebuilds the side-dependent SwiftUI shape when the side changes, and reports the new placement through a callback.

`PiPPanelCoordinator` stores the active `PanelStashPlacement` while stashed. Initial stashing sets it, drag callbacks update it, and restore/hide clears it. Screen-configuration changes re-place the handle from this stored handle frame rather than the hidden main panel frame, preserving the user's chosen side and height whenever that placement remains valid.

## Accessibility and Feedback

- The tab retains the accessibility label **Restore Perch** and hint **Bring the stashed Perch back from the side.**
- The whole visible tab remains the pointer and accessibility target.
- The help text becomes **Drag to move; click to restore Perch** so the new behavior is discoverable without adding permanent chrome.
- No animation is added; the tab follows the system drag and snaps immediately on release.

## Edge Cases

- A movement shorter than 3 points remains a restore click.
- A completed drag with no resolvable visible display returns the handle to its last valid placement instead of leaving it unreachable.
- Crossing displays uses the display with the largest handle intersection; a handle between displays falls back to the nearest display center through the existing target-frame policy.
- Vertical drops above the menu bar or below the Dock are clamped to `NSScreen.visibleFrame`.
- Screen changes while stashed retain the last tab placement as the geometry source and dismiss the tab only if no visible display remains.
- Repeated move callbacks update placement without activating the accessory app or the hidden main PiP.

## Testing

- Unit tests cover left/right snapping, vertical preservation and clamping, multi-display selection, and no-screen behavior.
- Coordinator tests cover remembering a moved placement, using it after a screen change, and clearing it on restore/hide without reloading the page.
- AppKit interaction tests cover click activation below the threshold and panel movement above it without firing restore.
- The full Swift suite, web suite, TypeScript typecheck, and packaged app verification build must pass.

## Out of Scope

- Persisting tab placement across relaunches.
- Moving or resizing the hidden main PiP to match the tab.
- Throw velocity, spring animations, or magnetic corner zones.
- Changing the `Command-Shift-P` shortcut or menu-bar behavior.
