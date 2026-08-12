# Product research: making Perch a better thinking surface

**Issue:** SUJ-12
**Prepared:** 2026-07-30
**Decision horizon:** the next three product experiments

> Superseded product direction (August 10, 2026): Quick Capture was removed.
> The `+` action now hands page creation to the native Notion app. This report
> remains as historical research, not a description of the current product.

## Executive summary

Perch's strongest thesis is not “Notion in a smaller window.” It is:

> Keep the one piece of a person's workspace that matters *right now* close
> enough to consult or change without breaking their flow.

The product already has the hard foundation for that thesis: a real Notion page
in a persistent, all-Spaces panel; an edge stash; a global shortcut; pinned and
recent pages; and durable Quick Capture with a chosen Notion destination. The
next step should be to reduce the cost of the two jobs that happen repeatedly
while someone works elsewhere:

1. **Glance:** consult a live reference, checklist, brief, or running note.
2. **Deposit:** put a thought, link, or selection into the right place and get
   back to work.

The best near-term direction is therefore **Context Dock**, not a broad Notion
client. Make one live page exceptionally easy to summon, read, edit, and put
away; then make capture feel instantaneous and trustworthy. Test these changes
in this order:

1. **Peek interaction:** press-and-hold the existing global shortcut to reveal
   the panel near its saved edge, then return it to its prior state on release.
2. **Instant capture:** a separate shortcut opens a focused capture surface,
   prefilled from an explicitly copied selection or URL, with fast save and
   unambiguous queued/sent feedback.
3. **Lightweight context slots:** user-named page slots bound to shortcuts, only
   after evidence shows that switching among the existing pinned/recent set is
   a frequent pain.

Avoid multiple simultaneous panels, automatic app-aware switching, ambient
screen/clipboard collection, and a native reimplementation of Notion. They
increase interruption, privacy risk, and product complexity while weakening
the “one calm surface” promise.

## 1. Scope and method

This is a desk-research and product-strategy report, not a usability finding.
It combines:

- a review of the current repository and documented behavior;
- pattern research across picture-in-picture, launchers, clipboard managers,
  scratchpads, web clippers, and native Notion navigation;
- a jobs-to-be-done decomposition;
- hypothesis ranking by expected user value, fit with the thesis, confidence,
  and implementation/operational cost.

No users were interviewed and no production analytics, support corpus, market
size, or competitor conversion data was available. Assertions below are
therefore hypotheses to validate, not claims about observed user behavior.
Linked sources were selected for first-party product behavior where possible.
The browsing environment was unavailable while this report was prepared, so
links should be rechecked before quoting them externally; no source code or
third-party prose was copied.

## 2. The product today

### Existing strengths

| Capability | Why it matters to the thesis |
| --- | --- |
| One live `WKWebView` page | The panel is the real workspace, not a lossy viewer or duplicate data store. |
| Always-on-screen, all-Spaces panel | A working page remains visually and spatially close while the primary app changes. |
| Edge stash and slim restore handle | Persistence does not have to mean permanent obstruction. |
| Global shortcut and optional menu-bar item | The page is recoverable without Dock or app-switcher navigation. |
| Seven pinned and seven recent pages with local search | A bounded working set prevents the accessory from becoming a second workspace browser. |
| Panel size presets | Different page roles can have useful, repeatable footprints. |
| Quick Capture, local draft state, outbox, retry, and explicit destination | Capture can survive network or API failure rather than demanding a perfect online moment. |
| Notion URL handoff and clipboard pinning | Other tools can intentionally send a page into the persistent surface. |

These capabilities imply an important strategy constraint: improve the
*transition* between the user's primary work and Perch before adding more
Notion surface area.

### Core frictions to investigate

These are inferred from the interaction model and should be validated:

1. **Persistent visibility competes with screen space.** The stash solves the
   resting state, but restoring, focusing, consulting, and re-stashing may still
   be too much ceremony for a two-second glance.
2. **One shortcut carries several meanings.** “Bring my page back,” “put it
   away,” and “let me type a thought” are distinct intentions. A toggle is
   simple to learn but can require cleanup after a momentary action.
3. **Capture asks for a context change before it earns trust.** The current
   system has strong delivery infrastructure, but the experience must prove
   that a note can be deposited quickly and safely without watching it arrive.
