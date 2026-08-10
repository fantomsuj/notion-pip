# Lecture 1 — Product and User Experience

**Duration:** 45 minutes

Perch is “a little piece of Notion that stays with you”: a native macOS
accessory that keeps a real Notion page close while other work continues. This
lecture builds a precise product model before later lectures explain the code.
It describes the committed repository snapshot; unrelated unstaged product
changes present while the course was authored are outside that snapshot.

Keep the [course glossary](GLOSSARY.md) nearby and use the
[architecture map](ARCHITECTURE_MAP.md) when you want to follow a journey past
the first owning subsystem.

> **Source-authority callout:** the root [README](../../README.md#what-it-feels-like)
> says, “Create a fresh Notion page from the `+` button; it becomes the new
> pinned page automatically.” That sentence is inconsistent with this committed
> source snapshot. Here the toolbar `+` invokes **Quick Capture** in
> [`PiPChromeView.swift`](../../Sources/Perch/Views/PiPChromeView.swift).
> Activating a new page records its visit so it appears in **Recent**; the pin
> control on each [`PageSwitcherView`](../../Sources/Perch/Views/PageSwitcherView.swift)
> row explicitly promotes it to a pinned favorite or removes that favorite.
> This lecture follows committed source behavior rather than the inconsistent
> README sentence.

## Learning objectives

By the end of this lecture, you can:

1. Explain the notebook metaphor and the interruption cost the product reduces.
2. Distinguish an accessory app, a floating panel, and an ordinary Dock app.
3. Describe how one live Notion view behaves during switching, stashing,
   resizing, and restoration.
4. Walk through page pinning, page switching, Quick Capture, and optional API
   setup from a user's point of view.
5. Map a user action to its first UI surface and to the subsystem that owns the
   result.
6. Identify behavior that automated tests cannot establish without the real
   macOS window server, Spaces, focus system, login session, or Launch Services.

The primary product statement is the repository [README](../../README.md), and
the precise macOS expectations live in the
[manual test matrix](../MANUAL_TEST_MATRIX.md).

## Before you begin

No Swift or macOS development experience is required. You need only the ideas
of a user action, visible state, saved state, and a system boundary. If you are
running the app, sign in to your own account inside the embedded Notion page.
Never paste a password, session cookie, or integration token into chat or a
terminal command. The optional token belongs only in the app's Settings UI, as
the [repository setup guidance](../../AGENTS.md) explains.

Use these terms consistently:

- A **Space** is a macOS desktop or full-screen workspace.
- An **accessory application** runs without an ordinary Dock presence. Its
  absence from the Dock is intentional, not evidence of a crash.
- An **`NSPanel`** is an AppKit window suited to auxiliary floating UI.
- A **`WKWebView`** is an embeddable browser view. Here it shows the real Notion
  web application rather than a screenshot or native imitation.
- An **edge stash** hides the full panel while leaving a small handle on the
  nearest screen edge.

These definitions are expanded with source examples in the
[glossary](GLOSSARY.md#accessory-application).

**Manual-verification boundary:** a learner can read the intended behavior in
source, but must use the [manual test matrix](../MANUAL_TEST_MATRIX.md) to
establish actual Dock, Spaces, focus, Mission Control, multi-display, and
full-screen behavior on a real Mac.

## Foundation

### The open-notebook metaphor

An ordinary browser or desktop Notion window is a destination: the user leaves
the current task, finds the window, and enters the workspace. Perch is more
like leaving a notebook open beside the keyboard. The page is already present,
small enough to coexist with the main task, and easy to tuck away without
closing the thought. The product goal is not to replace Notion. It shortens the
distance between “I should write that down” and writing it down.

That metaphor leads to four product principles:

- **Familiar content:** the panel contains the live Notion web app, with the
  user's own authenticated session and editing experience.
- **Ambient availability:** the panel and its stash handle intentionally join
  all Spaces and can accompany full-screen work.
- **Low-cost interruption:** a shortcut, optional menu-bar item, edge handle,
  and Quick Capture provide short routes back to writing.
- **Continuity:** moving, resizing, stashing, or switching should preserve as
  much working context as the lifecycle permits.

### Three kinds of state

It helps beginners to separate what “the same page” can mean:

1. **Live browser state** includes the current editor, selection, history, and
   other WebKit interaction state while the process retains it.
2. **Durable page state** includes a validated Notion URL and best-effort scroll
   restoration that can survive relaunch.
3. **Presentation state** says whether the panel is visible or stashed, plus its
   size and screen geometry.

The app owns at most one live Notion `WKWebView`, not one browser per saved
page. Switching therefore captures the outgoing page's available interaction
state and reuses that one view for the selected page. Across launches, or after
WebKit state is discarded, the fallback is the last validated URL and a
best-effort two-second scroll restoration; if that fails, the canonical page
URL and natural scroll position win. See the product explanation in the root
[README](../../README.md#a-native-mac-app-with-a-real-notion-page-inside).

## Repository tour

This first tour is organized by what the user sees, not by implementation
layer. Later lectures unpack each path.

| Product surface | What the user experiences | Starting source |
|---|---|---|
| Process presence | No Dock icon; menu-bar access is on by default and can be hidden | [`AppDelegate.swift`](../../Sources/Perch/App/AppDelegate.swift), [`StatusItemController.swift`](../../Sources/Perch/Platform/StatusItemController.swift) |
| Floating notebook | An editable Notion page in a floating, all-Spaces panel | [`WindowRolePolicy.swift`](../../Sources/Perch/Platform/WindowRolePolicy.swift), [`PiPChromeView.swift`](../../Sources/Perch/Views/PiPChromeView.swift) |
| Page entry | A validated Notion page URL can be entered; an allowlisted external handoff can activate a page | [`AppRuntime+Activation.swift`](../../Sources/Perch/App/AppRuntime+Activation.swift), [handoff protocol](../HANDOFF_PROTOCOL.md) |
| Page switcher | Up to seven favorites and seven nonfavorite recent pages, with local subsequence search, keyboard selection, and an explicit pin/unpin control | [`PageWorkingSetPolicy.swift`](../../Sources/Perch/Domain/PageWorkingSetPolicy.swift), [`PageSwitcherView.swift`](../../Sources/Perch/Views/PageSwitcherView.swift) |
| Edge stash | The full panel gives way to a slim handle on the nearest edge; restoring returns the retained panel | [`PiPPanelCoordinator.swift`](../../Sources/Perch/Platform/PiPPanelCoordinator.swift), [`PanelStashPolicy.swift`](../../Sources/Perch/Platform/PanelStashPolicy.swift) |
| Panel size | Built-in and custom presets resize the retained panel without intentionally reloading Notion | [`PanelSizeController.swift`](../../Sources/Perch/App/PanelSizeController.swift), [`PanelSizeSettingsView.swift`](../../Sources/Perch/Views/PanelSizeSettingsView.swift) |
| Quick Capture | The `+` control or capture command opens a focused local editor whose draft is saved before delivery | [`AppCommandModel.swift`](../../Sources/Perch/App/AppCommandModel.swift), [`QuickCaptureView.swift`](../../Sources/Perch/Views/QuickCaptureView.swift) |
| Optional Notion API access | Settings accepts a personal token for destination search and delivery; the token stays in Keychain and never enters the live Notion view | [`SettingsView.swift`](../../Sources/Perch/Views/SettingsView.swift), [`PersonalTokenCredentialVault.swift`](../../Sources/Perch/Platform/PersonalTokenCredentialVault.swift) |

The live Notion sign-in and the optional personal API token are separate trust
domains. Browser cookies belong to the embedded Notion session. The token is
needed only for API-backed Quick Capture destination search and delivery; it is
not needed to build, launch, pin, view, or edit a Notion page.

**Manual-verification label:** collection behavior in
[`WindowRolePolicy.swift`](../../Sources/Perch/Platform/WindowRolePolicy.swift)
states the all-Spaces policy, but the real outcomes for Mission Control,
full-screen Spaces, keyboard focus, and display changes are manual checks.

## Runtime trace

### Journey 1: open the notebook and work in Notion

1. The app launches as an accessory, so the user should look for the menu-bar
   item or panel rather than a Dock icon.
2. If no page is available, tapping the default panel shortcut, `Command-Shift-P`,
   opens and focuses page URL entry. A typed URL must be a supported HTTPS
   Notion page URL with a page ID.
3. A valid page is activated, presented in the floating panel, and recorded as
   a visit in the page working set. A newly activated page appears under
   **Recent**; activation alone does not make it a pinned favorite.
4. The retained `WKWebView` loads the actual Notion page. Authentication happens
   inside that view using the user's Notion account.
5. The user edits normally while the panel floats across Spaces. Hovering the
   top edge reveals controls; accessibility modes keep those controls available
   without depending on hover.

The same activation path accepts a validated
[`perch://pin`](../HANDOFF_PROTOCOL.md) handoff. The handoff's `source` is
untrusted metadata; URL validation, not the source label, grants entry.

### Journey 2: move between pages without multiplying browsers

1. The user opens the page switcher from the top-edge stack control.
2. The switcher shows pinned favorites and unpinned recents. Search is local and
   uses case- and diacritic-insensitive subsequence matching, so characters may
   have gaps but retain their order.
3. Hover or keyboard-select a row to reveal its pin control. The outline pin
   promotes a recent page to a favorite; the filled pin removes that favorite
   and returns it to recents. This changes favorite membership without
   activating a different page. Seven favorites is the maximum; an eighth
   attempt reports “Unpin a page first.”
4. Choosing the already-active row dismisses the popover without navigation.
   Choosing another row activates its saved page reference and restoration.
5. The one live WebKit view preserves the outgoing page's in-process
   interaction state when possible, then restores or loads the chosen page.
6. The selection is recorded as a visit so the latest active page can be
   restored later; it does not silently promote the page to a favorite.

### Journey 3: stash, peek, resize, and return

1. The stash button, menu-bar contextual command, panel close action, or a tap
   of the panel shortcut toggles between the visible panel and the edge handle.
2. Stashing records the logical panel frame, chooses the nearest edge, presents
   the handle, notifies the browser lifecycle that the panel hid, and removes
   the full panel from view.
3. Clicking the handle, choosing **Show Perch**, or tapping the shortcut
   restores the retained panel. Holding the panel shortcut while stashed
   temporarily peeks the panel and stashes it again on release.
4. Applying a built-in or custom size asks the panel coordinator to resize the
   existing panel. A stashed panel is restored to apply the size. The saved
   preferred dimensions remain distinct from temporary clamping on a small
   display.

The panel and handle intentionally use all-Spaces floating roles. Persistent
overlay behavior is part of the product, not an `NSPanel` defect.

### Journey 4: capture a thought and optionally deliver it

1. The toolbar `+` and the app's **Quick Capture** command open the Quick
   Capture editor directly.
2. The default global capture shortcut, `Command-Shift-N`, is a separate trusted
   route. If clipboard prefill is enabled, the runtime reads text from the
   clipboard at invocation. If insertion at the saved Notion cursor is also
   enabled and a nonempty prefill plus live WebKit session are available, it
   first attempts direct insertion into that saved cursor. A successful insert
   does not open Quick Capture; a missing or stale cursor, failed insertion, or
   unavailable live session falls back to the editor with the text prefilled.
   With insertion disabled—or without clipboard text—the shortcut opens the
   editor, using a clipboard prefill when one was read.
3. The editor saves changes locally. An acknowledgement means local persistence
   accepted the draft; it does not mean Notion has received it.
4. Closing an empty capture discards it. Closing a nonempty capture first saves
   a fresh snapshot.
5. If a default destination and usable personal token exist, the saved draft is
   placed in a durable delivery outbox and background delivery is triggered.
   The destination may create a child page or a data-source entry.
6. If either setting is missing, the close flow keeps the work and directs the
   user to configuration rather than pretending delivery succeeded. Offline
   work likewise remains local for later delivery.

The token is optional for the core live-page experience. When the user chooses
API-backed capture, Settings validates an `ntn_…` personal token, stores it in
this Mac's device-only Keychain item, and uses the user's own Notion
permissions. See the capture flow in the
[architecture map](ARCHITECTURE_MAP.md#flow-4--capture-delivery-from-editor-to-notion).

**Manual-verification label:** the sequence above is source-backed, but claims
that the panel stays editable across Spaces, survives focus changes, and
returns without a visible reload must be exercised in the
[manual test matrix](../MANUAL_TEST_MATRIX.md). Network delivery also requires
a real account, permissions, destination, and connection.

## Deep dive

### User action to subsystem map

The useful debugging question is not “which file draws this pixel?” but “which
subsystem owns the result of this intent?” A view collects intent; ownership
usually moves inward.

| User action | Immediate surface | Result-owning path | Durable or external effect |
|---|---|---|---|
| Launch the app | App lifecycle | `AppDelegate` selects accessory policy; startup/runtime restores services and the saved working set | Saved page and preferences may be read |
| Enter a Notion URL | Settings or Pin Page | URL input → `AppRuntime` → pin coordinator → panel coordinator → `NotionWebSession` | Valid activation is recorded as a visit; a new page appears in recents |
| Open `perch://pin` | Launch Services handoff | `AppDelegate` → runtime → strict external-route parser → normal activation path | Same page recording as typed input; untrusted routes are rejected |
| Edit the visible page | Embedded Notion UI | `PiPChromeView` hosts the retained `NotionWebSession` view | Notion owns remote page editing through its web session |
| Switch pages | Page-switcher popover | `PageSwitcherController`/matcher → runtime activation → WebKit session | Active/recent order and durable restoration are saved |
| Pin or unpin a favorite | Pin control or accessibility action on a switcher row | `PageSwitcherView` → `PageSwitcherController.setPinned` → page repository | The row moves between pinned favorites and recents; the active page need not change |
| Stash or restore | Panel control, shortcut, status menu, or handle | Runtime/pin coordinator → `PiPPanelCoordinator` → stash policy and handle controller | Presentation geometry/preferences remain local |
| Apply a size | PiP/status menu or Settings | `PanelSizeController` → panel coordinator | Presets and last explicit working size use local preferences |
| Press toolbar `+` or choose the app command | PiP control or app command | App command → capture presenter → local editor session → capture repository | A nonempty configured capture enters the outbox, then API delivery |
| Press the global capture shortcut | Registered shortcut | Runtime reads trusted settings and optional clipboard text → saved-cursor WebKit insertion attempt → capture presenter fallback | Successful insertion edits the live page directly; fallback creates a local draft that may later enter the outbox |
| Connect a token | Settings secure field | Runtime/connection controller → credential vault | Device-only Keychain item; never WebKit cookies or page URLs |
| Hide the menu-bar icon | Settings toggle | Runtime preference → `StatusItemController` observation | Preference persists; failure of the panel shortcut temporarily forces a safe icon fallback |
| Open page in browser | Notion mark in top controls | `NotionWebSession` asks macOS to open the canonical URL, then stashes the panel | Launch Services behavior is manual; the saved PiP page remains available |

Follow these paths through the canonical
[subsystem ownership map](ARCHITECTURE_MAP.md#subsystem-and-ownership-map). A
view should not implement URL trust, repository transitions, panel geometry, or
credential storage merely because it contains the initiating button.

### Exact limits worth remembering

- The working set retains at most seven pinned favorites and seven unpinned
  recents. Attempting an eighth favorite produces “Unpin a page first.”
- The PiP content minimum is 360 × 420 points when space permits. Panel size
  preferences include Compact, Comfortable, Wide, and up to twelve custom
  presets; actual usable screen geometry can clamp a requested size.
- The menu-bar item is visible by default, but the saved preference may hide it.
  If panel-shortcut registration fails, the app temporarily forces the icon
  visible so the accessory app remains reachable.
- Accepted external page URLs and handoffs are narrowly validated. The
  [handoff protocol](../HANDOFF_PROTOCOL.md) documents exact hosts, fields, and
  sanitization rules.

## Common misconceptions and failure modes

| Misconception or symptom | Correct product model | First check |
|---|---|---|
| “The app crashed because it is not in the Dock.” | Accessory/no-Dock behavior is intentional. | Look for the panel or default-visible menu-bar icon; use the panel shortcut. |
| “An all-Spaces panel is an `NSPanel` bug.” | The panel and stash handle deliberately join all Spaces as floating auxiliary UI. | Compare [`WindowRolePolicy.swift`](../../Sources/Perch/Platform/WindowRolePolicy.swift) with the [manual matrix](../MANUAL_TEST_MATRIX.md). |
| “Every pinned page has its own live browser.” | One `WKWebView` is reused; saved pages have snapshots and restoration, not permanent browser instances. | Distinguish live interaction state from durable URL/scroll state. |
| “Switching back must reproduce every detail after relaunch.” | Rich WebKit state is process-local; cross-launch restoration is URL plus best-effort scroll. | Confirm whether the process relaunched or the view was evicted. |
| “The `+` button immediately pins a blank live page.” | The README sentence making that claim is inconsistent with this snapshot. In committed UI, `+` opens Quick Capture; favorites are managed by the page-switcher pin control. | Use the source-authority callout, then check Quick Capture status or the switcher row. |
| “`Command-Shift-N` always opens Quick Capture.” | The toolbar/app command does; the global shortcut may instead insert clipboard text at a saved live-Notion cursor when both trusted options are enabled, falling back to Quick Capture if insertion cannot complete. | Check both Trusted Quick Capture settings and whether a usable saved cursor and clipboard value exist. |
| “Saved means delivered to Notion.” | Editor acknowledgement means locally saved. Delivery is a separate, retryable stage. | Inspect the service/outbox status rather than assuming remote success. |
| “Notion sign-in supplies the API token.” | Browser cookies and the optional personal API token are separate credentials. | Sign in inside the live view; configure the token only in Settings if using API-backed capture. |
| “Hiding the menu-bar icon can strand the app.” | The edge handle and registered shortcut remain access paths; shortcut failure forces the icon visible. | Read the explanatory Settings message and retry shortcut registration. |
| “A unit test proves full-screen and multi-display behavior.” | Window-server, Spaces, focus, login-session, and Launch Services integration are manual-verification boundaries. | Run the relevant [manual test row](../MANUAL_TEST_MATRIX.md). |

## Presenter notes

### Suggested 45-minute pacing

- **0–5 min — Hook:** ask learners how many steps it takes to move a fleeting
  thought into their current Notion page. Introduce the open-notebook metaphor.
- **5–11 min — Foundation:** contrast accessory, panel, WebKit view, and Space.
  Draw the three-state model: live browser, durable page, presentation.
- **11–19 min — Demo:** show one live page, hover controls, activate a recent
  page, use its pin/unpin control, and select the active row. Narrate that
  activation records a visit while the pin control manages favorites, and that
  only one live `WKWebView` exists.
- **19–25 min — Demo:** stash to the edge, restore from the handle, apply a size,
  and point out the missing Dock icon plus optional menu-bar presence.
- **25–32 min — Demo:** open Quick Capture with `+`, then contrast the global
  shortcut's optional clipboard/saved-cursor route. Type a note and distinguish
  local save from delivery. Show trusted-capture and token/destination Settings
  without exposing private content or a real token.
- **32–37 min — Map:** use the user-action table to trace one action across UI,
  runtime, platform, and persistence/service ownership.
- **37–42 min — Knowledge check:** let learners answer before revealing the
  supplied answers.
- **42–45 min — Exercise and recap:** classify actions and mark manual-only
  observations.

### Demo safety and recovery

- Prepare a non-sensitive demonstration page and sign in before presenting.
- Never project a password, cookie, or token. A placeholder token is sufficient
  to explain the Settings surface.
- If the panel appears absent, check the menu bar, edge handle, and panel
  shortcut before calling it a crash.
- If focus, full-screen, or multi-display behavior differs, label the result as
  a manual observation and record it against the
  [manual matrix](../MANUAL_TEST_MATRIX.md); do not improvise an architecture
  claim from one machine.
- If network access fails, use the offline banner to reinforce that Quick
  Capture saves locally and delivery is separate.

**Presenter emphasis:** the surprising idea is not “Notion in a small window.”
It is continuity across native presentation changes while maintaining clear
trust and ownership boundaries.

## Knowledge check

Try to answer before expanding the supplied answers below.

1. Why does Perch not appear in the Dock?
2. Does switching among seven favorites create seven live `WKWebView` objects?
3. What survives a relaunch when rich WebKit interaction state does not?
4. Name three ways to restore a stashed panel.
5. How does activating a page differ from pinning it as a favorite?
6. How can `Command-Shift-N` behave differently from toolbar `+`?
7. What does “Saved” in Quick Capture prove, and what does it not prove?
8. When is the personal Notion token required, and where is it stored?
9. Which product claims in this lecture still need manual verification?

### Answers

1. It deliberately uses the macOS accessory activation policy. The panel,
   optional menu-bar item, shortcut, and edge handle are its access paths.
2. No. The app owns at most one live Notion `WKWebView` and switches that view
   among saved page references.
3. A validated last URL plus durable, best-effort scroll restoration; otherwise
   the canonical URL and natural scroll position are used.
4. Click the edge handle, choose **Show Perch** from the menu-bar item, or
   tap the panel show/hide shortcut. A held shortcut can also provide a
   temporary peek while stashed.
5. Activation displays the page and records its visit, placing a new page in
   recents. Pinning is a separate page-switcher row action that promotes a
   recent page to a favorite; unpinning removes it from favorites.
6. Toolbar `+` opens Quick Capture directly. The global shortcut may read
   clipboard text when prefill is enabled and, when saved-cursor insertion is
   also enabled, first try to insert it into the live Notion page. Success skips
   Quick Capture; failure or unavailable prerequisites opens the editor,
   retaining the prefill when one was read.
7. It proves the editor change reached local persistence. It does not prove
   enqueueing, network delivery, or Notion acceptance.
8. It is required for API-backed destination search and Quick Capture delivery,
   not for the live embedded Notion page. It is stored device-only in Keychain.
9. Real Dock/accessory presence, Spaces and full-screen behavior, Mission
   Control/window cycling, focus, multi-display geometry, and Launch Services
   opening require the manual matrix; real Notion delivery also needs account,
   permission, destination, and network integration.

## Hands-on exercise

### Exercise: narrate two interruptions

Work from the source links; running the app is optional.

**Scenario A:** You are editing a deeply scrolled project page in the PiP. You
switch to a recent research page, stash the panel, restore it from the handle,
apply the Wide preset, and switch back.

**Scenario B:** With both Trusted Quick Capture options disabled, you press
`Command-Shift-N`, write a nonempty note while offline, see it save locally,
and close the capture. A destination and usable token were configured earlier.

For each scenario, write:

1. the immediate user-facing surface for each action;
2. the subsystem that owns each transition;
3. the state expected to remain live, durable, or presentation-only;
4. one expected observation that automated tests cannot fully prove.

Use [`PiPChromeView.swift`](../../Sources/Perch/Views/PiPChromeView.swift),
[`PiPPanelCoordinator.swift`](../../Sources/Perch/Platform/PiPPanelCoordinator.swift),
the [page activation flow](ARCHITECTURE_MAP.md#flow-2--page-activation-and-webkit-navigation),
the [stash flow](ARCHITECTURE_MAP.md#flow-3--stashrestore-presentation), and the
[capture flow](ARCHITECTURE_MAP.md#flow-4--capture-delivery-from-editor-to-notion).

### Expected answers and observations

**Scenario A:** the page-switcher popover sends the selection through the
page-switcher controller and runtime to `NotionWebSession`; stashing and handle
restoration belong to `PiPPanelCoordinator`; applying Wide begins in
`PanelSizeController` and resizes through the panel coordinator. There is one
live browser view. In-process interaction snapshots may restore page history
and scroll, the active/working-set record and URL/scroll fallback are durable,
and visible/stashed state plus geometry are presentation concerns. Manually
verify that the same editable session returns across the active Spaces without
a visible reload and that resizing preserves selection.

**Scenario B:** the global capture shortcut reaches the runtime capture action.
Because clipboard prefill and saved-cursor insertion are explicitly disabled in
this scenario, it opens the Quick Capture presenter without attempting direct
Notion insertion. The local editor collects input and the capture repository
owns the acknowledged local draft. On close, the lifecycle coordinator saves a
fresh snapshot and enqueues it for the configured destination; delivery remains
retryable until the network returns. The draft and outbox record are durable,
while the capture window's visibility is presentation state. If the trusted
options were enabled instead, the runtime could read clipboard text and first
attempt saved-cursor insertion, falling back to the prefilled editor. Manually
verify the global shortcut/focus behavior and, with a safe test workspace, that
the queued item eventually reaches the chosen Notion destination exactly as the
service status reports.

If your answer assigns Keychain storage to a SwiftUI view, gives each page its
own WebKit view, or treats “Saved” as remote delivery, revisit the
[subsystem ownership map](ARCHITECTURE_MAP.md#subsystem-and-ownership-map).

## Recap

Perch is an open notebook, not a replacement for Notion. It combines an
intentional accessory/no-Dock process with a floating, all-Spaces panel that
hosts one live Notion web view. Page switching, stashing, and sizing preserve
continuity at different state boundaries. Quick Capture is local-first and
uses an optional, Keychain-held token only when API-backed destination search
and delivery are desired.

The durable mental model is:

```text
user intent → UI surface → owning subsystem → local state → optional external effect
```

Use the [architecture map](ARCHITECTURE_MAP.md) to continue from this product
model into runtime flows, and use the [course syllabus](README.md) to choose the
next lecture. Remember that intentional policy in source and observed macOS
behavior are different kinds of evidence: the latter remains explicitly
manual wherever the window server, Spaces, focus, login session, or Launch
Services participates.
