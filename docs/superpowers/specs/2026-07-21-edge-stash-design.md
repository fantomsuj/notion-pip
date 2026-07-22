# Edge Stash Design

## Goal

Let someone temporarily tuck the Notion PiP out of the way without closing it, losing the pinned page, or disturbing the panel's saved size and position. A compact tab at the nearest horizontal screen edge restores the live PiP with one click.

## Research and Rationale

Apple's iPad Picture in Picture supports dragging a video off the left or right edge while retaining an onscreen recovery affordance. Apple's macOS Picture in Picture keeps the floating player positioned across desktop Spaces. Arc's Mini Player similarly treats the player as a movable, resizable surface whose controls stay attached to the media rather than opening a separate workflow.

Three implementation approaches were considered:

1. Shrink the Notion panel into a narrow strip. This is simple, but it forces the live WebView through an unusably small layout and changes the panel's saved geometry.
2. Move most of the Notion panel offscreen. This resembles iPad PiP, but conflicts with the app's frame-clamping and frame-autosave behavior and leaves the recovery target dependent on clipped window content.
3. Hide the Notion panel and show a dedicated edge tab. This preserves the WebView, panel geometry, and session exactly while providing a reliable recovery target. This is the selected approach.

References:

- [Apple iPad User Guide: Multitask with Picture in Picture](https://support.apple.com/guide/ipad/multitask-with-picture-in-picture-ipad7858c392/ipados)
- [Apple Safari User Guide: Play web videos](https://support.apple.com/guide/safari/play-web-videos-ibrw27291639/mac)
- [Arc Help Center: Mini Player](https://resources.arc.net/hc/en-us/articles/19234766331799-Picture-in-Picture-Watch-Videos-as-you-Browse)

## Interaction

- Add a toolbar button with the accessibility label **Stash Notion PiP to Side** and help text explaining that it moves the PiP to the nearest edge.
- Activating the button hides the main panel and shows a 36-by-96-point edge tab.
- Choose the left or right edge by comparing the panel center with the center of the screen containing most of the panel.
- Vertically align the edge tab with the panel center, clamped fully inside the screen's visible frame.
- The tab uses a chevron pointing back toward the screen. Activating it restores and focuses the same panel.
- Pressing `Command-Shift-P` while the full PiP is visible stashes it; pressing the shortcut while the PiP is stashed or otherwise hidden restores it.
- Showing or replacing a page by any existing path dismisses the edge tab first.
- The menu-bar click restores a stashed PiP because the main panel is hidden and its existing show path dismisses the tab before presenting the panel. Its visible-panel behavior remains hide rather than stash.
- Explicitly hiding the PiP dismisses both the main panel and any edge tab.

## Architecture

`PanelStashPolicy` is a pure geometry component. It selects a visible screen, chooses the nearest horizontal edge, and returns the edge-tab frame. It has no AppKit window dependency and is covered by unit tests.

`PiPStashHandleController` is the narrow AppKit bridge. It owns one borderless, nonactivating floating `NSPanel`, hosts a small SwiftUI `PiPStashHandleView`, and exposes only `present`, `orderOut`, and `isVisible` through a protocol.

`PiPPanelCoordinator` orchestrates the two windows. Stashing never moves or resizes the main panel: the coordinator orders it out and presents the handle. Restoring, showing, replacing, or hiding first removes the handle so there can never be two active representations. Screen-configuration changes continue to clamp the retained main frame and recompute a visible handle placement when currently stashed.

`PiPChromeView` receives a narrow `onStash` callback beside its existing `onHide` callback. It does not own window state.

## Visual Treatment and Accessibility

- Use a system material, shadow, semantic foreground styles, and SF Symbols so the tab adapts to appearance and accessibility settings.
- Keep the outer edge flush with the screen and round only the inward-facing corners, preserving the physical impression that the panel is tucked behind the edge.
- The restore control has the accessibility label **Restore Notion PiP** and help text **Bring the stashed Notion PiP back from the side.**
- Do not add motion that requires a Reduce Motion alternative. The panel and tab exchange visibility immediately.
- Keep the tab large enough for a comfortable pointer target while consuming little screen space.

## Edge Cases

- If no visible screen can be resolved, stashing is a no-op and the main panel remains visible.
- If the shortcut cannot resolve a stash placement, it falls back to the previous hide behavior rather than opening URL entry or doing nothing.
- If the panel straddles displays, use the display with the largest intersection. If there is no intersection, use the nearest display center, matching the existing clamp policy.
- If screen geometry changes while stashed, clamp the retained main panel frame and reposition the tab. If no display remains available, dismiss the tab rather than strand an unreachable control.
- Stashing does not clear `currentPage`, call the page loader, navigate the WebView, or rewrite the autosaved panel frame.
- The tab joins all Spaces and stays at floating level, matching the main PiP.

## Testing

Unit tests cover left/right selection, multi-display selection, vertical clamping, no-screen behavior, stashing without page reload, restoring the same panel, normal show/hide cleanup, handle repositioning after screen changes, shortcut-driven stash/restore, and unchanged menu-bar toggling.

The full Swift and web test suites, TypeScript typecheck, and app verification build must pass before commit.

## Out of Scope

- Drag-to-stash gestures or velocity-based throwing.
- A configurable preferred edge.
- Persisting the stashed state across relaunches.
- Multiple simultaneous PiP panels.