4. **A bounded working set still requires recall.** Page switching is useful,
   but titles and recency do not always express roles such as “today,” “meeting
   notes,” or “project brief.”
5. **The embedded full web app can be visually dense at PiP sizes.** This is the
   cost of fidelity. The right response is better sizing and access—not a
   speculative native Notion renderer.

## 3. Jobs to be done

### Primary job: keep context in reach

> When I am doing focused work in another app, help me keep the relevant Notion
> page close enough to consult or update, so I do not lose my place by navigating
> through windows and workspace hierarchy.

Success means less time and attention spent between deciding to use the page
and seeing the relevant content.

### Secondary job: deposit a thought without opening a loop

> When a thought, decision, link, or excerpt appears, let me put it into my
> Notion system with confidence, so I can continue the task that produced it.

Success means the user can leave immediately and trust local persistence,
delivery status, and recovery.

### Supporting job: change the active context deliberately

> When my focus changes, let me replace the nearby page with the next useful
> one, so the panel reflects my current work rather than becoming visual noise.

Success means intentional switching is fast without causing automatic,
surprising page changes.

### Emotional requirements

- **Calm:** the panel waits; it does not demand attention.
- **Trust:** typing is not lost and capture status is legible.
- **Control:** persistence, visibility, and switching are always user-directed.
- **Continuity:** page session, scroll, size, and placement feel stable.

## 4. Comparable patterns and what to learn

The useful comparison set is interaction patterns, not only direct Notion
wrappers.

### 4.1 Video picture-in-picture: spatial constancy and reversible presence

Apple's Picture in Picture keeps media above other windows and permits moving
or resizing it while work continues elsewhere. Its lesson is not “copy video
controls”; it is that a persistent companion earns its space through predictable
placement, minimal chrome, and a one-step return to the source.

**Adopt:** stable placement, momentary reveal, low-chrome resting state, obvious
dismiss/stash behavior.
**Reject:** passive-consumption assumptions. A document needs keyboard focus,
selection, scrolling, and state preservation.

### 4.2 Raycast Quicklinks and Floating Notes: invocation before navigation

Launcher interactions compress a known destination into a command and make a
scratch surface globally available. The relevant principle is that repeated
intent should become an invocation, not another browsing session.

**Adopt:** searchable commands, role-based aliases, direct shortcuts, and a
fast return to the previous app.
**Reject:** turning Perch into a general launcher or command marketplace.

### 4.3 Maccy: keyboard-first recall with privacy made explicit

Clipboard managers demonstrate the value of a compact, searchable recent set,
pinned entries, deterministic keyboard traversal, and an interaction that
disappears immediately after selection. They also show why collection and
retention must be transparent.

**Adopt:** bounded history, predictable ranking, fast keyboard selection, and
clear local-state semantics.
**Reject:** passive clipboard history. Perch should only use content the
user explicitly copies, drops, pastes, shares, or hands off.

### 4.4 Drafts and share extensions: capture first, organize later

Capture tools remove destination decisions from the moment of writing, retain
an inbox, and make routing a later action. Perch already has a default
destination and durable outbox, which is the right substrate.

**Adopt:** open directly into a focused editor, save locally first, show a terse
receipt, and allow recovery without blocking the user's return.
**Reject:** an elaborate automation/action system until the simple capture path
has demonstrated repeated use.

### 4.5 Notion Web Clipper: explicit source handoff

Web clippers package an intentional web context into a chosen workspace
destination. The useful boundary is explicit user action plus preserved
provenance (title, URL, and optionally selected text).

**Adopt:** source URL/title metadata and a preview before capture when content
is inferred.
**Reject:** background browsing observation or silent capture.

### 4.6 Notion's own navigation: preserve familiarity

Notion provides workspace search, favorites, recents, back/forward navigation,
and links. The embedded real page already inherits the editor and its evolving
behavior.

**Adopt:** complement Notion with a small working set and native Mac access.
**Reject:** rebuilding workspace search, databases, blocks, or permissions
outside the narrow capture APIs required for reliability.

### Pattern synthesis

Across these products, the winning sequence is consistent:

1. **Invoke from anywhere.**
2. **Show the smallest useful context.**
3. **Complete one known action.**
4. **Confirm invisibly or tersely.**
5. **Return the user to where they were.**

Perch is differentiated because the useful context can remain a live,
editable Notion page after step 2. That continuity—not generic capture—is the
defensible product center.

