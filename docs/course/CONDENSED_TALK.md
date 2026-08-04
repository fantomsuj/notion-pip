# Notion PiP in 75 Minutes

This is a slide-equivalent talk track for an engineering audience. The elapsed targets form the 75-minute spine. Every section names what the audience sees, what the presenter says, the source evidence behind it, a diagram cue, and whether a demo occurs.

## Version timing

| Version | Arithmetic | Delivery rule |
|---|---:|---|
| 60 minutes | 75 − 15 minutes of marked cuts | Make only the cuts named below; keep both demos and all ten subject areas. |
| 75 minutes | 75 minutes | Use every elapsed target as written. |
| 90 minutes | 75 + 15 minutes of marked extensions | Add only the extensions named below. |

**60-minute trim ledger:** Slides 01 (1), 02 (1), 03 (2), 04 (1), 06 (1), 07 (2), 08 (2), 09 (2), 11 (1), 14 (1), and 17 (1) = **15 minutes**.

**90-minute extension ledger:** Slides 02 (2), 03 (2), 04 (2), 07 (2), 08 (3), 12 (2), and 13 (2) = **15 minutes**.

The product demo uses a rehearsed account with non-sensitive pages. Account and network-dependent material is optional; never expose a password, session cookie, personal integration token, or private workspace content. If the environment is unavailable, use the named source and test evidence instead.

## Slide 01 — The product is a reachable layer, not a little browser window

**Elapsed target:** 00:00–03:00 (3 minutes; cumulative 3).

**Visible content:** Three phrases: “always available,” “at most one live Notion view,” and “local capture that survives failure.” Show a still of the panel stashed at a screen edge and restored.

**Spoken narrative:** Notion PiP is a macOS accessory app: its absence from the Dock is expected, its all-Spaces panel behavior is intentional, and the menu-bar item, edge handle, and global shortcut are alternate reachability paths. Frame the repository around three promises: keep the panel available, never keep more than one live Notion view, and keep user-authored capture data durable even when remote delivery is not.

**Source links:** [Lecture 1](01-product-and-user-experience.md), [product intent and setup expectations](../../AGENTS.md), [PiPChromeView](../../Sources/NotionPiP/Views/PiPChromeView.swift).

**Diagram cue:** Draw three concentric rings labeled presentation, session, and durable work; use the [architecture map](ARCHITECTURE_MAP.md) as the reference for the later decomposition.

**Demo:** No demo — establish the mental model before manipulating the app.

**Audience checkpoint 1:** If the app is running but has no Dock icon, is that evidence of a crash? **Answer:** No. It is an accessory app; first check the menu-bar icon, edge handle, or configured shortcut.

**60-minute cut:** Trim 1 minute by using the three-ring image without the still-image walkthrough.

**90-minute extension:** None.

## Slide 02 — Product demo: browse, switch, stash, capture

**Elapsed target:** 03:00–08:00 (5 minutes; cumulative 8).

**Visible content:** The running app with a rehearsed, non-sensitive Notion page and a prepared Quick Capture draft.

**Spoken narrative:** Demonstrate the user loop in one uninterrupted pass: restore the panel, navigate the existing Notion session, switch pages, stash and restore the panel, then type a short Quick Capture draft. Call out that panel visibility, browser identity, and draft durability are related experiences with different owners. Do not imply that a local save acknowledgement means the capture has reached Notion.

**Source links:** [Lecture 1](01-product-and-user-experience.md), [PiPPanelCoordinator](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift), [QuickCaptureView](../../Sources/NotionPiP/Views/QuickCaptureView.swift).

**Diagram cue:** Keep a small “user action → owning subsystem” strip below the live app: restore → Platform, switch → App/Platform, type → Web/Platform/Persistence.

**Demo:** **Product demo.** Preflight the account and content. Fallback: show the prepared stills and use [PiPChromeViewTests](../../Tests/NotionPiPTests/PiPChromeViewTests.swift) plus [PiPStashHandleInteractionTests](../../Tests/NotionPiPTests/PiPStashHandleInteractionTests.swift) for chrome/stashing, [NotionWebSessionTests](../../Tests/NotionPiPTests/NotionWebSessionTests.swift) for page replacement and restoration, and [CaptureWebViewAutosaveTests](../../Tests/NotionPiPTests/CaptureWebViewAutosaveTests.swift) for acknowledged local persistence.

