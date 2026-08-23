# Drag-to-Stash Design

## Goal

Allow a user to drag the visible Perch panel sufficiently beyond a true left or right display edge and stash it by releasing the drag. The established stash handle remains visible and restores the panel through the existing interaction.

## Interaction

- Stashing commits only after the primary mouse button is released or a trackpad move ends.
- The threshold is 40% of the panel width beyond the display's visible left or right edge.
- Pulling back before release cancels the candidate.
- Top and bottom edges never trigger stashing.
- A boundary shared with an adjacent display is not a stash edge.
- The stash handle is vertically centered on the released panel and clamped around system UI.
- Restoring returns the panel fully on-screen at the corresponding edge.

## Architecture

`PanelStashPolicy` owns the pure geometry decision and returns a `PanelDragStashDecision` containing the stash placement and the fully visible restore frame. `PiPPanelCoordinator` evaluates that decision from the same deferred move-completion path that currently performs corner snapping. A successful decision bypasses corner snap, persists the restore frame, and invokes the existing coordinated stash transition.

This avoids global event taps and custom drag gestures. Native AppKit panel movement, trackpad movement, stash animation, page lifecycle, and the edge handle remain unchanged.

## Alternatives considered

1. Observe global mouse-up events. This is more direct but introduces event-monitor lifetime and permission complexity.
2. Replace native movement with a SwiftUI drag gesture. This would duplicate AppKit window behavior and interfere with the existing top-edge trackpad controller.
3. Extend the existing move-completion scheduler. This is selected because it already waits for both mouse and trackpad movement to finish and is independently testable.

## Release

The behavior ships as version `0.1.1` with an incremented build number. Before tagging, the feature tests, complete Swift suite, script tests, bundle validation, and a local `0.1.0` to `0.1.1` Sparkle upgrade must pass. The release tag is created only after the working tree and release prerequisites are reviewed.