## 5. Product directions

### Direction A — Context Dock (recommended)

Treat the panel as a reversible, spatially stable extension of the current
task.

Candidate improvements:

- hold-to-peek using the existing shortcut, without changing the saved resting
  state;
- restore focus to the previously active app after a read-only peek;
- remember size and edge per display, with safe fallback after display changes;
- make “stashed,” “visible but inactive,” and “editing” distinct, predictable
  states;
- add optional role labels to pinned pages (“Today,” “Brief,” “Notes”);
- expose back/forward and switcher actions to keyboard access without persistent
  chrome.

**Why it is strong:** it directly improves the primary job and compounds the
app's existing technical strengths.
**Main risk:** keyboard focus and hold semantics can be surprising or conflict
with accessibility tools. The experiment must keep click/toggle behavior and
provide an opt-out.

### Direction B — Trusted Capture Lane (recommended second)

Make capture a separate, fast deposit path that uses the existing durable
delivery engine.

Candidate improvements:

- a configurable Quick Capture shortcut distinct from panel show/stash;
- explicit prefill actions: selected copied text, copied URL, or dragged item;
- source URL/title stored with the capture when provided;
- `Command-Return` to save locally and return immediately;
- a small “Saved locally · sending” receipt that does not steal focus;
- concise outbox access from the stash handle/menu, with retry only when needed;
- an inbox/default destination that avoids choosing a database on every use.

**Why it is strong:** it improves frequency and trust while reusing substantial
existing work.
**Main risk:** if capture becomes a modal mini-app, it breaks the flow it is
meant to protect. Time-to-type and time-to-return are the controlling metrics.

### Direction C — Named Context Slots (conditional)

Allow a few pinned pages to acquire stable roles and direct shortcuts, such as
“open Today” or “open Project Brief.”

Start with labels and command/menu actions, not automation. Consider optional
per-slot size only after observing meaningful resize friction.

**Why it might work:** role recognition is faster than remembering page titles,
and direct invocation removes the switcher step.
**Why it is conditional:** the current seven pinned/seven recent switcher may
already be sufficient. Validate switching frequency and failure first.

### Direction D — Automatic Context Following (do not build yet)

Automatically change the page based on foreground app, calendar event, browser
domain, or project folder.

This sounds powerful but violates calm and control easily. It creates privacy
questions, brittle rules, surprising navigation, and possible loss of editor
context. A manual command or URL handoff provides most of the value with much
less risk. Revisit only if users repeatedly create the same context switches
and explicitly ask to automate them.

### Direction E — Multi-panel workspace (do not pursue)

Multiple simultaneous pages would increase screen occupation, WebKit memory,
focus ambiguity, and state-restoration complexity. More importantly, it changes
the thesis from one nearby context to a window manager. Improve switching and
slots instead.

### Direction F — Native Notion client (do not pursue)

A native renderer/editor would chase a large, changing product surface and
introduce fidelity, permissions, and sync risks. Keep the real Notion page for
full interaction; use public APIs only for narrow, recoverable capture.

## 6. Prioritization

Scores are directional (1 low, 5 high). “Cost/risk” includes interaction,
engineering, privacy, and maintenance cost; lower is better.

| Idea | Thesis fit | Expected value | Confidence | Cost/risk | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| Hold-to-peek panel | 5 | 5 | 3 | 2 | Prototype now |
| Dedicated Quick Capture shortcut | 5 | 5 | 4 | 2 | Prototype now |
| Terse local-save/delivery receipt | 4 | 5 | 4 | 2 | Build with capture test |
| Explicit copied selection/URL prefill | 4 | 4 | 3 | 3 | Test after basic shortcut |
| Role labels for pinned pages | 4 | 3 | 3 | 2 | Interview/prototype |
| Direct shortcut to named slot | 4 | 3 | 2 | 3 | Gate on switcher evidence |
| Per-display placement hardening | 4 | 4 | 3 | 3 | Audit and instrument |
| Per-page size presets | 3 | 3 | 2 | 3 | Defer |
| Automatic app-aware switching | 2 | 3 | 1 | 5 | Do not build |
| Multiple live panels | 1 | 2 | 2 | 5 | Do not build |
| Native Notion renderer/editor | 1 | 2 | 1 | 5 | Do not build |

## 7. Three concrete experiments

### Experiment 1 — Hold-to-peek

