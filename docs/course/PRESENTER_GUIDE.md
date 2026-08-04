# Notion PiP Presenter Guide

This guide turns the twelve lectures into teachable sessions. It is for a
presenter who needs exact timing, a safe demonstration plan, useful questions,
and a fallback when the room or machine disagrees with rehearsal.

Keep the [course syllabus](README.md), [glossary](GLOSSARY.md),
[architecture map](ARCHITECTURE_MAP.md), [file atlas](FILE_ATLAS.md),
[change guide](CHANGE_GUIDE.md), and
[manual test matrix](../MANUAL_TEST_MATRIX.md) open. The lecture is the source
for detail; this guide is the run-of-show.

## Timing authority

The syllabus allocations are the presenter clock:

| Lecture | Allocation |
|---|---:|
| 1 | 45 min |
| 2 | 60 min |
| 3 | 60 min |
| 4 | 75 min |
| 5 | 75 min |
| 6 | 75 min |
| 7 | 75 min |
| 8 | 75 min |
| 9 | 90 min |
| 10 | 90 min |
| 11 | 75 min |
| 12 | 90 min |

That is 885 minutes, or 14 hours 45 minutes, of instruction before breaks.
There is one known source discrepancy: [Lecture 9](09-quick-capture-editor-bridge.md)
labels itself and its embedded pacing as 75 minutes, while the
[syllabus](README.md#course-navigation) allocates 90. All schedules here use
**90 minutes**: deliver the lecture's 75-minute plan unchanged, then spend 10
minutes comparing TypeScript, native protocol, and real-WebKit evidence and 5
minutes on questions or recovery. Do not silently stretch its individual
segments.

The words **optional cut** mean material to assign as reading when a session
runs late. Never cut the takeaway, hard concept, privacy warning, debrief, or
transition.

## Presenter preparation

### Audience and prerequisite check

Send the [course prerequisites](README.md#prerequisites) in advance. At the
start, ask for a show of hands on Swift, macOS UI, WebKit, databases, and
TypeScript experience; this sets vocabulary depth, not who may participate.

Required learner preparation:

- basic programming concepts and comfort navigating a repository;
- a checkout at the same committed baseline used by the presenter; and
- the glossary open for unfamiliar Swift/macOS terms.

Hands-on native work additionally needs macOS 15.6 or newer and full Xcode 26.2
or newer at `/Applications/Xcode.app`. Node/npm is needed only for editor-source
exercises. A learner without those tools can follow source, captured output,
and paired discussion without changing their machine.

### Environment rehearsal

Run these read-only checks before the audience arrives:

```sh
git status --short
sw_vers -productVersion
test -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version
pgrep -x NotionPiP
```

Preserve unrelated work. Rehearse against committed source with
`git show HEAD:<path>` when the working tree is dirty. If you need a staged app,
save active capture work, quit Notion PiP, and only then run:

```sh
./script/build_and_run.sh --verify
```

The script terminates running `NotionPiP` processes. A pre-existing
`node_modules` directory also makes it regenerate the checked-in editor asset;
understand and review that condition before the session. Prepare a source-only
route and captured successful output so a build is never the sole teaching
path.

### Privacy and account preparation

- Use a presenter-controlled workspace and disposable, non-sensitive pages.
- Sign in through the embedded Notion UI before projection. Never display or
  request a password, cookie, session token, Keychain item, or personal
  integration token.
- Demonstrate token settings with placeholder text or an already-obscured
  field. Do not paste a token into source, tests, logs, slides, chat, or shell
  history.
- Disable notification previews and close unrelated tabs, logs, and recovery
  exports. Clear terminal scrollback containing personal paths or content.
- Use synthetic URLs, capture JSON, Notion blocks, and delivery errors. If a
  remote write is essential, target a disposable page and clean it up later.

### Accessibility and room preparation

- Increase editor and terminal font sizes; verify contrast on the projector,
  not only the laptop display.
- Caption spoken questions, read diagram labels and arrow direction aloud, and
  provide prose fallbacks from the architecture map.
- Rehearse keyboard-only navigation and, when in scope, VoiceOver and Full
  Keyboard Access. State the exact macOS/display/accessibility environment for
  every manual observation.
- Avoid relying on hover, color, animation, or a laser pointer as the only
  carrier of meaning. Describe state changes in words.
- Ask before enabling sound, motion-heavy window changes, or screen
  magnification. Give learners a text exercise alternative to every live UI
  demo.

### Demo kit

Prepare these tabs in order: the current lecture, its first code entry, the
matching architecture-map flow, the nearest focused test, and the manual
matrix. Keep a known-good committed build, screenshots or short recordings,
and captured test/build output available. Record the expected observation for
each demo; a command without an expected observation is not a teaching plan.

## Six-session paired schedule

This is the recommended cohort format: **16 hours 15 minutes** including one
15-minute break per session. Learners should complete each session's exercise
before the next meeting.

| Session | Run time | Prerequisites | Lecture blocks and break | Demonstration | Exercises |
|---|---:|---|---|---|---|
| 1 — Product and repository | 2 h | Basic programming; checkout ready | [L1](01-product-and-user-experience.md) 45 min → break 15 min → [L2](02-repository-and-technology-stack.md) 60 min | Product journey, then source → target → staged bundle | Narrate two interruptions; classify a proposed directory |
| 2 — Lifecycle and composition | 2 h 30 | Session 1; basic callbacks/state | [L3](03-application-lifecycle.md) 60 min → break 15 min → [L4](04-composition-and-runtime.md) 75 min | `main()` to event loop; then construct the dependency graph | Annotate one event-loop trace; audit a command and degraded branch |
| 3 — Panel and live browser | 2 h 45 | Sessions 1–2; AppKit/WebKit terms from glossary | [L5](05-panel-stashing-and-controls.md) 75 min → break 15 min → [L6](06-webkit-notion-session.md) 75 min | Stash/restore and shortcut timeline; then warm/switch/renderer session states | Predict three panel changes; classify WebKit restoration lifetimes |
| 4 — Domain and persistence | 2 h 45 | Sessions 1–3; value/actor basics | [L7](07-domain-modeling-and-policies.md) 75 min → break 15 min → [L8](08-persistence-and-restoration.md) 75 min | Canonical URL/working-set policy; then migration and atomic repository tests | Design a trusted recent-page handoff; place a field and audit a transaction |
| 5 — Editor and delivery | 3 h 15 | Sessions 1–4; TypeScript/HTTP overview | [L9](09-quick-capture-editor-bridge.md) 90 min → break 15 min → [L10](10-notion-api-and-delivery.md) 90 min | Delay a bridge acknowledgement; then trace a 201-block delivery journal | Diagnose a lost New-note acknowledgement; prove reliability with fakes |
| 6 — UI and maintenance | 3 h | Sessions 1–5; XCTest concepts | [L11](11-views-settings-and-state.md) 75 min → break 15 min → [L12](12-testing-debugging-and-change-workflow.md) 90 min | Find four hosting roots; then choose evidence for three failures | Design a persisted setting; run the domain/UI/cross-language investigations |

Open each meeting with a five-minute retrieval question from the prior
lecture, inside the first lecture's allocation. End with the paired lecture's
debrief and assign its exercise rather than adding unbudgeted discussion.

## Twelve standalone sessions

Use this format for weekly teaching or independent teams. Instruction time is
the syllabus duration; the break column is recovery time after the session and
is not included in that duration.

| Session | Duration | Prerequisite | Primary demo | Exercise | Break / recovery |
|---|---:|---|---|---|---|
| [Lecture 1](01-product-and-user-experience.md) | 45 min | Basic programming | One page → stash → capture | Narrate two interruptions | 10 min after |
| [Lecture 2](02-repository-and-technology-stack.md) | 60 min | Lecture 1 | Tree, manifests, build stages | Classify a proposed directory | 10 min after |
| [Lecture 3](03-application-lifecycle.md) | 60 min | Lectures 1–2 | `main()` → run loop → termination | Annotate one event trace | 10 min after |
| [Lecture 4](04-composition-and-runtime.md) | 75 min | Lecture 3 | Composition graph and relays | Audit command/failure paths | 15 min after |
| [Lecture 5](05-panel-stashing-and-controls.md) | 75 min | Lecture 4 | Window roles, stash, shortcut timing | Classify/predict panel changes | 15 min after |
| [Lecture 6](06-webkit-notion-session.md) | 75 min | Lecture 5 | Warm hide, switch, renderer recovery | State-lifetime classification | 15 min after |
| [Lecture 7](07-domain-modeling-and-policies.md) | 75 min | Lecture 4; value semantics | Canonical URL and policy test | Trusted handoff design | 15 min after |
| [Lecture 8](08-persistence-and-restoration.md) | 75 min | Lecture 7; actor basics | Migration/reopen and atomic enqueue tests | Field placement and transaction audit | 15 min after |
| [Lecture 9](09-quick-capture-editor-bridge.md) | 90 min normalized | Lecture 8; TypeScript basics | Delayed native reply and exact retry | Lost-ack diagnosis | 15 min after |
| [Lecture 10](10-notion-api-and-delivery.md) | 90 min | Lectures 8–9; HTTP basics | Close → outbox → journaled delivery | Reliability proof with fakes | 15 min after |
| [Lecture 11](11-views-settings-and-state.md) | 75 min | Lectures 4–10 | Hosting roots and settings trace | Add a persisted setting safely | 15 min after |
| [Lecture 12](12-testing-debugging-and-change-workflow.md) | 90 min | All prior lectures | Focused test → bundle/manual ladder | Three bounded investigations | 15 min after |

For a truly standalone audience, spend the first five minutes inside the
allocation recapping the prerequisite in the card's hook and point learners to
the glossary rather than attempting the entire earlier lecture.

## Two-day intensive schedule

This format delivers every syllabus minute rather than compressing the course.
Day 1 is 8:30–17:45; Day 2 is 8:30–17:00. Require the repository/toolchain check
before arrival and assign Lecture 1's product overview as optional pre-reading
for learners completely new to macOS.

### Day 1 — product through domain

| Time | Block | Demo / exercise |
|---|---|---|
| 08:30–09:15 | Lecture 1 (45 min) | Product journey; interruption narration |
| 09:15–10:15 | Lecture 2 (60 min) | Repository/build tour; directory classification |
| 10:15–10:30 | Break | Stop screen sharing; questions on cards |
| 10:30–11:30 | Lecture 3 (60 min) | Event-loop trace; callback annotation |
| 11:30–12:45 | Lecture 4 (75 min) | Composition graph; command/failure audit |
| 12:45–13:30 | Lunch | Do not use lunch to repair demos in public |
| 13:30–14:45 | Lecture 5 (75 min) | Panel/stash demo; change predictions |
| 14:45–15:00 | Break | Reset displays and focus before WebKit |
| 15:00–16:15 | Lecture 6 (75 min) | Session states; restoration exercise |
| 16:15–16:30 | Break | Privacy check before example URLs/content |
| 16:30–17:45 | Lecture 7 (75 min) | Policy/test demo; trusted-handoff exercise |

Day 1 prerequisites: checkout, basic programming, and the glossary. Native
build participation requires the supported macOS/Xcode host; observation does
not. End by assigning the persistence schema table as a ten-minute Day 2
warm-up.

### Day 2 — persistence through maintenance

| Time | Block | Demo / exercise |
|---|---|---|
| 08:30–09:45 | Lecture 8 (75 min) | Migration/transaction tests; field placement |
| 09:45–10:00 | Break | Open TypeScript/native protocol tabs |
| 10:00–11:30 | Lecture 9 (90 min normalized) | Bridge acknowledgement; lost-ack exercise; evidence comparison |
| 11:30–13:00 | Lecture 10 (90 min) | Journaled delivery; fake-transport reliability exercise |
| 13:00–13:45 | Lunch | Clear any remote demo data privately |
| 13:45–15:00 | Lecture 11 (75 min) | Hosting/state traces; new-setting exercise |
| 15:00–15:15 | Break | Reset terminal and choose final investigation |
| 15:15–16:45 | Lecture 12 (90 min) | Evidence ladder; three investigations |
| 16:45–17:00 | Course close | Apply the change guide to one audience proposal |

Day 2 prerequisites: Day 1, actor/value vocabulary, and a conceptual
understanding of JSON and HTTP. Node is optional unless participants run the
web exercises. The course close uses the [change guide's owning layers](CHANGE_GUIDE.md#choosing-the-owning-layer),
not a live product edit.

## Lecture run sheets

Each card is a minimum viable delivery contract. Use the linked lecture for
full pacing, answers, and code context.

### Lecture 1 — Product and User Experience (45 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Ask, “How many context switches does a fleeting thought take before it reaches the Notion page you are using?” |
| Takeaway | Notion PiP is continuity across native presentation changes, not merely a small browser. |
| Hard concept | Separate one live browser, durable page identity/state, and visible/stashed presentation. |
| Diagram cue | Draw the three-state model, then point to architecture-map [page activation](ARCHITECTURE_MAP.md#flow-2--page-activation-and-webkit-navigation), [stash](ARCHITECTURE_MAP.md#flow-3--stashrestore-presentation), and [capture](ARCHITECTURE_MAP.md#flow-4--capture-delivery-from-editor-to-notion) flows. |
| Code-tour entry | Start at [`PiPChromeView.swift`](../../Sources/NotionPiP/Views/PiPChromeView.swift), then follow actions into `AppRuntime`. |
| Demo steps | 1. Show one page and hover controls. 2. Switch and pin/unpin a page. 3. Stash/restore and resize. 4. Open Quick Capture and distinguish local save from delivery. |
| Audience question | “Which state should survive a hidden panel, and which should survive a process restart?” |
| Misconception to surface | No Dock icon does not mean a crash; accessory activation and the all-Spaces panel are intentional. |
| Debrief | Ask learners to narrate the page, panel, and capture states without framework names. |
| Transition | “Now that we know the experience, where do its authored files and runtime artifacts live?” |
| Optional cut | Skip detailed trusted-capture options; retain the privacy boundary and local-first capture. |

### Lecture 2 — Repository and Technology Stack (60 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Put one source file, one resource, one app bundle, and one running process on screen and ask which can be edited. |
| Takeaway | SwiftPM owns the native target/resources; TypeScript authors the checked-in editor bundle; the script stages and ad-hoc signs the app. |
| Hard concept | Distinguish authored source, generated-but-checked-in `editor.js`, ignored build output, bundle resources, and a launched process. |
| Diagram cue | Draw `Sources + Web → SwiftPM/esbuild → .build → dist/NotionPiP.app → process`. |
| Code-tour entry | Open [`Package.swift`](../../Package.swift), [`package.json`](../../package.json), then [`build_and_run.sh`](../../script/build_and_run.sh). Use the [file atlas](FILE_ATLAS.md) for unfamiliar paths. |
| Demo steps | 1. Classify the top-level tree. 2. Locate the copied resource. 3. Trace build, plist, resource copy, entitlements, signing, and launch. 4. Inspect an existing bundle read-only if available. |
| Audience question | “Why can a fresh clone run without Node, while a checkout with `node_modules` may invoke npm during the build?” |
| Misconception to surface | Ad-hoc signed is development-ready, not Developer ID signed or notarized. |
| Debrief | Have learners name the authoritative authoring file for one Swift behavior and one editor behavior. |
| Transition | “A staged executable is inert until macOS enters its event loop—what actually starts next?” |
| Optional cut | Skip the live `dist` inspection; keep the source-to-bundle trace. |

### Lecture 3 — Application Lifecycle (60 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Ask what statement runs “after” `NSApplication.run()` in an event-driven program. |
| Takeaway | `main()` constructs and enters the loop; delegates, buffered routes, startup work, and deferred termination drive later behavior. |
| Hard concept | Ordering main-actor UI work with actor calls, cancellation/generation guards, early URL delivery, and `.terminateLater`. |
| Diagram cue | Draw `main()` ending at the run loop, with launch, URL, and quit callbacks entering from the side; use architecture [Flow 5](ARCHITECTURE_MAP.md#flow-5--terminationautosave-coordination) for termination. |
| Code-tour entry | [`NotionPiPApp.swift`](../../Sources/NotionPiP/App/NotionPiPApp.swift) → [`AppDelegate.swift`](../../Sources/NotionPiP/App/AppDelegate.swift). |
| Demo steps | 1. Number `main()`. 2. Follow `AppStartup.start`. 3. Trace a URL arriving before readiness. 4. End at the termination reply after local preservation. |
| Audience question | “What prevents startup restoration from overwriting a newer user activation?” |
| Misconception to surface | Creating `Task {}` from main-actor code does not automatically make UI state unisolated or detached. |
| Debrief | Ask the room to identify the owner, ordering guard, and cancellation point for one callback. |
| Transition | “Lifecycle tells us when work begins; composition tells us which object receives it.” |
| Optional cut | Defer cold-launch signpost detail to Lecture 12. |

### Lecture 4 — Composition and Runtime (75 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Ask, “If every feature needs every other feature, who is allowed to know the concrete graph?” |
| Takeaway | `AppComposition` constructs concrete dependencies; `AppRuntime` is a main-actor facade; narrow protocols and relays keep ownership explicit. |
| Hard concept | Distinguish call direction from lifetime ownership, especially cycle-breaking relays and degraded persistence construction. |
| Diagram cue | Build architecture [Flow 1](ARCHITECTURE_MAP.md#flow-1--startup-and-dependency-composition) in three passes: concrete boxes, protocol edges, dotted callbacks. |
| Code-tour entry | Start at `AppComposition` in [`NotionPiPApp.swift`](../../Sources/NotionPiP/App/NotionPiPApp.swift), then [`AppRuntime.swift`](../../Sources/NotionPiP/App/AppRuntime.swift). |
| Demo steps | 1. Number construction phases. 2. Branch success/failure container graphs. 3. Follow command and switcher relays. 4. Trace forwarded controller observation into Settings. |
| Audience question | “Why is a relay preferable to capturing a not-yet-initialized runtime or introducing a service locator?” |
| Misconception to surface | The runtime coordinates the system; it does not own AppKit mechanics, SwiftData mutation, or HTTP transport. |
| Debrief | Give three objects and ask who constructs, retains, and calls each. |
| Transition | “With the graph in place, we can study the strangest retained platform object: the PiP panel.” |
| Optional cut | Shorten lazy-window lifetime detail; preserve composition, relay, facade, and degraded graph. |

### Lecture 5 — Panel, Stashing, and Controls (75 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Put “visible,” “key,” and “active app” on the board and ask whether they mean the same thing. |
| Takeaway | One retained feature state has two AppKit representations—the full panel and edge handle—controlled by pure geometry and main-actor coordination. |
| Hard concept | Window roles/collection behavior, content-versus-frame geometry, stash state, and Carbon tap/hold timing cross distinct evidence boundaries. |
| Diagram cue | Use architecture [Flow 3](ARCHITECTURE_MAP.md#flow-3--stashrestore-presentation); add lanes for pure policy, coordinator, AppKit, and SwiftUI. |
| Code-tour entry | [`WindowRolePolicy.swift`](../../Sources/NotionPiP/Platform/WindowRolePolicy.swift), [`PanelFramePolicy.swift`](../../Sources/NotionPiP/Platform/PanelFramePolicy.swift), then [`PiPPanelCoordinator.swift`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift). |
| Demo steps | 1. Compare panel/handle roles. 2. Trace stash ordering. 3. Predict 2-point versus 4-point handle movement. 4. Draw shortcut release at 299 ms and 301 ms. |
| Audience question | “Which facts can a rectangle test prove, and which require the real window server?” |
| Misconception to surface | Persistent all-Spaces `NSPanel` behavior is product intent, not a panel defect. |
| Debrief | Classify each observation as pure policy, AppKit integration, or manual matrix evidence. |
| Transition | “The panel can hide without losing work because a separate owner manages the live browser lifecycle.” |
| Optional cut | Assign custom-size CRUD as reading; keep requested-versus-effective size semantics. |

### Lecture 6 — WebKit Notion Session (75 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Use the “one reading desk, many bookmarks” metaphor and ask what page switching must preserve. |
| Takeaway | `NotionWebSession` owns at most one live Notion WebView and separates warm view state, process-lifetime restoration, and durable restoration. |
| Hard concept | WebKit object lifetime, navigation trust, renderer recovery, and interaction-state capture are related but not interchangeable. |
| Diagram cue | Extend architecture [Flow 2](ARCHITECTURE_MAP.md#flow-2--page-activation-and-webkit-navigation) with warm-hide, switch/retire, and renderer-recovery branches. |
| Code-tour entry | [`NotionWebSession.swift`](../../Sources/NotionPiP/Platform/NotionWebSession.swift) and [`NotionWebLifecycleController.swift`](../../Sources/NotionPiP/Platform/NotionWebLifecycleController.swift). |
| Demo steps | 1. Show that SwiftUI receives an existing WebView. 2. Trace activate → restore/load → finish. 3. Contrast warm hide with page switch. 4. Compare trusted and lookalike hosts in tests. |
| Audience question | “When should the session resume an object, recreate an object, or load a durable URL/state snapshot?” |
| Misconception to surface | Page switching does not create a permanent WebView per page, and durable restoration does not persist cookies or DOM. |
| Debrief | Have learners place six state facts into warm, process, or durable lifetime. |
| Transition | “WebKit produces framework events; Domain turns the trusted parts into values and policies.” |
| Optional cut | Skip external drag/new-window detail; preserve trust classification and three lifetimes. |

### Lecture 7 — Domain Modeling and Policies (75 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Ask which parts of a URL, retry decision, or page ranking can be decided without a window, database, or network. |
| Takeaway | Validated `Sendable` values and deterministic policies carry meaning between effectful owners. |
| Hard concept | Put invariants at construction/mutation boundaries while acknowledging current folder-level exceptions without spreading them. |
| Diagram cue | Draw an inner value/policy core and outer effectful ring; arrows carry values, never database/window objects. |
| Code-tour entry | [`NotionPageReference.swift`](../../Sources/NotionPiP/Domain/NotionPageReference.swift) then [`PageWorkingSetPolicy.swift`](../../Sources/NotionPiP/Domain/PageWorkingSetPolicy.swift). |
| Demo steps | 1. Number page-URL acceptance gates. 2. Trace a visit through working-set normalization. 3. Compare history assembly and switcher ranking. 4. Calculate retry attempts 1–5. |
| Audience question | “Why do both an outer route and its nested URL need independent length and trust checks?” |
| Misconception to surface | “Domain” does not mean every type imports nothing; it means the business decision is deterministic and effect-free. |
| Debrief | Ask learners to move three proposed behaviors to the lowest layer with enough information. |
| Transition | “Values become durable only when a repository actor commits them.” |
| Optional cut | Assign detailed panel-size decoding and export rendering; retain security non-guarantees. |

### Lecture 8 — Persistence and Restoration (75 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Hold up a mutable model object and an immutable snapshot and ask which may cross an actor boundary. |
| Takeaway | One shared container feeds isolated model actors that exchange snapshots, commit explicit transactions, migrate deliberately, and degrade truthfully. |
| Hard concept | Separate in-memory transaction behavior, on-disk migration/reopen, lazy bootstrap, idempotency, and rollback. |
| Diagram cue | Use architecture page/capture flows, then draw draft → record → claim → terminal state as a durable state machine. |
| Code-tour entry | [`NotionPiPPersistence.swift`](../../Sources/NotionPiP/Persistence/NotionPiPPersistence.swift), [`NotionPiPSchema.swift`](../../Sources/NotionPiP/Persistence/NotionPiPSchema.swift), and one repository. |
| Demo steps | 1. Compare V1–V3 model lists. 2. Show private contexts/autosave off. 3. Trace one save/rollback. 4. Run or read migration, lost-ack, and atomic-enqueue tests. |
| Audience question | “Why can an in-memory repository test pass while a real migration still fails?” |
| Misconception to surface | SwiftData autosave or one shared `ModelContext` is not the repository's transaction/actor contract. |
| Debrief | For one proposed field, name schema, snapshot, transaction, migration, and degradation consequences. |
| Transition | “The local editor depends on these revisioned commits, but it speaks across a language boundary.” |
| Optional cut | Skip settings-storage detail; retain schemas, repositories, transaction, and degraded startup. |

### Lecture 9 — Quick Capture Editor Bridge (90 minutes normalized)

| Cue | Presenter plan |
|---|---|
| Hook | Ask, “At what exact event may the editor truthfully change ‘Saving…’ to ‘Saved’?” |
| Takeaway | A versioned, exact, bounded bridge makes a native persistence acknowledgement—not JavaScript dispatch—the durability boundary. |
| Hard concept | Correlation IDs, expected revisions, serialized autosaves, transition gates, stale conflicts, and exact retry must agree in two languages. |
| Diagram cue | Use the edit → debounce → native save → acknowledgement sequence, then architecture [Flows 4 and 5](ARCHITECTURE_MAP.md#flow-4--capture-delivery-from-editor-to-notion). |
| Code-tour entry | Compare [`protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts) with [`CaptureBridgeProtocol.swift`](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift), then open [`CaptureEditorSession.swift`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift). |
| Demo steps | 1. Delay a native reply. 2. Queue two edits and predict revision 2. 3. Compare original and retry byte-for-byte. 4. Use the extra 10 minutes to compare Node, native protocol, and real-WebKit evidence. |
| Audience question | “If native saved revision 1 but the reply was lost, what identity and payload may the retry change?” |
| Misconception to surface | A local file URL/CSP alone is not trust, and generated `editor.js` is not the authoring source. |
| Debrief | Have learners label the authority before dispatch, after commit, after acknowledgement, and during stale conflict. |
| Transition | “Local acknowledgement creates durable work; Lecture 10 decides how that work reaches Notion.” |
| Optional cut | Assign formatting/slash-menu details; never cut protocol trust, revision, transition, or lost-ack behavior. |

### Lecture 10 — Notion API and Delivery (90 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Ask why “retry every error” can be more dangerous than reporting a failure. |
| Takeaway | Local close/enqueue is separate from remote delivery; durable states, journals, and error classification make retries bounded and honest. |
| Hard concept | Acknowledged progress is not exactly-once semantics: a timeout after a possible create can be uncertain. |
| Diagram cue | Walk architecture [Flow 4](ARCHITECTURE_MAP.md#flow-4--capture-delivery-from-editor-to-notion) and annotate 401, 409, 429, 5xx, and ambiguous branches. |
| Code-tour entry | [`QuickCaptureLifecycleCoordinator.swift`](../../Sources/NotionPiP/Services/QuickCaptureLifecycleCoordinator.swift) → [`DeliveryEngine.swift`](../../Sources/NotionPiP/Services/DeliveryEngine.swift) → [`NotionCaptureDeliveryService.swift`](../../Sources/NotionPiP/Services/NotionCaptureDeliveryService.swift). |
| Demo steps | 1. Prove close only saves/enqueues. 2. Find single flight and claim-before-send. 3. Trace 201 blocks through create and two appends. 4. End at delivered-state cleanup. |
| Audience question | “If remote create succeeds but the local journal write fails, which fact is missing and why is retry unsafe?” |
| Misconception to surface | Single flight prevents concurrent local drains; it does not provide remote idempotency. |
| Debrief | Give each status/error to the room and require state, retry timing, user action, and safe message. |
| Transition | “Services publish state, but views must project it without becoming a second source of truth.” |
| Optional cut | Shorten the destination-variant and conversion-node catalog; retain chunk/batch bounds and ambiguity. |

### Lecture 11 — Views, Settings, and State (75 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Show a Toggle and ask, “Who owns this value before, during, and after the view disappears?” |
| Takeaway | SwiftUI renders injected owners and local presentation state; AppKit hosts retained roots; commands and effects flow back to their actual owners. |
| Hard concept | Choose `@ObservedObject`, `@StateObject`, `@Binding`, and `@State` by ownership, then distinguish saved, effective, and forced state. |
| Diagram cue | Use architecture [Flow 6](ARCHITECTURE_MAP.md#flow-6--settings-propagation-and-observable-state); draw the four AppKit/SwiftUI hosting roots. |
| Code-tour entry | [`SettingsView.swift`](../../Sources/NotionPiP/Views/SettingsView.swift), [`PiPChromeView.swift`](../../Sources/NotionPiP/Views/PiPChromeView.swift), and [`AppWindowFactory.swift`](../../Sources/NotionPiP/Platform/AppWindowFactory.swift). |
| Demo steps | 1. Search for `NSHostingView`. 2. Trace switcher Return to activation. 3. Compare SwiftUI/AppKit command menus. 4. Follow a setting from binding through owner and effect. |
| Audience question | “Why does changing the default panel size not necessarily resize the current panel?” |
| Misconception to surface | `@StateObject` is not the default for every observable object; it means the view creates and owns that object. |
| Debrief | For the exercise setting, name storage, App owner, view projection, failure behavior, tests, and manual limits. |
| Transition | “Correct ownership makes failures testable; the final lecture chooses evidence for each boundary.” |
| Optional cut | Skip the full 20-file inventory; preserve hosting, wrappers, settings, commands, failure state, and accessibility. |

### Lecture 12 — Testing, Debugging, and Change Workflow (90 minutes)

| Cue | Presenter plan |
|---|---|
| Hook | Ask, “What can a passing rectangle test prove about Mission Control?” |
| Takeaway | Choose the smallest evidence that can falsify the owning contract, then verify outward and report what remains unproved. |
| Hard concept | Distinguish pure/controller tests, in-memory versus disk SwiftData, Node/happy-dom versus real WebKit, bundle verification, and manual macOS evidence. |
| Diagram cue | Draw failing observation → owner → narrow reproduction → regression → outward verification; finish at the [verification ladder](CHANGE_GUIDE.md#verification-ladder). |
| Code-tour entry | Compare [`CaptureWebViewTestSupport.swift`](../../Tests/NotionPiPTests/CaptureWebViewTestSupport.swift) with [`dom.ts`](../../Web/QuickCaptureEditor/test-support/dom.ts), then inspect [`build_and_run.sh`](../../script/build_and_run.sh). |
| Demo steps | 1. Run/read a focused signposter test. 2. Compare test isolation helpers. 3. Select a manual matrix row. 4. Apply the change workflow to one domain, UI, or cross-language report. |
| Audience question | “Which evidence would you require for a migration bug, a WebKit bridge bug, and a wrong-Space panel?” |
| Misconception to surface | `--verify` is a bundle/startup gate, not the XCTest/Node/manual suite or notarization proof. |
| Debrief | Require every group to report exact commands, outcomes, manual observations, and unverified integrations. |
| Transition | “The course ends; maintenance begins with choosing the owning layer in the change guide.” |
| Optional cut | Assign logs/signposts detail; retain test independence, evidence boundaries, build safety, and the change loop. |

## Demo failure recovery

Say what failed, preserve evidence, switch teaching mode, and continue. Never
change security, signing, entitlements, dependencies, or user data merely to
rescue a presentation.

| Failure | Safe checks | Recovery path | Teaching point |
|---|---|---|---|
| Build or Xcode | Re-run the exact failing command; confirm macOS 15.6+, full Xcode 26.2+, `DEVELOPER_DIR`, and actual output. Explain whether existing `node_modules` invoked npm. | Use committed source, captured green output, and the build-pipeline diagram. Do not install Xcode/Node live, use `sudo` to accept a license, or edit signing. | Toolchain and bundle verification are separate from product correctness. |
| Notion login | Check whether the embedded page is on the expected sign-in route without showing credentials or cookies. | Use a pre-recorded non-sensitive journey, committed navigation tests, and the trust/state diagram. Let the presenter sign in privately later. | Authentication is user-owned WebKit state, not course configuration. |
| Network or API permission | Confirm the failure is connectivity/permission rather than silently retrying writes. Do not expose request content or tokens. | Demonstrate offline local capture, fake transports, state/error tables, and queued delivery. | Local durability and remote delivery are intentionally separate. |
| WebKit renderer/resource | Identify live Notion versus local editor, navigation versus renderer termination, and authored source versus generated asset. | Use Node tests for owned state, native protocol tests for envelopes, real-WebKit test source/captured output for integration, and the lifecycle diagram. | Each harness proves a different boundary; weakening trust policy is not recovery. |
| Global shortcut | Check registration health and conflicts; note that failure can force the menu-bar icon visible. | Invoke the same action through the menu-bar item or on-screen control. Do not rebind participants' shortcuts without consent. | Shortcut delivery is one platform adapter, not the feature's only route. |
| Focus, keyboard, or panel appears absent | Check the process, menu-bar item, edge handle, active Space, and whether the panel is visible but not key. Remember no Dock icon is expected. | Click the intended surface, use the menu/shortcut fallback, then teach from window roles, focus tests, and the named manual-matrix row. | A single machine's focus/Spaces result is a manual observation, not automatic proof of a defect. |

If `./script/build_and_run.sh` has already begun, remember that it may have
terminated the running app. Do not pretend unsaved work is recoverable. Stop,
state the consequence, and move to the prepared source-only route.

## Final presenter checklist

Before each session:

- confirm the allocation, break, prerequisite, demo, and exercise;
- open the lecture card's code entry and diagram before screen sharing;
- state the demo's expected observation and manual limits;
- verify synthetic fixtures and conceal notifications/secrets;
- prepare the optional cut and one recovery path; and
- end with the debrief and spoken transition, even when the live demo fails.

After each session, record questions, timing drift, demo environment, manual
observations, and cuts. Update claims only after revalidating current source;
the [file atlas](FILE_ATLAS.md) is orientation, historical plans are context,
and the checked-out implementation remains authority.