**60-minute cut:** Trim 1 minute by demonstrating only one page switch and one stash/restore cycle.

**90-minute extension:** Add 2 minutes for audience-directed page switching and a second capture edit, while keeping all content non-sensitive.

## Slide 03 — Two source languages, one shipped app bundle

**Elapsed target:** 08:00–12:00 (4 minutes; cumulative 12).

**Visible content:** A stack table: Swift 6.2 / SwiftPM / macOS 14 target; SwiftUI + AppKit + WebKit; SwiftData + Keychain + Notion API; TypeScript + Tiptap + esbuild; checked-in `editor.js`.

**Spoken narrative:** The native executable is a Swift package, but the capture editor is a TypeScript application bundled as a generated resource. Explain the artifact boundary: edit TypeScript under `Web/QuickCaptureEditor`, build it with the pinned npm toolchain, and ship the checked-in `Sources/NotionPiP/Resources/QuickCapture/editor.js`. `.build`, `dist`, and `node_modules` are generated or local artifacts, not product architecture. Source builds require full Xcode 26.2 or newer on macOS 15.6 or newer even though the product deployment target is macOS 14.

**Source links:** [Lecture 2](02-repository-and-technology-stack.md), [Package.swift](../../Package.swift), [package.json](../../package.json), [build-and-run script](../../script/build_and_run.sh).

**Diagram cue:** Draw two build lanes—Swift sources and TypeScript sources—joining at `NotionPiP.app`.

**Demo:** No demo — use the artifact diagram to avoid spending talk time on tool output.

**60-minute cut:** Trim 2 minutes by naming the frameworks and artifact boundary without discussing generated directories or host-versus-target versions.

**90-minute extension:** Add 2 minutes to open the package manifests and trace `editor.ts` through the build script to the bundled `editor.js`.

## Slide 04 — Architecture is a map of ownership

**Elapsed target:** 12:00–16:00 (4 minutes; cumulative 16).

**Visible content:** Seven columns: Domain, Persistence, Services, App, Platform, Views, Web. Under each, show its job and one representative type.

**Spoken narrative:** Domain owns values and pure policy. Persistence owns SwiftData models and repositories. Services own delivery orchestration. App owns composition, observable state, and feature coordination. Platform owns AppKit, WebKit, system integrations, and Keychain. Views render state and send intent. Web owns the editor implementation and its side of the bridge. Dependencies cross through narrow contracts and value snapshots; a convenient file location is not proof of ownership.

**Source links:** [subsystem and ownership map](ARCHITECTURE_MAP.md), [change guide ownership rules](CHANGE_GUIDE.md), [file atlas](FILE_ATLAS.md).

**Diagram cue:** Reuse the subsystem row from the [architecture map](ARCHITECTURE_MAP.md), with arrows only where a real call or value crosses a boundary.

**Demo:** No demo — ask the audience to place a hypothetical “hide menu icon” preference on the ownership map.

**Audience checkpoint 2:** Does the SwiftUI settings form own menu-bar icon behavior? **Answer:** No. The view expresses intent; App coordinates saved versus effective state, while the dedicated Platform `UserDefaults` adapter stores the preference and the status-item controller applies it.

**60-minute cut:** Trim 1 minute by showing only each layer’s job, not its representative type.

**90-minute extension:** Add 2 minutes for two more placement exercises: URL validation and delivery retry policy.

## Slide 05 — Startup constructs the graph before it shows the panel

**Elapsed target:** 16:00–20:00 (4 minutes; cumulative 20).

**Visible content:** `NotionPiPApp.main → AppComposition → AppRuntime.start → NSApplication.run`, with the degraded-persistence branch visible.

**Spoken narrative:** `NotionPiPApp` is the executable entry point and `AppComposition` is the concrete composition root. It creates persistence and services, builds `AppRuntime`, installs the delegate, starts the runtime, and enters the AppKit run loop. The runtime can continue in a degraded mode when durable storage cannot open, which is a deliberate availability choice—not permission to hide the failure.

**Source links:** [Lecture 3](03-application-lifecycle.md), [NotionPiPApp.swift](../../Sources/NotionPiP/App/NotionPiPApp.swift), [AppDelegate.swift](../../Sources/NotionPiP/App/AppDelegate.swift), [startup flow](ARCHITECTURE_MAP.md).

