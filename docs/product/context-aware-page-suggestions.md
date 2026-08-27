# Context-aware page suggestions and exact connection

## Product contract

Context Suggestions remains one optional, local-only feature with one macOS
Accessibility permission and one Settings control. Its original behavior
continues to suggest a saved pinned/recent page by matching the frontmost app
against native-app roles and titles, and by matching focused-window titles and
exposed document URLs—including an exact working-set page ID when the URL is a
trusted Notion page. Browser names are not used as match tokens. The exact
connection is an additive reveal-time behavior; it does not create another
monitor, preference, prompt, or activation service.

## Reveal behavior

When the user deliberately reveals Perch through the global shortcut,
menu-bar Show command, status-item peek, edge handle, successful edge pull, or
Restore Current shelf row, Perch captures the source application before panel
presentation and starts one bounded exact-page read.

- If Perch has no page and a valid exact page arrives, the page opens through
  `AppRuntime.activate`, preserving the single WebView, recents, persistence,
  restoration, and status behavior.
- If Perch already has a different page, it reveals immediately and retains
  that page. A slim, dismissible **Open Here** action appears inside Perch.
- If the page IDs match, no action appears.
- Explicit pinned/recent choices are authoritative. They do not start exact
  detection and invalidate outstanding reveal results.
- Each reveal supersedes the prior generation, so stale callbacks cannot
  activate a page or restore an old action.

No context, denial/revocation, termination, malformed attributes, unsupported
sources, or timeout silently follows the pre-existing reveal or setup path.

## Detection and privacy boundary

`AccessibilityContextMonitor` snapshots the frontmost process synchronously,
then performs the AX read on its existing utility queue. The exact reader uses
only `AXDocument` and `AXURL` values from the focused window, focused element,
and at most three parents. It does not scan an Accessibility tree or read page
contents, selected text, keystrokes, screenshots, clipboard data, or a window
title for exact inference.

The focused recent-page shelf is the one path that can activate Perch before a
reveal choice is made. It therefore retains only the source process identity
immediately before requesting focus. No URL is read at that point. Choosing
Restore Current consumes that identity for the reveal-time AX read; dismissing
the shelf or choosing an explicit recent page discards it.

Known browser bundle identifiers are allowlisted for Safari, Safari Technology
Preview, Chrome stable/beta/canary, Firefox, Edge, Brave, and Arc. Their values
must pass `NotionPageReference` unchanged as HTTPS. The native Notion bundle
(`notion.id`) may first normalize an exact `notion://www.notion.so/...` link to
HTTPS, after which the same host, credentials, length, path, and page-ID checks
apply. Raw source values and URL candidates—including rejected candidates—stay
in memory and are not logged or persisted as Accessibility context. Once an
empty Perch auto-opens a validated page, or the user accepts **Open Here**, its
validated page reference follows Perch's ordinary device-local recents,
persistence, and restoration behavior.

## Architecture

- `ContextSnapshot` carries a source process identity and optional exact page.
- `AccessibilityExactPageContextResolver` and
  `ContextualNotionPageResolver` enforce the URL/source trust boundary.
- `ContextSuggestionController` owns capture generation, timeout, empty-state
  fallback, same-page checks, and contextual activation intent.
- `ContextualPageActionState` is the narrow observable companion shared with
  `PiPChromeView`; it carries no detection or activation policy.
- `PiPPanelCoordinator.onWillReveal` covers retained-page reveal paths before
  presentation. `AppRuntime` invokes the same controller only when an empty
  reveal would otherwise open setup.
- Acceptance and empty auto-open both call the existing runtime activation
  closure with `.contextSuggestion`; no parallel WebView or page store exists.

## Compatibility limits

Detection depends on the source application exposing a focused URL attribute.
Unsupported browser channels with different bundle IDs, private or protected
views, and applications that omit or delay AX URL attributes fall back without
an action. This is intentionally narrower than guessing from a title or
scanning UI hierarchies.
