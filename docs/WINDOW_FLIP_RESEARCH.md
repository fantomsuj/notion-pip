# Research: flip any window to Notion

**Prepared:** 2026-09-07
**Status:** research complete; experimental sibling prototype lives in
[`docs/FLIP.md`](FLIP.md) and `Sources/Flip`. Still not a Perch option.
**Question:** Can a user click the top of another app (for example ChatGPT) and
have that window flip over so Notion is on the other side? Should that live in
Perch, or as a separate application?

> This is not a current product plan. It evaluates a requested interaction
> against macOS public APIs, Perch's existing overlay architecture, and the
> privacy contract already published for Perch 0.1.

## Recommendation

**Build this, if at all, as a separate application.** Do not add it as a Perch
setting, panel mode, or in-process option.

The interaction is a reversible window-occupancy trick: take over another app's
rectangle, show Notion there, and restore the original app on a second flip.
That is a window manager with a card-flip animation, not an always-on-screen
notebook. It needs permissions Perch currently refuses to request, it fights
Perch's one-live-`WKWebView` floating panel, and a naive "click the title bar"
gesture would steal drag, double-click zoom, and traffic-light clicks from
every other app.

A sibling app (same repo and team identity is fine; separate bundle ID,
entitlements, and privacy copy are required) can prototype the illusion without
changing what Perch is.

## What the request is asking for

The desired loop:

1. The user is working in another app, e.g. the ChatGPT desktop window.
2. They click the top of that window.
3. The window appears to flip, like a card, and Notion is on the reverse face.
4. A second flip restores ChatGPT in the same place, at the same size.

That is a spatial-memory job: keep Notion in the same rectangle as the current
task so the user does not hunt for another window. Perch already solves a
nearby job ("leave a notebook open beside the keyboard"). This request wants
Notion *in place of* the current window, then back again.

## Why macOS will not actually flip ChatGPT's window

AppKit, WindowServer, and TCC make the literal reading of this idea
impossible with public APIs:

- A process cannot apply `CATransform3D`, rotate, or replace the content of
  another process's `NSWindow`. WindowServer composites each app's surfaces
  independently.
- There is no public API to add a title-bar accessory, toolbar item, or click
  handler to a foreign window. Title-bar clicks belong to that app.
- Private CoreGraphics WindowServer calls (historical `CGSSetWindowTransform`,
  alpha, and similar) can manipulate other windows. They are unstable across
  macOS versions, incompatible with notarized Developer ID distribution as a
  durable strategy, and should not be used.
- Injecting code into ChatGPT or other apps (SIMBL, mach injection, dylib
  insertion) is a non-starter under SIP, notarization, and Perch's trust model.

The only honest implementation is an **illusion**: snapshot the foreign window,
animate a flip in a window *we* own that covers the same frame, then show our
own Notion surface there while the original window is hidden, moved, or
covered.

That illusion is what existing "pin any window on top" utilities already do,
in the opposite direction. Apps such as WindowPin, WinTop, PinWindow, MenuPiP,
and Floaty cannot raise another app's window level. They capture it with
ScreenCaptureKit and draw a live mirror in their own floating panel. A flip
would use the same public-API ceiling: we own the overlay, not the foreign
window.

## Technical approaches

### Approach A — Snapshot, overlay, hide, restore (viable prototype)

This is the only public-API path that can look like the requested animation.

1. **Identify the target window.** Accessibility (`AXUIElementCopyElementAtPosition`,
   `kAXWindowAttribute`, `kAXPositionAttribute`, `kAXSizeAttribute`) plus
   `CGWindowListCopyWindowInfo` / ScreenCaptureKit `SCShareableContent` to get
   a `CGWindowID`. Mapping AX elements to window IDs commonly uses the
   long-stable but still private `_AXUIElementGetWindow`; many utilities do
   this. A prototype can also match by PID + frame as a public-only fallback.
