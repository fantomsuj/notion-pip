# Typing-Aware PiP Chrome Design

## Goal

Make the PiP's top actions recede while the user writes in the embedded Notion page, then return as soon as the user reaches for them.

## Research

Notion's public documentation describes contextual editing controls but does not specify this micro-interaction or an exact delay. Recent editor recordings show a deliberately low-chrome writing surface, while a user report confirms pointer-oriented UI returning with pointer activity. Because the timing is undocumented, this design copies the interaction shape without claiming an exact native threshold.

Sources:

- [Notion writing and editing basics](https://www.notion.com/help/writing-and-editing-basics)
- [Recent Notion editor walkthrough](https://www.youtube.com/watch?v=PFHsAX9Eu7c&t=75s)
- [Pointer visibility while writing in Notion](https://www.reddit.com/r/Notion/comments/129rqbs/cant_see_the_mouse_cursor_while_writing_on_notion/)
- [WCAG: Focus Visible](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html)
- [WCAG: Keyboard Accessible](https://www.w3.org/WAI/WCAG22/Understanding/keyboard.html)

## Considered Approaches

1. Inject a small, origin-restricted activity bridge into the main Notion frame. Listen for `beforeinput` so real edits, IME input, dictation, and paste all count. This is the selected approach because it observes editing semantics without depending on Notion's private CSS classes.
2. Subclass `WKWebView` and treat key-down events as typing. This is simpler but incorrectly includes navigation keys and shortcuts, and it misses non-keyboard input.
3. Hide the actions whenever the WebView has focus. This hides too early: reading, selecting, and scrolling are not writing.

## Behavior

- A `beforeinput` event inside an enabled input, textarea, or editable region enters writing mode.
- Writing mode fades the top actions to transparent over 160 ms. The 32-point bar and action layout remain mounted; branding stays in the native window title instead of being repeated in the content.
- Pointer movement, editable focus loss, Tab, Escape, and navigation leave writing mode immediately.
- The bridge accepts only main-frame HTTPS messages from `app.notion.com`, `notion.so`, or `www.notion.so`.
- Duplicate state transitions are suppressed in JavaScript and again in native state assignment.
- Reduced-motion users receive an immediate visibility change.
- Transparent controls ignore pointer hits but stay represented in the view hierarchy. Tab or Escape reveals them before keyboard navigation can reach the toolbar.

## Components and Data Flow

`NotionWebSession` installs the script and a weak script-message handler when it creates its `WKWebView`. Valid activity becomes a published `isTypingInPage` state. `PiPChromeView` observes that state and changes only the action group's opacity and hit testing. Hovering the persistent top row also asks the session to reveal the actions, providing a native fallback independent of page JavaScript.

## Failure Handling

Malformed, child-frame, non-HTTPS, and non-Notion messages are ignored. Navigation resets writing mode, so a failed or replaced page cannot leave the toolbar hidden. If JavaScript is disabled or Notion changes its editor internals, the toolbar simply remains visible.

## Verification

- Unit-test accepted and rejected bridge contexts.
- Unit-test writing-mode hide/reveal transitions and navigation reset.
- Verify the installed user script runs at document start in the main frame only.
- Run the focused `NotionWebSessionTests`, the full Swift suite, and the packaged-app verification build.
