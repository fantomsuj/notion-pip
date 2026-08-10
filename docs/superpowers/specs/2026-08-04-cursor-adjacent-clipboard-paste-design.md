# Cursor-Adjacent Clipboard Paste Button Design

## Goal

Move the existing “Fill copied text” button from the fixed bottom-right corner
of the Perch to the current Notion text insertion caret whenever a trusted,
live caret can be located. Preserve the button’s current insertion behavior and
provide a stable fallback when no editable caret exists.

## Assumption

“Cursor” means the text insertion caret inside the embedded Notion editor, not
the macOS pointer. This matches the button’s existing help text and its current
saved-editor-selection insertion behavior.

## Considered Approaches

### 1. Native SwiftUI button driven by trusted caret geometry — selected

A main-frame WebKit user script observes generic selection and viewport events,
publishes a validated caret rectangle through an origin-restricted message
handler, and lets `PiPChromeView` position the existing native button. This
keeps clipboard access in native code, preserves the existing selection-token
insertion path, and does not depend on Notion-specific class names.

### 2. Inject the button into Notion’s DOM

This gives direct CSS-pixel placement and naturally follows page scrolling, but
it mutates third-party page markup, requires a new command bridge back to native
clipboard access, and risks style or event conflicts when Notion changes its
DOM. The tighter coupling is not justified for one control.

### 3. Position a separate AppKit overlay

An AppKit subview or child window could be positioned above `WKWebView`, but it
still needs the same JavaScript caret geometry and introduces more focus,
layout, and accessibility coordination than the existing SwiftUI overlay.

## Interaction Design

- With a collapsed selection inside a live, focused `contenteditable` element,
  place the button six points below and to the right of the caret.
- If the control would cross the right edge, place it to the caret’s left.
- If it would cross the bottom edge, place it above the caret.
- Clamp the final position to an eight-point inset inside the visible web view.
- Use a fixed 30-by-30-point control footprint so placement is deterministic.
- Do not animate caret-following movement. Animation would make the control
  chase the user while typing and could increase distraction.
- When no valid editable caret is available, retain the existing bottom-right
  placement. This avoids removing the control for VoiceOver, Full Keyboard
  Access, loading transitions, or stale/unsupported Notion editor states.
- Keep the existing label, help, prominent style, and paste action. Clipboard
  contents are read only when the user activates the button; the feature does
  not poll or monitor the pasteboard.

## Architecture

`NotionEditorCaretBridge` owns the message schema, origin checks, and main-frame
user script. The script uses only platform DOM APIs: `window.getSelection()`, a
collapsed `Range`, `Element.closest('[contenteditable]')`, and
`Range.getClientRects()`. It schedules at most one publication per animation
frame in response to `selectionchange`, `input`, `focusin`, `focusout`, `keyup`,
`pointerup`, captured scroll events, and viewport resize.

The visible message includes caret `left`, `top`, and `bottom` coordinates plus
the script viewport width and height. The native side scales those coordinates
to the actual SwiftUI overlay size, so placement remains correct when WebKit
zoom or viewport dimensions differ from view points. A hidden message contains
only `visible: false`.

`NotionWebSession` installs the new handler beside its existing editor-activity
and scroll handlers. It accepts messages only from the current web view and
current generation, then publishes `editorCaretGeometry` for the view. Page
replacement, navigation, suspension, failure, process termination, and web-view
retirement clear the geometry through the same interaction invalidation path
that already clears saved selection state.

`CursorAdjacentControlPlacement` is a pure geometry policy. It converts the
validated CSS viewport geometry into view coordinates, chooses below/right,
flips as needed, clamps to the inset, and returns a control-center point.
`PiPChromeView` uses that point inside its existing web-view overlay.

## Data and Trust Boundaries

- Only HTTPS messages from the trusted Notion hosts `app.notion.com`,
  `notion.so`, and `www.notion.so` are accepted.
- Only main-frame messages are accepted.
- Visible messages must contain exactly `visible`, `left`, `top`, `bottom`,
  `viewportWidth`, and `viewportHeight`.
- All numeric values must be finite; viewport dimensions must be positive; the
  bottom coordinate must not precede the top coordinate.
- The bridge carries geometry only. It never carries clipboard contents,
  document text, selection text, tokens, or credentials.
- Retired web-view and stale-generation messages are ignored.

## Error and Edge-Case Behavior

- Expanded selections, missing selections, disconnected nodes, unfocused
  editables, offscreen ranges, zero-height ranges, and JavaScript errors hide
  the cursor-adjacent placement and use the bottom-right fallback.
- Scroll and resize updates are request-animation-frame throttled.
- A native button click may temporarily remove page focus. The existing
  `rememberCurrentEditorCursor` then `insertAtSavedEditorCursor` flow remains
  authoritative; placement geometry is never used as an insertion target.
- If Notion replaces the editable DOM node between capture and activation, the
  existing selection token rejects insertion rather than inserting elsewhere.
- The button does not become conditional on clipboard content because checking
  that content before explicit activation would broaden pasteboard access.

## Testing

- Unit-test strict bridge parsing for trusted visible, trusted hidden,
  subframe, non-HTTPS, untrusted-host, malformed-schema, non-finite, and invalid
  viewport cases.
- Unit-test placement below/right, horizontal flip, vertical flip, both-edge
  clamping, viewport scaling, and bottom-right fallback.
- Extend `NotionWebSessionTests` to verify current-generation publication,
  retired-web-view rejection, and geometry clearing on interaction invalidation.
- Preserve the existing `NotionEditorSelectionTests` insertion regression test.
- Run the full Swift test suite with the required Xcode toolchain.
- Manually verify caret following, scrolling, zoom, fallback, keyboard access,
  VoiceOver labeling, light/dark appearances, and actual clipboard insertion in
  a signed-in Notion page.

## Out of Scope

- Changing clipboard contents, clipboard monitoring, or clipboard history.
- Replacing the existing text insertion implementation.
- Adding placement settings or a user-selectable fallback location.
- Supporting text controls or cross-origin subframes that the current Notion
  selection insertion code does not support.
- Modifying Notion’s private DOM structure or CSS classes.