**Diagram cue:** Use Architecture Map Flow 1; highlight object construction separately from lifecycle callbacks.

**Demo:** No demo — a static startup sequence is faster and more deterministic than relaunching the app.

**60-minute cut:** Keep in full.

**90-minute extension:** None.

## Slide 06 — AppRuntime is a main-actor facade, not a service locator

**Elapsed target:** 20:00–24:00 (4 minutes; cumulative 24).

**Visible content:** `AppRuntime` in the center, feature controllers and action relays on the App side, actor-backed repositories and services outside it.

**Spoken narrative:** `AppRuntime` is the `@MainActor` facade that connects UI intent, platform callbacks, observable state, repositories, and services. Composition injects concrete collaborators. Controllers own feature-specific state transitions; action relays keep AppKit command surfaces from reaching through SwiftUI. Actor isolation protects mutable storage and service state, while Sendable value snapshots cross back to the main actor.

**Source links:** [Lecture 4](04-composition-and-runtime.md), [AppRuntime.swift](../../Sources/NotionPiP/App/AppRuntime.swift), [AppCommandActionRelay.swift](../../Sources/NotionPiP/App/AppCommandActionRelay.swift), [AppRuntime facade tests](../../Tests/NotionPiPTests/AppRuntimeFacadeTests.swift).

**Diagram cue:** Draw a main-actor boundary around Runtime/controllers and actor boundaries around repositories/services; label crossings “intent” and “snapshot.”

**Demo:** No demo — point to the constructor and one relay path in the visible code excerpt.

**60-minute cut:** Trim 1 minute by omitting the relay example while retaining the isolation boundaries.

**90-minute extension:** None.

## Slide 07 — The panel is a policy-driven state machine

**Elapsed target:** 24:00–29:00 (5 minutes; cumulative 29).

**Visible content:** Panel states `visible ↔ stashed`, plus `WindowRolePolicy`, `PanelFramePolicy`, `PiPPanelCoordinator`, `PiPStashHandleController`, and the global shortcut registrar.

**Spoken narrative:** AppKit owns the unusual window behavior. Pure policies decide role, geometry, and stash transitions; coordinators apply those decisions to `NSPanel` and SwiftUI hosts. Stashing moves the panel out of the way and exposes a separate edge handle so the app remains reachable. The shortcut and menu icon are additional controls, not the owners of panel geometry. Preserve all-Spaces behavior as a product invariant.

**Source links:** [Lecture 5](05-panel-stashing-and-controls.md), [PiPPanelCoordinator.swift](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift), [PanelStashPolicy.swift](../../Sources/NotionPiP/Platform/PanelStashPolicy.swift), [stash/restore flow](ARCHITECTURE_MAP.md).

**Diagram cue:** Use Architecture Map Flow 3, adding a dashed reachability triangle between menu item, shortcut, and edge handle.

**Demo:** No demo — the product demo already established behavior; here the state machine explains it.

**60-minute cut:** Trim 2 minutes by discussing only the visible/stashed transition and the edge handle.

**90-minute extension:** Add 2 minutes to walk through the frame calculation and the matching interaction tests.

## Slide 08 — One live Notion WebView, three different lifetimes

**Elapsed target:** 29:00–34:00 (5 minutes; cumulative 34).

**Visible content:** Three lanes: live Notion session, local Quick Capture editor, ephemeral test WebViews. Put “at most one live Notion WebView” above the first lane.

**Spoken narrative:** `NotionWebSession` owns at most one live Notion `WKWebView`. A hide/show during the warm period can reuse that view, while switching to a different page captures outgoing interaction state, retires the old view, and ensures one replacement. Quick Capture is a different, local-file WebView with a nonpersistent data store and a narrow script bridge. WebKit integration tests create disposable views. Trust decisions belong at navigation and message boundaries, not in SwiftUI.

**Source links:** [Lecture 6](06-webkit-notion-session.md), [NotionWebSession.swift](../../Sources/NotionPiP/Platform/NotionWebSession.swift), [NotionWebView.swift](../../Sources/NotionPiP/Platform/NotionWebView.swift), [NotionWebSessionTests.swift](../../Tests/NotionPiPTests/NotionWebSessionTests.swift).

