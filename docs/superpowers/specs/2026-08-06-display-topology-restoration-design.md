# Display Topology Restoration Hardening

## Goal

Keep the single retained Notion PiP panel, its live WebView, and its optional
stash handle reachable while the set, identity, scale, and arrangement of
displays changes. Preserve the user's meaningful floating size and screen-edge
intent without revisiting the panel sizing design shipped on `origin/master`.

## Existing Behavior And Gaps

The current unified `PanelGeometry` correctly separates the desired content
size from a temporarily clamped effective frame. It also preserves an edge
anchor and avoids reloading the retained WebView during stash and restore.

Display changes are still represented only as `[CGRect]` visible frames. This
leaves four gaps:

- the policy cannot distinguish the same display after rearrangement from a
  replacement display at the old coordinates;
- identifier and backing-scale changes have no explicit model;
- the AppKit notification closure bypasses the injected test provider and
  enqueues unsequenced work that cannot reject stale delivery; and
- visible, stashed, expanded, and otherwise hidden representations do not share
  one pure topology decision boundary.

## User-Facing Behavior

- Disconnecting the display that contains a visible PiP moves the effective
  floating frame inside a current visible frame, excluding menu bars and Docks.
- Reconnecting the same display restores the preferred content size and edge
  anchor when they fit.
- A changed display identifier does not by itself lose display intent. A strong
  semantic replacement match can restore the PiP to the replacement display.
- Rearranging a known display from left to right follows that display while
  preserving the nearest horizontal and vertical edge insets.
- Changing display scale preserves the desired content size in AppKit points;
  only the effective frame is clamped to the new visible frame.
- A manual move after an automatic fallback becomes the new display intent. A
  later reconnect does not pull the PiP back to an abandoned display.
- A stashed PiP keeps its committed floating geometry while its single existing
  handle moves to a reachable edge. Its side and relative vertical placement
  remain meaningful on the replacement visible frame.
- A zoomed or native-full-screen PiP keeps its expanded presentation. Display
  changes do not commit the expanded frame over its remembered floating frame.
- A hidden PiP remains hidden, but its next presentation resolves against the
  latest accepted topology.
- Screen changes never activate, reselect, reload, replace, or recreate the
  current Notion page or WebView.

## Architecture

### Display topology values

Add a pure display descriptor containing:

- an optional display identifier;
- full frame and visible frame in AppKit points;
- backing scale factor; and
- whether the display is primary.

A topology snapshot contains a monotonically increasing revision and an ordered
array of descriptors. Synthetic fixtures construct these values directly, so
policy and coordinator tests do not inspect the CI runner's displays.

### Display affinity

Extend committed panel geometry with optional display affinity. Affinity records
the descriptor facts needed to find the intended display later without making
the volatile display identifier the sole authority.

Selection is deterministic:

1. Prefer an exact display identifier match.
2. Otherwise score semantic replacements by primary/secondary role, usable size
   and aspect ratio, backing scale, and topology relationship to the primary
   display.
3. Require a strong replacement match before preferring it over the display
   currently containing the effective panel or handle.
4. Fall back to greatest frame intersection and then nearest center.

The unified geometry payload advances to a new version. Decoding the previous
version derives affinity from its saved frame and visible frame without
discarding the existing desired size or anchor.

### Pure topology policy

Introduce a pure topology policy that consumes:

- committed geometry;
- current effective panel frame;
- optional stash intent;
- presentation kind (`visible`, `stashed`, `expanded`, or `hidden`); and
- the last accepted and incoming topology snapshots.

It returns a decision containing the accepted revision, optional effective
panel frame, and optional stash placement. Empty snapshots preserve the current
reachable representation. Revisions older than or equal to the accepted
revision are ignored.

For visible and hidden floating panels, the decision resolves the existing
desired size and anchor onto the selected current display. The coordinator sets
the frame with `display` matching current visibility. For expanded panels, the
decision accepts the topology but leaves AppKit in control of the expanded
frame and preserves the committed floating geometry. For stashed panels, the
decision leaves the hidden panel frame untouched and remaps the handle intent.

### Stash intent

Represent stash intent as edge side, normalized vertical position within the
source visible frame, and display affinity. Initial stash derives the intent
from the panel. A completed handle drag updates it. A topology change maps the
same intent to a current visible frame and presents the same handle controller
once; it never creates another panel or handle.

### AppKit observation

Move screen observation into a small `@MainActor` adapter. The adapter samples
all `NSScreen` descriptors for every
`NSApplication.didChangeScreenParametersNotification`, assigns the next
revision, and delivers the captured snapshot to the coordinator.

The snapshot is captured before asynchronous actor handoff. If deliveries run
out of order, the pure revision gate rejects older work. The coordinator uses
the same injected topology provider for initialization, notifications, stash,
restore, resizing, and move persistence.

## Coordinator Ordering And Invariants

- `PiPPanelCoordinator` continues to own exactly one retained panel.
- `PiPStashHandleController` continues to own at most one retained handle.
- Representation transitions present the incoming reachable object before
  removing the outgoing object.
- Topology updates reconcile the current representation; they never perform a
  representation transition or WebView lifecycle transition.
- Programmatic topology moves do not commit fallback display affinity.
- Manual move and completed manual resize remain the only topology-related
  paths that replace committed user geometry.
- A stale stash completion and a stale topology delivery cannot hide, move, or
  duplicate a newer representation.

## Testing

Pure synthetic-display tests cover:

- visible secondary-display disconnect;
- reconnect with the same identifier;
- reconnect with a different identifier;
- reconnect with a different backing scale;
- known-display rearrangement from left to right;
- desired-size clamping on a smaller fallback and restoration on a suitable
  display;
- menu-bar and Dock exclusion through visible-frame-only decisions;
- stashed disconnect and reconnect while retaining side and vertical intent;
- manually moved handle intent;
- hidden and expanded behavior;
- empty transient topologies;
- duplicate, stale, and out-of-order revisions; and
- deterministic semantic-match ties.

Coordinator regression tests assert that every topology transition:

- leaves exactly one retained panel and at most one visible handle;
- never calls page activation, reselection, reload, or panel show/hide lifecycle
  hooks;
- does not overwrite committed floating geometry with a clamped or expanded
  frame; and
- applies hidden frames without presenting the panel.

Run the complete suite with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Manual Evidence

Expand `docs/MANUAL_TEST_MATRIX.md` with a two-display sequence that records:

- visible, stashed, zoomed, and hidden disconnect behavior;
- reconnect with the same display;
- reconnect after changing resolution or scale;
- left/right rearrangement;
- restore from the relocated handle;
- retained page URL, unsaved edit, selection, and scroll position; and
- the absence of duplicate panels, duplicate handles, system-UI overlap, or a
  navigation reload.

Use `./script/build_and_run.sh --verify` for the staged development app. Manual
disconnect/reconnect and Spaces evidence must be reported honestly; automated
tests cannot establish WindowServer behavior.

## Constraints

- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Preserve the intentional all-Spaces floating `NSPanel` and stash-handle roles.
- Do not redesign built-in or custom panel sizes.
- Do not recreate the panel, handle, `WKWebView`, or Notion session for a screen
  change.
- Do not require Node.js, secrets, Notion credentials, or signing certificates.