**Hypothesis:** people who currently stash the panel will consult it more often
and spend less time managing it if a hold reveals it only for the duration of a
glance.

**Prototype:** behind a setting, distinguish a shortcut hold from a tap. Hold
reveals the panel without changing its saved stashed/visible state; release
returns it and restores the prior application. A tap retains today's toggle
behavior. Do not make the panel click-through.

**Study:** 5–8 existing or target users complete read, scroll, and edit tasks
across two Spaces and two displays. Compare current toggle with peek.

**Success signals:**

- median time from shortcut-down to useful content visible under 400 ms on a
  warm session;
- at least 80% of read-only tasks completed without window cleanup;
- at least 6 of 8 participants correctly predict the release behavior after
  one explanation;
- no lost keystrokes, unintended page navigation, or persistent focus trap.

**Kill/adjust criteria:** users cannot distinguish tap/hold reliably, editing
is accidentally dismissed, VoiceOver/keyboard operation regresses, or focus
restoration is inconsistent. If so, test a separate “Peek” shortcut rather
than adding timing magic.

### Experiment 2 — Capture and return

**Hypothesis:** a dedicated shortcut with local-first save will let users record
a thought in under five seconds without checking Notion afterward.

**Prototype:** shortcut → editor focused → type/paste → `Command-Return` → local
save → return to the prior app. Show “Saved locally · sending” briefly and make
failure visible later through the existing outbox; never discard the draft on
delivery failure.

**Study:** 5–8 users capture plain text, a URL, formatted text, and an offline
note. Include an ambiguous/expired Notion connection case.

**Success signals:**

- median shortcut-to-first-keystroke under 700 ms warm;
- median plain-text shortcut-to-return under 5 seconds excluding composition;
- zero lost captures across forced offline/relaunch cases;
- at least 80% correctly explain whether a simulated offline capture is safe;
- fewer than 20% reopen Notion just to verify successful delivery after the
  trust-learning tasks.

**Kill/adjust criteria:** destination setup blocks first capture, receipts steal
focus, rich-text startup misses the latency budget, or users confuse “local”
with “delivered.” Prefer a simpler plain-text fast path over hiding status.

### Experiment 3 — Roles versus search

**Hypothesis:** people with three or more recurring contexts switch faster using
named roles/direct commands than the existing pinned/recent search.

**Prototype:** a clickable Figma or instrumented lightweight build with three
optional aliases mapped to existing pins. Compare search, menu selection, and a
direct command. Do not add a second live web view.

**Study:** users bring their own realistic page titles and repeat switching
after a one-day delay.

**Success signals:**

- at least 25% lower median selection time than existing search;
- fewer selection errors after the delay;
- a majority naturally assign stable roles to at least three pages;
- slots are used across sessions rather than only configured once.

**Kill/adjust criteria:** aliases duplicate already-clear titles, users cannot
remember mappings, or configuration costs more than search saves. In that case,
improve switcher ranking and keyboard navigation instead.

## 8. Measurement plan

### North-star behavior

**Useful returns per active day:** intentional reveals that lead to a meaningful
read or edit, plus successful captures, without requiring workspace navigation.

This is a behavioral direction, not a complete metric definition. Raw “panel
visible time” is a bad north star: a forgotten panel would score well.

### Funnel metrics

| Stage | Suggested measure |
| --- | --- |
| Reach | shortcut invocation success; handle/menu fallback use |
| Reveal | warm/cold time to visible interactive page; reveal cancellation |
| Use | scroll, editor focus, or sustained visible interval (aggregated) |
| Switch | switcher opened → page selected; time and query count |
| Capture | open → first input → local save → return; abandon rate |
| Delivery | local save → delivered; retries, age of oldest pending item |
| Recovery | successful restore after relaunch, display change, offline period |

### Guardrails

- crash-free sessions and WebKit termination recovery;
- no draft loss in failure-injection tests;
- focus returned to the intended application;
- shortcut registration failures remain recoverable;
- panel does not cover system UI or become unreachable across displays/Spaces;
- memory and CPU stay quiet while stashed and idle;
- accessibility parity for every new shortcut-only action;
- no capture of clipboard, active-app, browser, or screen data without an
  explicit user action.

### Privacy-respecting instrumentation