**Diagram cue:** Use Architecture Map Flow 2 for live navigation, then place the capture editor beside—not inside—that lifecycle.

**Demo:** Optional account/network demo only in the 90-minute extension: show that the authenticated session remains available when a page switch replaces the live view. Never display credentials or private content. Fallback: the lifecycle diagram and `NotionWebSessionTests`.

**Audience checkpoint 3:** Does “one live Notion WebView” mean object identity must survive every page switch? **Answer:** No. A warm hide/show can reuse the view, but a different page retires it and creates one replacement; the invariant is at most one live view at a time.

**60-minute cut:** Trim 2 minutes by stating the three lifetimes and single-view invariant without opening test evidence.

**90-minute extension:** Add 3 minutes for the optional account/network demonstration and its lifecycle-test fallback.

## Slide 09 — Domain types make invalid intent hard to express

**Elapsed target:** 34:00–38:00 (4 minutes; cumulative 38).

**Visible content:** A small set of value types and policies: `NotionPageReference`, `PageWorkingSetPolicy`, `DeliveryState`, `RetryPolicy`, and `ExternalURLRoute`.

**Spoken narrative:** Domain code gives names to validated identity, explicit state, and deterministic decisions. Page references normalize what the rest of the app may trust; working-set policy chooses recency and pin behavior; delivery and retry types describe failure without invoking network code. Keeping these decisions pure makes concurrency boundaries smaller and tests faster.

**Source links:** [Lecture 7](07-domain-modeling-and-policies.md), [NotionPageReference.swift](../../Sources/NotionPiP/Domain/NotionPageReference.swift), [PageWorkingSetPolicy.swift](../../Sources/NotionPiP/Domain/PageWorkingSetPolicy.swift), [RetryPolicy.swift](../../Sources/NotionPiP/Domain/RetryPolicy.swift).

**Diagram cue:** Draw “untrusted input → validated value → pure policy → effect owner.”

**Demo:** No demo — use one input/output policy example on the slide.

**60-minute cut:** Trim 2 minutes by retaining only page identity and working-set policy examples.

**90-minute extension:** None.

## Slide 10 — Persistence returns snapshots, not live models

**Elapsed target:** 38:00–43:00 (5 minutes; cumulative 43).

**Visible content:** Shared SwiftData container feeding model-actor repositories for pages, settings, drafts, and capture records; Sendable snapshots crossing outward.

**Spoken narrative:** `NotionPiPPersistence` owns schema and container creation. Repositories isolate model access behind actors and return value snapshots so SwiftData objects do not escape their context. Restoration rebuilds working state at startup; schema migration and disk-backed tests cover durable behavior. If persistence initialization fails, the runtime can surface degraded service health while continuing with limited functionality.

**Source links:** [Lecture 8](08-persistence-and-restoration.md), [NotionPiPPersistence.swift](../../Sources/NotionPiP/Persistence/NotionPiPPersistence.swift), [CaptureRepository.swift](../../Sources/NotionPiP/Persistence/CaptureRepository.swift), [SchemaMigrationTests.swift](../../Tests/NotionPiPTests/SchemaMigrationTests.swift).

**Diagram cue:** Draw actor-isolated repositories inside the persistence boundary and immutable snapshots leaving it toward App and Services.

**Demo:** No demo — show the persistence boundary and one restoration path.

**60-minute cut:** Keep in full.

**90-minute extension:** None.

## Slide 11 — Quick Capture is a local editor with a versioned seam

**Elapsed target:** 43:00–48:00 (5 minutes; cumulative 48).

**Visible content:** Tiptap editor → TypeScript protocol/client → WebKit script message → Swift protocol/session → capture repository. Mark `editor.js` as generated.

**Spoken narrative:** The editor runs local HTML, CSS, and JavaScript in a nonpersistent WebKit store. TypeScript owns rich-text interaction and canonical editor snapshots. `CaptureBridgeProtocol` defines the payload contract; `WeakScriptMessageHandler` avoids a WebKit ownership cycle; `CaptureEditorSession` validates requests and coordinates persistence. A bridge change is a cross-language contract change and must update both implementations and both test suites.

