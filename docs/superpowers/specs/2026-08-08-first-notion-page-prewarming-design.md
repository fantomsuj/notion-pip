# First Notion Page Prewarming Design

**Date:** 2026-08-08

**Status:** Approved

## Objective

Reduce the time from pasting a valid Notion page URL to the page being fully
interactive and ready to edit, with the cold first load as the primary target.
Showing the panel or receiving WebKit's navigation-finished callback is not the
success boundary.

The optimization may spend modest memory, CPU, and network bandwidth before
submission. It must not read the clipboard speculatively, persist an
unsubmitted URL, expose a background page, weaken URL/origin checks, or keep a
second Notion `WKWebView` alive.

## Current behavior and opportunity

URL validation and pin coordination are synchronous and small. The expensive
path starts in `NotionWebSession.restoreOrLoad`: the first activation creates
and configures a `WKWebView`, starts a remote navigation, and waits for Notion's
client application to initialize. `didFinish` ends the current restoration
signpost, but it only establishes that WebKit navigation completed. It does not
establish that Notion's editor finished hydrating or can accept input.

The existing persistent `WKWebsiteDataStore.default()` already preserves
Notion cookies and disk/memory cache data. The design should exploit that
existing session rather than introduce a separate browser profile. Apple
documents the website data store as the owner of cookies and cached website
data:
<https://developer.apple.com/documentation/webkit/wkwebsitedatastore>.

The WebView currently uses the `.suspend` inactive scheduling policy. Apple
documents that policy in terms of a WebView that is not in a window:
<https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property>.
The retained PiP panel therefore continues to own and host the one prewarming
WebView while its window is ordered out. The first implementation does not
weaken the scheduling policy globally.

## Chosen approach

Use a bounded, first-activation-only, two-stage prewarm:

1. After startup restoration confirms there is no saved active page, create
   and host the existing session's single WebView in the retained, ordered-out
   PiP panel and load `https://app.notion.com/`.
2. Observe the app-owned URL input text. When it becomes a complete valid
   Notion page URL, speculatively navigate that same WebView to the exact
   canonical page before submission.
3. On submission, adopt a matching in-flight or interactive candidate without
   issuing a second load. A mismatched, expired, or failed candidate falls back
   to the normal activation path.
4. Measure a separate editor-interactive signal instead of treating
   `didFinish` as time-to-interactive.

This gives the cold WebKit process, authenticated Notion shell, caches, and
network connection time to start before the user submits, while exact-URL
speculation overlaps the final navigation with the user's paste-to-submit
interval.

## Architecture

### First-page prewarm policy

Add a small `@MainActor` policy/controller that owns values and transitions but
never owns WebKit objects. Its states are conceptually:

- `idle`: startup restoration has not authorized prewarming;
- `warmingShell(generation)`: the neutral Notion application route is loading;
- `candidate(page, generation, phase)`: a validated exact page is loading,
  navigation-finished, interactive, or failed;
- `committed(pageID)`: first activation consumed the candidate or used the
  normal path;
- `expired`: the bounded prewarm window elapsed without activation.

Every asynchronous callback carries the generation that initiated it. A newer
candidate, restored page, external route, normal activation, expiry, memory
pressure event, or termination invalidates older callbacks.

The controller answers decisions such as start shell load, start candidate
load, adopt candidate, perform normal load, ignore stale callback, and retire
unused prewarm. `NotionWebSession` remains the sole executor of those decisions
and the sole owner/delegate of the live WebView.

### Runtime and input integration

Prewarming starts only after repository restoration has completed with no
active page. This avoids competing with the faster and more important saved-page
restore path. Both automatic empty-state presentation and the explicit
first-page handoff path request the same idempotent prewarm operation.

`AppRuntime` observes `PageURLInputState.text`; it does not read the system
pasteboard. A short 75 ms coalescing delay prevents programmatic field updates
or rapid edits from issuing redundant navigation. The value must pass the
existing `PinCoordinator.page(from:)` validation before it can become a
candidate. Canonically identical changes do nothing.

The request flows through `PinCoordinator` and `PiPPanelCoordinator` to the
existing `NotionPageLoading` boundary. Preparing a candidate does not change
`activePage`, `currentPage`, panel presentation, page history, persistence, or
the URL input's success message.

### WebView hosting and navigation

There is at most one Notion WebView:

- shell prewarm creates/configures it through the existing `ensureWebView()`;
- the retained PiP panel's content hierarchy hosts it while the panel remains
  ordered out;
- exact-page speculation navigates that same instance;
- matching submission presents and adopts it;
- normal activation supersedes it when it does not match.

Prewarm navigation uses the same default data store, navigation policy,
script-message coordinator, popup policy, and exact trusted-host checks as a
visible page. Prewarm mode explicitly suppresses page-resolution publication,
restoration capture, selection restoration, editor caret UI, and user-facing
failure state until a candidate is committed.

The unused prewarm expires after 60 seconds, matching the existing warm
retention interval. Expiry retires the WebView but leaves WebKit's persistent
cache intact. Memory pressure retires an uncommitted prewarm immediately.

## Editor-interactive readiness

Add a fourth document-start bridge alongside activity, scroll, and caret
bridges. It posts a single readiness message only after all of these conditions
hold:

- the main document is no longer in the `loading` ready state;
- a connected, enabled `contenteditable` editing surface exists;
- the surface has a nonempty visible rectangle;
- the condition remains true across two animation frames.

The script uses platform semantics (`contenteditable`, connection, geometry)
rather than Notion CSS class names. A `MutationObserver`, `DOMContentLoaded`,
`pageshow`, and animation-frame scheduling re-evaluate the condition without a
tight polling loop. The observer disconnects after publishing.

