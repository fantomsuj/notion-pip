# Wispr-Style Peek Gesture Design

**Date:** 2026-08-09
**Status:** Approved interaction direction

## Summary

Change the panel shortcut from delayed tap-versus-hold recognition to an
immediate, push-to-peek interaction inspired by Wispr Flow:

- press and hold to peek immediately;
- release to return the panel to its stashed state;
- double-press quickly to keep the panel open; and
- press once while the panel is open to stash it.

The panel must never wait for gesture recognition before appearing. Timing is
used only after the first press to decide whether a second press converts the
temporary peek into a persistent open panel.

## Motivation

The existing shortcut waits 300 milliseconds before restoring a stashed panel.
That fixed delay consumes most of the product's existing warm-session goal of
showing useful content within 400 milliseconds of shortcut-down.

Wispr Flow avoids delaying the start of its primary action. Holding its
push-to-talk shortcut starts a temporary session, while double-pressing the
same shortcut locks that session into hands-free mode. Notion PiP can apply the
same model spatially: holding reveals a temporary panel, while a double press
locks the panel open.

References:

- [Use Flow hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free)
- [Supported and unsupported keyboard hotkey shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts)

Wispr Flow describes the double press as happening "quickly" but does not
publish an exact interval. Notion PiP will use a deterministic 300-millisecond
press-to-press window, matching its existing injected shortcut timing default
and keeping the value testable.

## Interaction Contract

### Stashed panel

On the first shortcut press:

1. Capture the previously frontmost application using the existing peek focus
   restorer.
2. Restore the current panel immediately. Do not wait for a timer.
3. Record the press time and enter transient peek state.

On release:

- If the key was held through the 300-millisecond double-press window, restash
  immediately.
- If the key was released before the window expired, keep the temporary panel
  visible only until the original window expires. This grace period allows a
  second press without a hide/show flicker.

If a second press begins within 300 milliseconds of the first press, after an
intervening release:

1. Cancel the pending restash.
2. Convert the temporary peek into a persistent open panel.
3. Cancel focus restoration because the user has chosen to leave Notion PiP
   active.
4. Ignore the matching second release for presentation purposes.

If no second press arrives before the window expires, restash the panel and
finish the existing focus-restoration flow.

### Visible panel

A shortcut press while the panel is already visible stashes it immediately.
Its matching release has no further effect. This applies whether the panel was
latched open by a double press or shown through another persistent surface such
as the stash handle or menu-bar command.

### No current page

Preserve the existing fallback: the shortcut presents and focuses the page URL
input. Peek and double-press recognition do not run when no page is available.

### Hold-to-peek preference disabled

Preserve the current opt-out behavior. When **Press and hold to peek** is
disabled, shortcut press immediately performs the normal persistent show or
stash action, and release has no effect.

## State Model

The runtime should represent the gesture explicitly instead of coordinating
several loosely related booleans. The minimum logical states are:

- `idle`: no shortcut gesture is active;
- `peeking`: the first press is down and the panel was restored temporarily;
- `awaitingSecondPress`: the first press was released quickly and temporary
  visibility is being preserved until the double-press deadline;
- `persistent`: a second press latched the panel open; and
- `suppressingRelease`: an action completed on press and the matching release
  must be ignored.

The exact type may differ during implementation, but state transitions must be
centralized and independently testable. A stale timer may act only when its
gesture generation still matches the active state.

## Cancellation and Edge Cases

- Changing the shortcut, disabling hold-to-peek, stopping the runtime, or
  losing a required shortcut event cancels pending gesture work.
- A panel show or stash action from the handle, menu bar, close button, or
  another command invalidates the active gesture generation. The external
  action becomes authoritative, and a later timer or release must not invert
  it.
- Cancelling a transient peek restashes only a panel restored by that gesture;
  it must never hide a panel made persistently visible by another action.
- Repeated press events without an intervening release do not count as a double
  press.
- A second press after the deadline begins a new peek rather than latching the
  expired gesture.
- If panel restoration fails, cancel focus restoration and return to `idle`.
- Display-topology changes continue through the existing panel coordinator;
  the gesture layer does not own panel geometry.
- Interaction with the panel during a transient peek preserves the existing
  focus-restoration policy. This change does not make the panel click-through
  or alter its editing behavior.

## Presentation and Feedback

The first press uses the existing restore path but invokes it immediately.
There is no reveal animation added by this design.

Temporary restashing uses a dedicated immediate order-out path so release or
double-press expiry feels as responsive as reveal. It still restores the stash
handle before removing the full panel, preserving reachability and the
existing representation transition order. Normal manual stashing retains its
current 120-millisecond fade, and Reduce Motion behavior remains unchanged.

No new persistent chrome is required. The panel remaining visible after the
second release is the primary confirmation that it has been latched open.
VoiceOver should receive a concise announcement such as “Notion PiP will stay
open” when the second press is recognized.

Settings and onboarding copy should explain the complete gesture in one line:

> Hold to peek. Double-press to keep the panel open.

## Performance Measurement

Add repeatable, privacy-safe performance intervals for:

- first shortcut press to panel presentation request;
- first shortcut press to useful Notion content becoming visible, when a
  reliable readiness signal is available; and
- release or grace-period expiry to completed restash.

Measurements must distinguish a retained warm WebView from a WebView that was
evicted and requires reloading. They must not record URLs, page IDs, titles, or
shortcut values.

The behavioral acceptance criterion is that restoring a warm stashed panel is
requested synchronously from the first press, with no gesture-recognition sleep
on the reveal path. The existing product target remains median warm
shortcut-down-to-useful-content under 400 milliseconds.

## Test Strategy

### Automated runtime tests

Cover these event sequences with an injected clock or duration and an
independent fake panel coordinator:

1. First press restores a stashed panel before any timer advances.
2. Hold beyond the window and release restashes the panel once.
3. Quick first release keeps the panel visible until the deadline.
4. A valid second press latches the panel open without reloading its page.
5. The second release leaves a latched panel visible.
6. Deadline expiry without a second press restashes and restores focus.
7. A second press after the deadline starts a new gesture.
8. Repeated press without release does not latch.
9. Press while visible stashes once and suppresses its release.
10. Disabled hold-to-peek retains immediate toggle behavior.
11. No current page retains the page-input fallback.
12. Preference or shortcut changes cancel pending timers without hiding an
    independently visible panel.

### Focus tests

Verify that:

- a completed temporary peek restores the previously frontmost application
  when the user did not interact;
- a latched double press cancels restoration; and
- failed restoration does not leave a stale focus monitor active.

### Manual checks

Exercise the gesture with the real Carbon shortcut across:

- rapid and deliberately slow double presses;
- two Spaces and two displays;
- full-screen apps, Stage Manager, and Mission Control;
- VoiceOver, Full Keyboard Access, and Reduce Motion;
- a warm panel and a panel stashed long enough for WebView eviction; and
- shortcut reconfiguration while a gesture is pending.

Confirm that there are no lost key events, visible hide/show flickers during a
successful double press, persistent focus traps, or unintended page reloads.

## Out of Scope

- A separate persistent-open shortcut.
- Triple-press behavior.
- Long-hold-to-latch behavior.
- Changing WebView retention or eviction policy without performance evidence.
- New panel geometry, Spaces, signing, entitlement, or persistence behavior.