**Source links:** [Lecture 9](09-quick-capture-editor-bridge.md), [editor controller](../../Web/QuickCaptureEditor/quick-capture-editor-controller.ts), [CaptureBridgeProtocol.swift](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift), [CaptureEditorSession.swift](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift).

**Diagram cue:** Use the editor half of Architecture Map Flow 4 and label every serialization boundary.

**Demo:** No demo — reserve the live code trace for the next section.

**60-minute cut:** Trim 1 minute by omitting generated-asset mechanics, already covered on Slide 03.

**90-minute extension:** None.

## Slide 12 — Code-flow demo: an edit becomes a durable acknowledgement

**Elapsed target:** 48:00–54:00 (6 minutes; cumulative 54).

**Visible content:** Side-by-side excerpts from the 300 ms debounced publisher, `BridgeClient`, `WeakScriptMessageHandler`, `CaptureEditorSession`, and `CaptureRepository`.

**Spoken narrative:** Trace one keystroke: the editor produces a canonical snapshot; a 300 ms debounce coalesces changes; `BridgeClient` sends a request carrying the expected revision; WebKit forwards the message through the weak handler; Swift decodes it; and `CaptureRepository` enforces the expected revision before saving. Back in the browser, `BridgeClient` validates the reply shape and correlation ID, and a successful reply advances the editor to the maximum of its current revision and the returned authoritative revision. A lost, malformed, uncorrelated, or failed acknowledgement must not silently declare the draft saved. Emphasize the boundary: this acknowledgement proves local persistence, not remote Notion delivery.

**Source links:** [debounced-change-publisher.ts](../../Web/QuickCaptureEditor/bridge/debounced-change-publisher.ts), [bridge-client.ts](../../Web/QuickCaptureEditor/bridge/bridge-client.ts), [WeakScriptMessageHandler.swift](../../Sources/NotionPiP/Platform/WeakScriptMessageHandler.swift), [CaptureEditorSession.swift](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift), [autosave tests](../../Web/QuickCaptureEditor/autosave.test.ts).

**Diagram cue:** Animate or reveal one numbered arrow at a time across the Web → Platform → Persistence boundary; finish with a separate, still-unstarted Delivery lane.

**Demo:** **Code-flow demo.** Navigate these prepared symbols rather than editing code. Fallback: use the numbered Architecture Map Flow 4 and the autosave test cases.

**Audience checkpoint 4:** What does a successful autosave acknowledgement prove? **Answer:** Native persistence accepted the save under its expected-revision rules and returned an authoritative revision; it does not prove delivery to Notion.

**60-minute cut:** Keep in full.

**90-minute extension:** Add 2 minutes to compare success, revision mismatch, and lost-acknowledgement tests.

## Slide 13 — Delivery is an outbox with explicit uncertainty

**Elapsed target:** 54:00–59:00 (5 minutes; cumulative 59).

**Visible content:** `CaptureRepository → DeliveryScheduler → DeliveryEngine → journal/API → DeliveryState`, with `queued`, `inFlight`, `retrying`, `blockedConflict`, `uncertain`, and `delivered` outcomes.

**Spoken narrative:** Closing or submitting a capture does not make the network reliable. The repository is the durable outbox; the scheduler decides when work is eligible; the engine owns an attempt; the delivery service converts blocks and calls the Notion API. Persisted states, retry policy, and request journaling distinguish safe retries from uncertain outcomes so the app does not pretend success or duplicate work casually.

**Source links:** [Lecture 10](10-notion-api-and-delivery.md), [DeliveryScheduler.swift](../../Sources/NotionPiP/Services/DeliveryScheduler.swift), [DeliveryEngine.swift](../../Sources/NotionPiP/Services/DeliveryEngine.swift), [NotionCaptureDeliveryService.swift](../../Sources/NotionPiP/Services/NotionCaptureDeliveryService.swift), [DeliveryEngineTests.swift](../../Tests/NotionPiPTests/DeliveryEngineTests.swift).

**Diagram cue:** Complete Architecture Map Flow 4 by revealing the previously hidden Delivery lane and branching on confirmed failure versus ambiguous completion.

**Demo:** No live network demo — deterministic fake-API evidence is safer for the base talk.

**60-minute cut:** Keep in full.

**90-minute extension:** Add 2 minutes to step through one retryable failure and one ambiguous result in `DeliveryEngineTests`.