Native validation accepts the message only from the current generation, the
main HTTPS frame, and an exact trusted Notion page host. It additionally
validates the current WebView URL as a `NotionPageReference` and requires its
page ID to match the candidate or committed page. Shell, login, stale page, and
subframe messages cannot mark a candidate ready.

Read-only pages and signed-out pages may never expose an editable surface.
Readiness therefore does not gate WebView presentation or replace the existing
navigation state. A 30-second measurement timeout records a noninteractive
outcome without changing the page UI; authentication and permission flows
remain usable.

## Activation data flow

1. Runtime restoration resolves with no saved page.
2. The session creates/hosts one hidden WebView and loads the Notion app shell.
3. The user pastes a URL into the app-owned field.
4. After coalescing and existing validation, the session starts exact-page
   navigation and records the candidate generation.
5. WebKit may report provisional start, commit, finish, and editor-interactive
   milestones while the panel is still ordered out.
6. Submission validates the field again.
7. If canonical page and generation match an in-flight, finished, or
   interactive candidate, activation commits it without another request and
   presents the panel. Otherwise activation uses the existing load path.
8. Persistence and page-history recording begin only after submission, exactly
   as they do now.
9. A matching readiness event ends time-to-interactive. If readiness arrived
   before submission, the committed page is immediately considered
   interactive and the user-facing interval ends at submission.

## Failure and race behavior

- Shell-prewarm failure is silent. A later valid candidate still attempts its
  exact URL normally.
- Candidate failure before submission is not adopted. Submission performs one
  normal canonical navigation so a transient speculative failure cannot strand
  the user.
- Changing from one valid URL to another invalidates the first generation and
  navigates only the newest coalesced candidate.
- Clearing or invalidating the field cancels candidate adoption but need not
  call `stopLoading`; stale callbacks are ignored. A subsequent valid value may
  reuse the same WebView.
- A restored page, external route, page-picker activation, or direct runtime
  activation always wins and permanently commits the first-load state.
- Submission that races the 75 ms coalescing task follows the existing normal
  activation path. Correctness wins over waiting for speculation.
- Renderer termination, memory pressure, and WebView retirement invalidate
  readiness and candidate generations through the existing stale-callback
  firewall.
- No failure path displays the shell route, saves it as a page, or records it
  in history.

## Measurement and acceptance

Extend performance instrumentation with privacy-safe, repeatable operations:

- first-page shell prewarm;
- valid-input-to-editor-interactive;
- submit-to-editor-interactive.

Record only public categorical or integer metadata: cold/prewarmed path,
candidate reused or missed, navigation milestone, outcome, and elapsed-time
signposts. Never record URLs, page IDs, titles, workspace paths, query values,
cookies, document text, or DOM content.

The readiness interval begins when a validated candidate is accepted. A second
user-perceived interval begins on submission. Both end on the validated
interactive signal or the 30-second timeout. Existing navigation-restoration
measurement remains intact for historical comparison.

Before enabling the behavior by default, compare at least ten alternating
baseline and prewarm Release runs on the same machine, network, signed-in
account, and editable page. The change should demonstrate:

- at least a 20% improvement in median first-load
  valid-input-to-editor-interactive time;
- no more than a 10% regression in median native cold-launch-to-ready time;
- no duplicate exact-page request when a candidate is adopted;
- no panel presentation or persistence before submission.

Support this A/B run with a developer-only
`--disable-first-page-prewarm` launch argument. It is not a persisted setting
or user-facing preference and must alter only shell/candidate preparation, not
normal page activation.

Also record peak memory and energy observations rather than claiming they are
free. If hidden prewarming does not progress under the retained ordered-out
window with `.suspend`, stop and revisit the scheduling design based on trace
evidence; do not silently switch all hidden sessions to unrestricted
scheduling.

## Testing

### Automated

- Pure prewarm-policy tests cover authorization, idempotent shell warming,
  candidate replacement, generation rejection, candidate adoption, failure,
  expiry, memory pressure, and first-activation finality.
- URL-input integration tests prove only valid canonical values schedule
  speculation, edits coalesce, canonical duplicates do not reload, and
  submission can safely beat the coalescing task.
- Panel/session tests prove prewarm creates and hosts one WebView without
  presenting the panel, matching activation issues no second request, mismatch
  uses normal activation, and restore/external activation wins.
- Readiness-bridge tests cover exact hosts including current `.com` and legacy
  `.so`, main-frame HTTPS enforcement, stale generations, page-ID mismatch,
  malformed payloads, and one-message behavior.
- Local WebKit fixture tests add editable content after delayed hydration and
  verify readiness only after it becomes connected and visible. Fixtures also
  cover read-only content and candidate replacement.
- Performance-signposter tests cover repeatable concurrent intervals, timeout,
  candidate reuse metadata, and nil-token safety.
- Existing navigation, login popup, restoration, selection, caret, memory
  pressure, and full Swift suites remain regression gates.

### Manual

Use a staged Release build and a real account without automating credentials.
Verify signed-in cold first load, signed-out login, editable empty and populated
pages, read-only/no-permission pages, current `.com` and legacy `.so` input,
offline startup, slow network, immediate submit, delayed submit, changed URL,
memory pressure, and app termination during prewarm. Capture only sanitized
signpost summaries.

## Non-goals

- Keeping one WebView per pinned page.
- Reusing the live WebView across later page switches in this change.
- Rendering a native Notion editor or fetching page content through the API.
- Showing screenshots or cached page content as a substitute for editability.
- Reading or monitoring the clipboard before an explicit app-owned paste.
- Depending on Notion CSS class names, private WebKit APIs, or user credentials.
- Changing authentication, signing, entitlements, or the persistent website
  data store.
