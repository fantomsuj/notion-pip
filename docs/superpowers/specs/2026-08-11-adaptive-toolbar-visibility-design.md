# Adaptive Toolbar Visibility Design

## Goal

Keep Perch's complete top toolbar visible while the embedded Notion page is idle, and automatically hide the entire toolbar—including the four corner controls—while the user types or scrolls.

## Selected Interaction

Perch uses the existing origin-restricted WebKit activity bridge rather than observing private Notion CSS classes or treating all WebView focus as editing.

- Idle page: show the complete toolbar.
- Typing in an enabled text field, text area, or editable region: hide the complete toolbar.
- Scrolling the main document or a nested Notion scroller: hide the complete toolbar at the start of scrolling and reveal it after 500 milliseconds without another scroll event.
- Pointer movement after typing, editable focus loss, Tab, or Escape: return to idle immediately.
- Resting the pointer at Perch's top edge: reveal the toolbar through the existing delayed top-edge hover affordance.
- VoiceOver, Switch Control, and Full Keyboard Access: keep the toolbar visible.
- Reduce Motion: change visibility without animation.

The toolbar continues to overlay the Notion surface and reserves no content height.

## Considered Approaches

1. **Extend the existing semantic activity bridge (selected).** This reuses the current trusted-main-frame messaging boundary, detects nested scrolling in capture phase, and leaves Notion's private DOM structure alone.
2. **Monitor AppKit mouse and key events.** This cannot reliably distinguish editing from shortcuts or page navigation and cannot see JavaScript-driven scrolling semantics.
3. **Hide whenever the WebView has focus.** This would hide controls while the user is only reading or selecting, which is too aggressive.

## Architecture

NotionWebScriptMessageCoordinator extends NotionEditorActivity with scrolling start and end messages. Its existing document-start main-frame script sends the start message on the first scroll event, resets a 500-millisecond timer for subsequent events, and sends the end message after the quiet period.

NotionWebSession continues publishing isTypingInPage for its lifecycle protections and additionally publishes isInteractingWithPage for toolbar visibility. Typing and scrolling start interaction; editing or scrolling end it. Navigation, panel suspension, renderer termination, and explicit reveal paths reset interaction.

PiPChromeView combines page interaction, top-edge hover, and accessibility state in a pure visibility policy. Idle or hover produces the expanded toolbar. Active page interaction produces the hidden presentation even when a position controller exists.

## Failure Handling

Malformed, child-frame, non-HTTPS, and non-Notion messages remain ignored. If the injected script is unavailable, the toolbar remains visible. Duplicate activity messages are harmless because published state assignments are guarded. Navigation resets the toolbar so a stale document cannot leave it hidden.

## Testing

- Policy tests prove idle is expanded, typing/scrolling hides all controls, hover reveals, and accessibility overrides hiding.
- Session tests prove typing and scrolling update interaction independently and navigation clears it.
- Script tests prove scroll start/end hooks and the 500-millisecond quiet-period timer are installed.
- Existing hover-delay, origin-validation, lifecycle, and full Swift suites remain regression coverage.