## Slide 14 — Views bind state; settings propagate effects

**Elapsed target:** 59:00–62:00 (3 minutes; cumulative 62).

**Visible content:** `SwiftUI intent → App controller/runtime → Persistence and/or Platform effect → observable state → SwiftUI`, with AppKit-hosted panel and settings roots.

**Spoken narrative:** SwiftUI views should remain declarative: read observable state, bind edits, and send intent. App owns feature coordination; dedicated SwiftData or `UserDefaults` adapters store durable preferences; and Platform applies system effects such as panel sizing, shortcut registration, and menu-bar visibility. AppKit still owns window creation and hosting, so a view is not the whole feature.

**Source links:** [Lecture 11](11-views-settings-and-state.md), [SettingsView.swift](../../Sources/NotionPiP/Views/SettingsView.swift), [PanelSizeController.swift](../../Sources/NotionPiP/App/PanelSizeController.swift), [settings propagation flow](ARCHITECTURE_MAP.md).

**Diagram cue:** Use Architecture Map Flow 6 as a round trip, not a one-way binding arrow.

**Demo:** No demo — use one setting to show the complete ownership round trip.

**60-minute cut:** Trim 1 minute by showing only the panel-size example.

**90-minute extension:** None.

## Slide 15 — Tests are evidence layers, not one command

**Elapsed target:** 62:00–66:00 (4 minutes; cumulative 66).

**Visible content:** A verification ladder: pure policy → actor/repository → Web protocol/unit → real WebKit integration → full Swift/npm suites → staged app verification → manual behavior.

**Spoken narrative:** Match evidence to risk. Pure policies need fast independent tests. Persistence needs actor isolation and disk-backed migration coverage. The editor needs TypeScript protocol tests plus real `WKWebView` tests for the actual bridge and resource bundle. Full suites catch adjacency; `build_and_run.sh --verify` proves a staged app launches; manual checks remain necessary for Spaces, focus, animation, shortcuts, and account/network behavior.

**Source links:** [Lecture 12](12-testing-debugging-and-change-workflow.md), [CaptureBridgeProtocolTests.swift](../../Tests/NotionPiPTests/CaptureBridgeProtocolTests.swift), [CaptureWebViewAutosaveTests.swift](../../Tests/NotionPiPTests/CaptureWebViewAutosaveTests.swift), [verification ladder](CHANGE_GUIDE.md).

**Diagram cue:** Draw the ladder with speed decreasing and realism increasing from bottom to top.

**Demo:** No demo — show representative commands and evidence types, not a live test run.

**60-minute cut:** Keep in full.

**90-minute extension:** None.

## Slide 16 — Safe changes begin with ownership and a clean boundary

**Elapsed target:** 66:00–69:00 (3 minutes; cumulative 69).

**Visible content:** The workflow: inspect dirty tree → trace contract → add smallest regression test → edit the owner → run focused/adjacent checks → run full relevant checks → perform risk-based manual verification → report exact evidence.

**Spoken narrative:** Preserve existing work before touching files. Trace call sites and contracts before choosing the edit. Put the behavior change in its owning layer and keep seams narrow, especially across actors and the WebKit bridge. Verification expands with risk: a policy edit is not the same as a schema migration, panel behavior change, or cross-language protocol change. The handoff should say what ran and what remains manual.

**Source links:** [safe change workflow](CHANGE_GUIDE.md), [Lecture 12](12-testing-debugging-and-change-workflow.md), [repository course commands](README.md).

**Diagram cue:** Show a funnel from broad investigation to focused edit, then an expanding evidence ladder after the edit.

**Demo:** No demo — this is the reusable operating procedure for the audience’s next change.

**60-minute cut:** Keep in full.

**90-minute extension:** None.

## Slide 17 — Synthesis: trace behavior across owners

**Elapsed target:** 69:00–71:00 (2 minutes; cumulative 71).

**Visible content:** One end-to-end close trace: Platform `AppWindowFactory` / `CaptureEditorSession` → Services `QuickCaptureLifecycleCoordinator` → Persistence `CaptureRepository` → Services `DeliveryScheduler` / `DeliveryEngine` → remote API, with durable state highlighted before network work.