2. **Capture one frame** of that window with ScreenCaptureKit
   (`SCContentFilter(desktopIndependentWindow:)`). This is the supported
   replacement for the deprecated `CGWindowListCreateImage`. It requires
   Screen Recording permission even for a single snapshot.
3. **Cover the original frame** with a borderless, opaque `NSWindow` we own,
   at a high window level, sized and placed to the target.
4. **Animate the flip** in Core Animation: perspective `m34`, `CATransform3D`
   rotation about Y, front face = captured bitmap, back face = Notion
   `WKWebView` (or a snapshot of it until the live view is ready). Classic
   "flip one `NSWindow` to another" samples do this with a temporary animation
   window; they only work because both faces are views we own.
5. **Park the original window** for the duration: Accessibility hide, minimize,
   or move off-screen, and remember PID, AX identity, and the pre-flip frame.
6. **Reverse** on the second flip: snapshot Notion, animate back, restore the
   parked window to the overlay's current frame (so a moved/resized Notion
   face returns ChatGPT to the new rectangle), then order the overlay out.

**What this gets right:** the visual metaphor; reversible occupancy; no
private WindowServer transforms.

**What stays hard:** see [Hard edges](#hard-edges-that-a-prototype-will-hit).

### Approach B — Title-bar overlay chips (more discoverable, more fragile)

Track every on-screen window with `AXObserver` (`kAXWindowCreatedNotification`,
moved, resized, focused). Place a thin nonactivating `NSPanel` over the top
~28–40 pt of each window containing a flip control.

This is how a visible "click the top" affordance would actually work. It does
not intercept the rest of the title bar.

Costs: panels lag one frame behind window moves; they collide with traffic
lights, native tabs, and notches; they break on custom Electron chrome; they
must be excluded from Mission Control and screenshots carefully; and they
require constant Accessibility observation of the whole session.

### Approach C — Global event tap on title-bar clicks (do not ship naked)

A `CGEventTap` can see mouse-downs before the target app. Combined with
`AXUIElementCopyElementAtPosition`, a tap can guess "this click is in the top
40 pt and the hit role is `AXWindow` / `AXToolbar` / `AXGroup`" and swallow
the event.

That guess is exactly what third-party title-bar tools use, because
Accessibility has no reliable `AXTitleBar` hit for many apps. It is also how
you accidentally steal:

- window dragging
- double-click to zoom
- traffic lights
- native tab clicks
- Electron `-webkit-app-region: drag` chrome (ChatGPT, Slack, VS Code, Figma)

A **modifier-gated** tap (for example Option-click in the top 40 pt) is the
only event-tap variant worth prototyping. Naked click-the-top is hostile to
the rest of the Mac.

Event taps typically need Accessibility and, on current macOS, Input
Monitoring. They must run on a dedicated thread, handle tap timeouts, and
fail closed if TCC is revoked.

### Approach D — Private WindowServer transforms or injection (reject)

Do not rotate, alpha-fade, or reparent another app's window via private CGS
APIs. Do not inject into ChatGPT. Notarization, SIP, and future OS releases
make this a maintenance trap, and it is a worse privacy story than an overlay
we clearly own.

## Activation models, ranked

| Activation | Fit to the request | Reliability | Collateral damage |
| --- | --- | --- | --- |
| Global shortcut on the frontmost window | Medium | Highest | Low |
| Modifier + click in the top ~40 pt | High | Medium | Low if the modifier is required |
| Hover chip on the top edge | High | Medium | Overlay bookkeeping |
| Naked click on the top of any window | Highest | Low | Steals title-bar behavior |

A first prototype should use the shortcut, then optionally add modifier-click.
Naked title-bar click should stay out of scope.

## Hard edges that a prototype will hit

### Custom title bars, especially ChatGPT

The motivating example is a poor first target. The ChatGPT desktop app is an
Electron shell. Electron windows often use `titleBarStyle: 'hidden'` /
`hiddenInset` and CSS `-webkit-app-region: drag`. There is no standard
`AXTitleBar`. "The top of the window" is an app-defined strip that also
contains chat UI. Hit-testing becomes a pixel heuristic, the same 40 pt rule
other utilities already document as imperfect.

Safari tabs, unified toolbars, Notion's own desktop app, games, and
full-screen native apps have the same class of problem.

### What happens to ChatGPT while Notion is showing

The original app is still running. Choices:

- **Cover it** with an opaque overlay. Z-order fights (Exposé, Spaces, the
  original app raising itself). Keyboard focus can still land in ChatGPT.
- **Hide or minimize via Accessibility.** Some apps pause media, disconnect
  realtime sockets, or animate a Dock bounce on restore.
- **Move off-screen.** A classic window-manager trick; Mission Control and
  Stage Manager can still reveal it.

None of these is a true "other side of the same window." Notifications,
audio, and background work continue in ChatGPT unless that app decides
otherwise.

If the user moves or resizes the Notion face, restore must apply the new
frame to ChatGPT. If ChatGPT opens a second window, the pairing must be
per-window, not per-app.

### Full screen, Stage Manager, Split View, Spaces

Perch's panel is an `NSPanel` that joins all Spaces
(`.canJoinAllSpaces` + `.fullScreenAuxiliary`). Occupying another app's
window is the opposite: it must stay on *that* window's Space, match Stage
Manager grouping, and not follow the user around.

Full-screen ChatGPT lives on its own Space. An overlay can be
`.fullScreenAuxiliary`, but hiding the fullscreen window and substituting
Notion is a different product from Perch's "travel with me" panel. Existing
always-on-top overlay apps already document that they cannot pin above a
true fullscreen Space.

### One live Notion page

Perch owns **one** retained `WKWebView` and reuses it for pinned/recent
switching. A flip overlay that is also Perch would steal that session from
the PiP: stashed handle, peek, and the occupied ChatGPT face cannot all
show the same live editor at once.

A separate app can host its own WebKit session. That means a second Notion
login unless the two apps share a `WKWebsiteDataStore` through an App Group.
App-group cookie sharing is possible for two apps signed by the same team;
it is extra product and security surface, not a reason to merge processes.

`WKWebView` itself cannot be shared across processes. XPC cannot move the
live editor. The native Notion app is a third option: the flip could reveal
or create a native Notion window in the same frame via Accessibility rather
than embedding WebKit. That is simpler and less "the other side of this
window," because the user would see Notion's own chrome and a second
process popping into place.

### Permissions versus Perch's current contract

A working prototype needs:

- **Accessibility** — window identity, frame, hide/move/restore, observers
- **Screen Recording** — ScreenCaptureKit snapshot for the front face
- **Input Monitoring** — only if using a `CGEventTap`

Perch's published privacy policy currently says it does not request
Accessibility or screen recording. Context Suggestions, which used
Accessibility for reveal-time exact-page detection, was removed; the
changelog now states Perch no longer requests Accessibility. Putting a
window-flip option behind a Perch toggle would reintroduce those TCC prompts
into the accessory users already installed for a small floating notebook.

## Why this should not live inside Perch

Perch's thesis is one calm, always-available Notion page beside other work.
The architecture matches that thesis: accessory activation policy, one
floating `NSPanel`, edge stash, global shortcut, one WebKit session, empty
entitlements file, no Accessibility in the 0.1 product.

Prior product research already treated this neighborhood as out of scope:

- Automatic app-aware switching: do not build.
- Multiple live panels / becoming a window manager: do not pursue.
- Decision tests: shorten the path to one page, preserve the user's place in
  the primary app, stay calmer than ordinary window switching, avoid
  observing context the user did not give.

A flip that occupies ChatGPT fails several of those at once. It *replaces*
the primary app's place on screen, observes other windows continuously or on
click, and is not calmer than `Command-Tab` unless the animation is
perfect—which it will not be across Electron chrome, Spaces, and fullscreen.

Shipping it as "another option" in Settings still:

- loads event taps, window tracking, and ScreenCaptureKit into the Perch
  process
- changes the TCC story for every Perch user, including people who never
  enable the option (the binary requests the rights; the prompt may be lazy,
  but the capability is in the app)
- couples PiP stash/peek/Spaces behavior to a second, exclusive window role
- turns support into window-manager bugs (why did Slack's title bar stop
  dragging?) instead of notebook bugs

Those are product-identity costs, not just engineering costs.

## Why a separate application is the better shape

A sibling app can:

- use a distinct bundle ID and privacy copy that *does* explain Accessibility
  and Screen Recording before first use
- be a regular accessory or Dock utility without changing Perch's panel
- fail, be uninstalled, or remain experimental without regressing Perch
- own pairing state (which window is flipped) without colliding with PiP
  geometry, stash handles, or the all-Spaces collection behavior
- decide later whether to share an App Group with Perch for Notion cookies

Same-repo is reasonable: a second SwiftPM executable, second staged
`.app`, no shared process. Shared Swift code should stay limited to URL
validation and Notion page-reference types. Do not share
`PiPPanelCoordinator` or `WindowRole` — those encode Perch's overlay
contract.

If the sibling later proves the interaction, the question of merging can be
reopened with evidence. Starting inside Perch makes the evidence
untrustworthy because the overlay and the occupier will fight.

## Perch-shaped alternatives that are *not* this idea

These are cheaper and still wrong to treat as the same feature:

1. **Expand the PiP to the frontmost window's frame.** Still needs
   Accessibility for the frame; still covers the other app; no flip; still a
   window manager. Reject unless the sibling prototype shows occupancy is
   the job.
2. **Flip Perch's own panel** (Dashboard-widget style, Notion on the back of
   Perch). Fun, implementable with views we own, and not the request.
