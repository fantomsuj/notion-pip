# Context-Aware Page Suggestions Design

## Goal

Let Perch notice the frontmost macOS app or browser page and offer a relevant
page from Perch's existing pinned/recent working set. Accepting the card opens
the page at its saved restoration position. The feature is local-only,
explicitly enabled, and never requires a Notion token.

## Scope

- Candidates are limited to the seven pinned and seven recent pages already
  stored by Perch.
- Context collection starts only after the user enables Context Suggestions in
  Settings and grants macOS Accessibility access.
- Context consists of the frontmost app name and bundle identifier, focused
  window title, and an optional document URL exposed by Accessibility.
- Raw context is kept in memory only. It is not logged, persisted, uploaded, or
  added to the Notion page.
- Matching is deterministic. Page roles receive the strongest weight, page
  titles the next strongest weight, and pinned pages win ties.
- The current page is never suggested. Low-confidence matches, secure fields,
  Perch itself, repeated identical contexts, and recently dismissed suggestions
  remain silent.
- A small nonactivating floating card offers Open and Dismiss actions without
  stealing focus. Open activates the page through the existing runtime path and
  supplies its `DurablePageRestoration` so Perch resumes the saved document
  position.

## Architecture

`AccessibilityContextMonitor` is the platform adapter. It polls a narrow,
read-only snapshot while enabled and publishes only changed snapshots through
`ContextMonitoring`. `ContextSuggestionMatcher` is a pure domain policy that
normalizes context and scores the current working set. `ContextSuggestionController`
owns permission state, matching tasks, cooldown/suppression, and Open/Dismiss
intent. `ContextSuggestionPanelController` owns the one nonactivating `NSPanel`
and renders `ContextSuggestionCard` with SwiftUI.

`AppComposition` wires the controller to the existing `PageRepository` and to
`AppRuntime.activate`. Settings observes the controller directly. No matching,
window, or Accessibility mechanics move into `AppRuntime`.

## Interaction

1. The user enables Context Suggestions in Settings.
2. Perch requests Accessibility access using the standard macOS prompt.
3. When external context changes, the controller loads the local working set
   and asks the matcher for one confident candidate.
4. A card appears near the upper-right of the active display:
   `Safari · GitHub` / `Open Project Brief?`.
5. Open dismisses the card, activates Perch, and restores that page's last
   saved URL and scroll position. Dismiss suppresses the same context/page pair
   for thirty minutes.

## Failure and Privacy Behavior

- Denied or revoked Accessibility access stops monitoring and leaves a concise
  Settings explanation with a button to open Accessibility settings.
- Missing persistence, an empty working set, an unavailable focused window, or
  a low-confidence match produces no card.
- The monitor never reads passwords, keystrokes, clipboard contents, screenshots,
  or full DOM content.
- Disabling the preference stops monitoring immediately and closes any card.

## Testing

- Pure tests cover normalization, role/title weighting, current-page exclusion,
  deterministic ties, URL tokenization, minimum confidence, and restoration
  propagation.
- Controller tests use an in-memory monitor/store/presenter to cover opt-in,
  permission denial, changed context, dismissal cooldown, acceptance, and
  disabling.
- Window-role tests verify that the suggestion card is a retained,
  nonactivating, all-Spaces floating panel.
- Manual tests cover Accessibility prompting/revocation, Safari and Chrome
  titles/URLs where exposed, focus preservation, VoiceOver, Reduce Motion,
  Spaces, and saved-position restoration.