**Spoken narrative:** Ask the same three questions at each arrow: who owns the decision, what value crosses the boundary, and what evidence proves it? The architecture becomes manageable when behavior is followed as a flow rather than inferred from folder names. The Platform close handler asks `CaptureEditorSession` for a fresh snapshot, the lifecycle service ensures the draft is saved and enqueued through `CaptureRepository`, and only then does the scheduler trigger the delivery engine and remote API path.

**Source links:** [editor-to-delivery flow](ARCHITECTURE_MAP.md), [file atlas](FILE_ATLAS.md), [advanced bridge change scenario](CHANGE_GUIDE.md).

**Diagram cue:** Reuse Flow 4 with owner names above arrows and evidence names below them.

**Demo:** No demo — conduct a brief verbal trace with the audience.

**Audience checkpoint 5:** A stash animation regresses only on a second Space. Is a pure policy test sufficient proof of the fix? **Answer:** No. Add focused policy/coordinator evidence, then manually verify real panel behavior across Spaces because that AppKit integration is not fully represented by the unit seam.

**60-minute cut:** Trim 1 minute by asking the checkpoint and giving the answer without the full audience trace.

**90-minute extension:** None.

## Slide 18 — Four ideas to carry into the repository

**Elapsed target:** 71:00–73:00 (2 minutes; cumulative 73).

**Visible content:** Exactly these four closing ideas:

1. The accessory panel and its at-most-one-live-browser rule are intentional product constraints.
2. Explicit ownership, actor isolation, and trust boundaries keep integration code understandable.
3. Local-first persistence and explicit failure states protect user work before remote delivery.
4. Safe changes pair the smallest owning edit with evidence proportional to the risk.

**Spoken narrative:** Reconnect the talk to the opening promises. Product constraints determine lifecycle choices; ownership and isolation keep those choices maintainable; local durability makes failure honest; and risk-shaped evidence lets the repository evolve without weakening its invariants.

**Source links:** [course outcomes](README.md), [cross-cutting invariants](ARCHITECTURE_MAP.md), [change guide](CHANGE_GUIDE.md).

**Diagram cue:** Return to the three-ring opening diagram and add the fourth idea—change evidence—as a supporting foundation.

**Demo:** No demo — deliver the four ideas without introducing new material.

**60-minute cut:** Keep in full.

**90-minute extension:** None.

## Slide 19 — Choose the next study path by role

**Elapsed target:** 73:00–74:00 (1 minute; cumulative 74).

**Visible content:** A role-to-reading map.

**Spoken narrative:** Give each audience member a concrete next step rather than assigning the whole course at once.

**Source links:**

- New to macOS accessory apps: [Lectures 1–3](README.md) and the [glossary](GLOSSARY.md).
- Swift/macOS maintainer: [Lectures 4–8](README.md), the [architecture map](ARCHITECTURE_MAP.md), and the [file atlas](FILE_ATLAS.md).
- Editor or delivery engineer: [Lectures 9–10](README.md).
- UI, test, or change maintainer: [Lectures 11–12](README.md) and the [change guide](CHANGE_GUIDE.md).
- Future presenter: the [presenter guide](PRESENTER_GUIDE.md) and this talk’s timing ledgers.

**Diagram cue:** Show five short arrows from role labels to the linked course materials.

**Demo:** No demo — leave the links visible for the audience to capture.

**60-minute cut:** Keep in full.

**90-minute extension:** None.

## Slide 20 — Close on the invariant, then take questions

**Elapsed target:** 74:00–75:00 (1 minute; cumulative 75).

**Visible content:** “Preserve reachability, the one-live-view invariant, and user work.” Include the course index URL or repository path.

**Spoken narrative:** Close with the engineering test for any proposed change: does it preserve how the app stays reachable, how the session keeps at most one live Notion view while restoring safe state, and how local user work survives failure? Invite questions by flow—startup, panel, WebKit, persistence, editor, delivery, or verification—so answers can return to an owning subsystem.

**Source links:** [course index](README.md), [architecture map](ARCHITECTURE_MAP.md), [presenter guide](PRESENTER_GUIDE.md).

**Diagram cue:** Keep the final invariant sentence on screen; no new diagram.

**Demo:** No demo — reserve the final minute for the close and transition to Q&A.

**60-minute cut:** Keep in full.

**90-minute extension:** None; the 15 extension minutes are already allocated before the close.