If analytics are added, make them opt-in during research or plainly disclosed
in product use. Record event categories, durations, outcome codes, and coarse
counts—not page URLs, titles, query strings, captured text, workspace IDs, or
Notion content. Keep local diagnostics useful without requiring telemetry.

## 9. Research questions for interviews

Avoid asking whether a feature sounds useful. Ask for recent behavior:

1. “Tell me about the last time you kept a Notion page open while working in
   another app. What was on it?”
2. “Show me how you get back to that page today.”
3. “When did a floating window last get in your way? What did you do?”
4. “Tell me about the last thought you meant to put in Notion but did not.”
5. “How do you know a quick capture is safe? Do you check it?”
6. “Which pages recur every day or week? How do you recognize them?”
7. “What information would you never want a helper to observe automatically?”
8. “What changes when you use multiple monitors, full-screen apps, or Spaces?”

Recruit a mix of writers/researchers, designers, developers, project leads, and
people who already use Notion as a daily system. Include both one-display and
multi-display workflows and at least two accessibility-tool users before
shipping shortcut timing or focus changes.

## 10. Recommended sequence

### Now: validate the thesis at the interaction boundary

1. Instrument performance locally and establish warm/cold reveal baselines.
2. Conduct 5–8 current-state workflow interviews with screen sharing.
3. Prototype hold-to-peek behind a setting and run the task study.
4. Prototype a separate capture shortcut using existing draft/outbox behavior.

### Next: ship the smallest proven loop

If peek succeeds, harden focus, Spaces, multiple-display, VoiceOver, and
shortcut-conflict behavior before expanding it. If capture succeeds, ship
local-first save and the delivery receipt before adding metadata extraction.

### Later: improve deliberate context change

Use observed switcher telemetry and interviews to choose between better ranking,
role labels, or direct slots. Add only one mechanism. Continue to reuse a single
live web view.

### Explicit non-goals for this horizon

- multiple simultaneous PiP panels;
- background clipboard history;
- automatic foreground-app/browser/calendar monitoring;
- team collaboration or shared cursors;
- general-purpose launcher/actions platform;
- native Notion block or database editing;
- AI summarization before the core glance/capture loops are fast and trusted.

AI may become useful later for user-invoked transformations of selected
content, but it does not solve the current access and continuity problem and
would introduce cost, latency, and content-governance questions.

## 11. Decision principles

Use these to evaluate future ideas:

1. **Does it shorten the path to one relevant page or one safe deposit?**
2. **Does it preserve the user's place in both Notion and the primary app?**
3. **Is it calmer and more predictable than ordinary window switching?**
4. **Can the user explain where their content is and whether it is delivered?**
5. **Does it work with one live web session and narrow public API use?**
6. **Does it avoid observing context the user did not intentionally provide?**

If an idea fails two or more of these tests, it is probably outside the core
thesis even if it is individually attractive.

## Sources and further reading

### Product and platform documentation

- Apple, [Use Picture in Picture in Safari on Mac](https://support.apple.com/guide/safari/play-a-web-video-with-picture-in-picture-ibrw27291639/mac).
- Apple, [Work in multiple Spaces on Mac](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac).
- Notion, [Web Clipper](https://www.notion.com/help/web-clipper).
- Notion, [Navigate with the sidebar](https://www.notion.com/help/navigate-with-the-sidebar).
- Raycast, [Quicklinks](https://docs.raycast.com/raycast-core/quicklinks).
- Raycast, [Floating Notes](https://docs.raycast.com/raycast-core/floating-notes).
- Drafts, [Share Extension](https://docs.getdrafts.com/docs/extensions/shareextension).
- Maccy, [product site](https://maccy.app/).

### Repository evidence reviewed

- [`README.md`](../README.md) for the product thesis and documented behavior.
- [`OPEN_SOURCE_RESEARCH.md`](OPEN_SOURCE_RESEARCH.md) for implementation
  references, licensing constraints, and prior product conclusions.
- [`MANUAL_TEST_MATRIX.md`](MANUAL_TEST_MATRIX.md) for windowing, Spaces,
  display, focus, menu-bar, and shortcut risks.
- `Sources/Perch/App`, `Platform`, `Views`, `Services`, and `Persistence` for
  the implemented interaction and reliability surface.
- `Tests/PerchTests` for the behaviors already protected by regression
  coverage.

Links were assembled on 2026-07-30. Product behavior and documentation can
change; verify current wording before using this report as external marketing
or compliance material.
