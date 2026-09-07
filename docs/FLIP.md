# Flip prototype

**Status:** experimental sibling of Perch. Not a 0.1 product commitment.
**Bundle ID:** `com.fantomsuj.Flip`
**Activation:** `Cmd + Shift + F` on the frontmost window; menu-bar Flip back.

Flip occupies another app's rectangle with Notion and restores that app on a
second flip. It is a window-occupancy overlay, not a Perch panel mode. Perch's
empty entitlements, privacy copy, and one-live-`WKWebView` contract stay
unchanged.

## What v0 does

1. Asks for Accessibility and Screen Recording on first launch. It does not
   request Input Monitoring and does not click other apps' title bars.
2. On `Cmd + Shift + F`, identifies the frontmost non-Perch, non-Flip window
   through Accessibility plus `CGWindowList` PID/frame matching.
3. Captures one ScreenCaptureKit frame, covers that rectangle with a Flip-owned
   borderless window, parks the original window (hide, then minimize, then
   off-screen), and animates a Y-axis card-flip to an embedded Notion home
   page.
4. The same shortcut, the overlay **Flip back** control, or Quit restores the
   parked window to the overlay's *current* frame.

The occupying window uses `.moveToActiveSpace` and does **not** join all
Spaces. Pairing is in-memory only.

## What v0 refuses

- Full-screen windows, Stage Manager locked groups (when flagged), minimized
  windows, off-screen windows, non-layer-0 windows, and windows smaller than
  320×240.
- Perch (`com.fantomsuj.Perch` / `com.fantomsuj.NotionPiP`) and Flip itself.
- Naked title-bar clicks and `CGEventTap` interception.

## Build and run

Flip is a second SwiftPM executable. It does not replace `dist/Perch.app`.

```sh
./script/build_and_run_flip.sh --verify
```

The staged bundle is `dist/Flip.app`. Full Xcode 26.2+ at
`/Applications/Xcode.app` is required, same as Perch. The script quits a
running `Flip` process before launch; it does not quit Perch.

## Permissions

Grant both before the occupancy loop can run:

- System Settings → Privacy & Security → Accessibility → Flip
- System Settings → Privacy & Security → Screen Recording → Flip

Revoking either mid-session should fail closed: Flip will not occupy a new
window. If a window is already occupied, Quit still attempts restore.

## Manual matrix

Exercise after granting permissions:

- Native titled window (TextEdit)
- Unified toolbar (Safari)
- Electron (VS Code or ChatGPT)
- Move/resize the Notion face, then flip back
- Spaces move
- Target app quit while occupied
- Display sleep
- TCC revoke mid-session

Kill the prototype if restore is unpredictable, Electron chrome misfires, or
parking drops connections often enough that the metaphor feels untrustworthy.

## Relationship to Perch

Shared Swift is limited to the idea of a Notion HTTPS URL. Flip does not import
Perch's `PiPPanelCoordinator`, `WindowRole`, or entitlements. Cookie sharing
through an App Group is intentionally not implemented; Flip has its own WebKit
session and may require a second Notion sign-in.

See [Window-flip research](WINDOW_FLIP_RESEARCH.md) for why this is a separate
application.