3. **Peek / shortcut** already in Perch. Solves "get to Notion quickly"
   without occupying ChatGPT. If the real pain is reachability, improve peek
   rather than building a flip.

## Suggested prototype, if someone builds the sibling

Keep it small enough to falsify the idea:

1. Separate executable and bundle. Explicit first-launch copy for
   Accessibility + Screen Recording. No event tap in v0.
2. Shortcut only: "flip the frontmost non-Perch window." Exclude full-screen,
   Stage Manager locked groups, and apps with no AX window.
3. ScreenCaptureKit snapshot → overlay flip → live `WKWebView` (or native
   Notion raise) occupying the saved frame. Park the original via AX
   `kAXHiddenAttribute` or off-screen move. Store pairing in memory only.
4. Same shortcut flips back. Moving the overlay updates the restore frame.
5. Manual matrix: native titled window (TextEdit), unified toolbar (Safari),
   Electron (ChatGPT or VS Code), Spaces move, display sleep, target app
   quit mid-flip, TCC revoke mid-session.
6. Kill the idea if users cannot predict restore, if Electron chrome misfires,
   or if parking the original app drops connections often enough to distrust
   the metaphor.

Do not start with naked title-bar clicks. Add modifier-click only after the
shortcut occupancy loop is trustworthy.

The first cut of that sibling is `Sources/Flip`, staged as `dist/Flip.app`,
and documented in [`docs/FLIP.md`](FLIP.md).

## Decision

| Question | Answer |
| --- | --- |
| Can macOS flip ChatGPT's actual window? | No. |
| Can we fake it with public APIs? | Yes, as a snapshot + overlay + parked original window. |
| Is "click the top of any window" a safe gesture? | No, unless gated by a modifier or a dedicated chip. |
| Should this be a Perch option? | No. |
| Separate app? | Yes, if the metaphor is worth a prototype. |
| Share Perch's process, entitlements, or PiP coordinator? | No. |

The notebook and the card-flip occupier can coexist as products. They should
not coexist as modes of the same accessory.
