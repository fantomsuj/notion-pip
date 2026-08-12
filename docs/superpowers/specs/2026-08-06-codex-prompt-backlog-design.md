# Codex Prompt Backlog Design

**Date:** 2026-08-06

**Purpose:** Provide a balanced portfolio of implementation-ready Codex prompts for Notion PiP.
**Baseline reviewed:** Current repository behavior, `origin/master`, recent branch work, product research, beta-readiness guidance, modularity roadmap, manual test matrix, and existing Swift and TypeScript tests.

## How to use this backlog

Each numbered entry is intended to be pasted into a fresh Codex workspace as a standalone request. Before selecting one, compare the workspace against `origin/master` and confirm that newer work has not already implemented it. The prompts deliberately ask Codex to inspect current call sites and tests rather than assuming the likely files listed here are still authoritative.

Priority means:

- **P0:** beta safety or distribution readiness
- **P1:** high-value product, reliability, or accessibility improvement
- **P2:** enabling architecture with less immediate user impact

Effort is a directional estimate: **S** is a focused change, **M** is a multi-file feature, and **L** is a substantial but reviewable project. “Parallel-safe” means the prompt is relatively unlikely to overlap other entries. It does not replace checking the actual worktree before editing.

Every prompt preserves these repository contracts unless it explicitly says otherwise:

- Swift 6.2, macOS 14+, public APIs, current signing, and current entitlements
- one live Notion `WKWebView`, with no multi-panel or native Notion-client expansion
- local-first Quick Capture durability and explicit delivery state
- no background clipboard, active-app, browser, calendar, or screen observation
- structured concurrency without unsafe isolation escapes
- focused regression tests and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

## Portfolio summary

| # | Prompt | Category | Priority | Impact | Effort | Parallel-safe |
|---:|---|---|---|---|---|---|
| 1 | Add role labels to pinned pages | Product/UX | P1 | High | M | No |
| 2 | Add direct commands for named page roles | Product/UX | P2 | Medium | M | No; depends on #1 |
| 3 | Add Capture and Return | Product/UX | P1 | High | M | No |
| 4 | Preserve explicit source metadata in Quick Capture | Product/UX | P1 | Medium | M | No |
| 5 | Remember a preferred size per pinned page | Product/UX | P2 | Medium | M | No |
| 6 | Add opt-in Launch at Login | Product/UX | P1 | Medium | S | Yes |
| 7 | Recover the live Notion page after WebKit process termination | Reliability | P0 | High | M | No |
| 8 | Harden restoration across display topology changes | Reliability | P0 | High | M | No |
| 9 | Add recoverable persistent-store failure handling | Reliability | P0 | High | L | No |
| 10 | Build a deterministic delivery fault-injection matrix | Reliability | P1 | High | M | Yes |
| 11 | Self-heal shortcut registration after wake and session changes | Reliability | P1 | Medium | M | No |
| 12 | Enforce performance and idle-resource budgets | Reliability | P1 | High | M | Yes |
| 13 | Extract native editor transitions from `CaptureEditorSession` | Architecture | P2 | High | L | No |
| 14 | Create one versioned Swift–TypeScript bridge contract | Architecture | P2 | High | L | No; after #13 |
| 15 | Decompose `NotionWebSession` by responsibility | Architecture | P2 | High | L | No |
| 16 | Replace `AppRuntime` reach-through with feature façades | Architecture | P2 | Medium | L | No |
| 17 | Introduce dependency-enforcing SwiftPM targets | Architecture | P2 | Medium | L | No; after #13–16 |
| 18 | Audit VoiceOver semantics across every surface | Accessibility | P0 | High | M | Mostly |
| 19 | Add keyboard focus traversal regression coverage | Accessibility | P0 | High | M | No |
| 20 | Complete system accessibility-preference support | Accessibility | P1 | Medium | M | Mostly |
| 21 | Announce capture and recovery state accessibly | Accessibility | P0 | High | M | No |
| 22 | Build and verify the staged app bundle in CI | Release | P0 | High | M | Yes |
| 23 | Add a Developer ID signing and notarization workflow | Release | P0 | High | L | No; after #22 |
| 24 | Export a privacy-safe beta diagnostics bundle | Release | P1 | High | M | No |
| 25 | Finish the external-beta handoff surface and smoke test | Release | P0 | High | M | Mostly |

## Product and UX prompts

### 1. Add optional role labels to pinned pages

**Why it fits:** The working set is intentionally bounded, but recurring roles such as “Today,” “Project,” or “Meeting Notes” can be easier to recognize than page titles. This improves deliberate switching without adding another live web view.

**Likely areas:** page persistence schema, working-set snapshots and policies, page switcher controller/view, schema migration tests.

**Prompt:**

> Add optional device-local role labels to pinned Notion pages. Start by inspecting the pinned-page persistence model, schema migrations, working-set snapshots, switcher controller/view, and nearby tests. A role is short user-authored display metadata such as “Today” or “Project Brief”; it must never change the Notion page title or leave the Mac. Let users add, edit, and clear a role from the existing page-switcher experience without making the common switch action slower. Trim and collapse whitespace, cap the normalized role at 32 user-perceived characters, reject blank values, and require uniqueness among pins using case- and diacritic-insensitive comparison. Show the role prominently while keeping the actual page title available, and preserve deterministic search by matching both role and title. Migrate existing stores with nil roles, preserve pin order and recents behavior, and keep exactly one live WebView. Add unit tests for persistence, migration, search/ranking, duplicate validation, normalization, editing, clearing, and accessibility copy. Manually verify keyboard and VoiceOver operation in the switcher. Run the full Swift test suite and report any manual-only checks.

### 2. Add direct commands for named page roles

**Why it fits:** Stable roles can turn a repeated navigation sequence into an invocation while keeping context switching explicit and user-controlled.

**Likely areas:** app command model, main/status menus, page switcher controller, runtime activation path, settings or role-editing UI.

**Dependencies:** Complete #1 first and use its duplicate-role policy.

**Prompt:**

> Add direct app commands for activating pinned pages by their optional role labels. First inspect the role-label implementation, `AppCommandModel`, AppKit command-menu factories, runtime activation flow, and existing command tests. Expose role commands through a discoverable menu and the macOS responder/command system; do not register seven more global Carbon shortcuts by default. Commands must resolve a role deterministically, reuse the normal page-activation path, preserve the single live WebView and working-set state, and be disabled or omitted when the role is absent or ambiguous. Do not create an automation engine or observe the foreground app. Ensure menu items update after role edits without rebuilding unrelated application state. Add tests for command construction, enabled state, duplicate/removed roles, correct page activation, and no-op behavior when state changes between menu creation and invocation. Manually verify keyboard menu access, VoiceOver naming, stashed-panel activation, and cross-Space behavior. Run the full Swift test suite.

### 3. Add Capture and Return

**Why it fits:** Quick Capture is durable, but a fast “deposit this and take me back” action would complete the trusted-capture loop without requiring the user to watch delivery.

**Likely areas:** authored Quick Capture TypeScript, bridge protocol, editor session/lifecycle coordinator, window presenter, focus restoration, outbox status.

**Prompt:**

> Implement a Quick Capture “Capture and Return” action using Command-Return. Inspect the TypeScript editor transitions, bridge protocol, `CaptureEditorSession`, lifecycle coordinator, window presenter, focus-restoration behavior, and their tests before designing the change. Command-Return must flush the authoritative editor snapshot to local persistence, enqueue it when configuration permits, close the Quick Capture window through its existing presenter path only after local acceptance is confirmed, and restore the application that was active before capture opened. Remote Notion delivery must remain asynchronous; offline or API failure must not delay the return or lose the note. If local persistence fails, keep the editor open with an actionable error. If destination or token configuration is missing, preserve the draft and present a truthful recovery route. Prevent double submission from key repeat or repeated bridge messages. Add Swift and TypeScript regression tests for success, empty capture, pending debounce, local failure, missing configuration, offline delivery, duplicate commands, and focus restoration. Rebuild and verify committed editor assets, run web tests/typecheck and the full Swift suite, and manually verify focus across Spaces.

### 4. Preserve explicit source metadata in Quick Capture

**Why it fits:** A user-invoked pasted or dropped source can make a capture more useful without silently monitoring browsing activity.

**Likely areas:** Quick Capture launch input, drop/paste handling, draft/source document model, capture export, Notion block conversion, settings copy.

**Prompt:**

> Add source metadata for content the user explicitly pastes or drops into Quick Capture. Inspect the trusted-capture preferences, Quick Capture launch path, TypeScript paste/drop handling, draft persistence, `CaptureExport`, Notion conversion, and privacy documentation. Support a conservative first slice: when the user deliberately drops or pastes a valid HTTPS URL, retain a normalized source URL and an optional user-visible source title if one was supplied by that explicit action. Do not inspect browser state, clipboard history, active applications, or fetch remote page metadata in the background. Show a small removable source preview before save, persist it through autosave/conflict/relaunch, and deliver it through an intentional representation compatible with the existing narrow Notion API. Strip credentials and reject unsafe or oversized values. Existing drafts must migrate unchanged. Add Swift and TypeScript tests for sanitization, persistence, removal, export, delivery, conflict recovery, malicious schemes, credentials, and size limits. Update privacy-facing copy, rebuild generated editor assets, and run web and Swift checks.

### 5. Remember a preferred size per pinned page

**Why it fits:** A project brief and a daily note may need different footprints, but the feature should build on the existing panel-size model rather than introduce more panels.

**Likely areas:** panel-size preferences, pinned-page metadata, activation coordinator, frame policy, settings/switcher UI, migrations.

**Prompt:**

> Add an optional preferred panel-size preset to each pinned page. Inspect the current panel geometry redesign, `PanelSizePreferences`, pinned-page persistence, activation path, stash/restore behavior, and tests before editing. Users should be able to assign one existing named preset—or “Use current default”—to a pin. On deliberate page activation, apply the page preference without reloading the live WebView; do not continuously resize during navigation, restoration, display changes, or a transient URL redirect. Preserve the committed frame and stash anchor rules and clamp safely to the destination screen. Manual resizing must not rewrite a pin’s preference; only an explicit assignment in the pin UI changes it. Existing pins must migrate to no override. Add tests for migration, activation, missing/deleted presets, custom preset edits, manual resize, stash/restore, display clamping, relaunch, and rapid switches. Manually verify across two displays and full-screen Spaces. Run the full Swift suite.

### 6. Add opt-in Launch at Login

**Why it fits:** An accessory intended to remain available benefits from a user-controlled login launch, especially because it has no Dock presence.

**Likely areas:** settings, a narrow platform service around `SMAppService`, bundle staging metadata, tests and setup documentation.

**Prompt:**

> Add an opt-in “Launch Notion PiP at login” setting using the public ServiceManagement API available on the project’s deployment target. Inspect application composition, Settings, staged bundle construction, and existing preference/service patterns first. Wrap `SMAppService` behind a small injectable main-actor service so state mapping and failures are testable. The toggle must reflect actual system registration state rather than a separate optimistic Boolean, explain when macOS requires user action, and recover if registration changes outside the app. Do not modify signing, entitlements, or system settings beyond the explicit toggle action. Confirm the feature works for the staged `.app`, not just a SwiftPM executable. Add tests for registered, unregistered, requires-approval, failure, repeated actions, and external state change. Update local-run and beta documentation with realistic ad-hoc-build limitations. Run the full Swift suite and manually verify enabling, disabling, relaunching, and the System Settings entry.

## Reliability and performance prompts

### 7. Recover the live Notion page after WebKit process termination

**Why it fits:** Quick Capture already has renderer recovery coverage, but the persistent live Notion session also needs a truthful recovery path when its WebKit content process exits.

**Likely areas:** `NotionWebSession`, lifecycle controller, page working-set restoration, native failure banner, selection/scroll restoration tests.

**Prompt:**

> Add explicit recovery for `webViewWebContentProcessDidTerminate` in the live Notion `WKWebView`. Inspect `NotionWebSession`, `NotionWebLifecycleController`, page working-set restoration, navigation-generation guards, retained selection/scroll behavior, and failure UI before changing code. Recovery must keep the same `WKWebView` object when WebKit permits, invalidate opaque or DOM-bound state that cannot survive termination, and reload only the current validated canonical Notion page. Attempt the existing bounded scroll fallback where safe, never replay a saved editor selection into a different document, and avoid reload loops when termination repeats. Surface a retryable native failure state after a bounded automatic attempt. Do not treat the persistent all-Spaces `NSPanel` as defective. Add tests for termination during idle, navigation, page switching, stash, failed reload, repeated termination, stale callbacks, and successful recovery without extra WebViews. Manually verify with WebKit process termination while signed in, including stashed and full-screen-Space cases. Run the full Swift suite.

### 8. Harden restoration across display topology changes

**Why it fits:** Multi-display loss is a beta stop-ship risk even after the recent panel geometry work; this prompt focuses on topology transitions rather than another sizing redesign.

**Likely areas:** panel/frame/stash policies, screen-change observation, coordinator ordering, deterministic geometry test fixtures, manual matrix.

**Prompt:**

> Audit and harden Notion PiP restoration across display topology changes. Begin from the current panel geometry and stash implementation on `origin/master`; do not redesign sizing again. Model transitions where a secondary display is disconnected, reconnected with a different identifier or scale, rearranged from left to right, or removed while the PiP is stashed, visible, zoomed, or hidden. Ensure exactly one panel and at most one handle remain reachable, preserve the best meaningful size and edge intent, clamp to a current visible frame without covering system UI, and never reload the live Notion page solely because screens changed. Separate pure topology/frame decisions from AppKit observation so tests use synthetic display fixtures and do not depend on the CI runner’s real screen. Add regression tests for every transition and stale/out-of-order notifications. Update the manual matrix with two-display evidence steps. Run the full Swift suite and manually verify disconnect/reconnect across Spaces.

### 9. Add recoverable persistent-store failure handling

**Why it fits:** The current health state can report that storage is unavailable, but an external beta needs a safe, explicit path that protects recoverable local captures.

**Likely areas:** persistence bootstrap, schema/container factory, capture export, service health, app startup composition, migration tests.

**Prompt:**

> Design and implement a recoverable persistent-store failure path for Notion PiP’s SwiftData stores. Inspect persistence bootstrap, schema migrations, service-health presentation, capture export/redaction, and startup composition before editing. Never silently delete or overwrite a failing store. On open or migration failure, preserve the original files, start only in an explicitly degraded mode, and offer user-controlled actions to export recoverable local capture data and reveal or archive the failed store before creating fresh storage. Pinned-page failure must not be confused with capture loss. Keep personal integration credentials in Keychain and out of diagnostics. Make destructive reset language exact and require an explicit confirmation; prefer moving files to a dated recovery location over deletion. Add injectable filesystem/store operations and tests for open failure, migration failure, partial sidecars, export success/failure, canceled recovery, repeated launch, fresh-store creation, and redaction. Document what is and is not recoverable. Run the full Swift suite and report the manual corruption simulation performed.

### 10. Build a deterministic delivery fault-injection matrix

**Why it fits:** The delivery engine has strong unit tests; the next reliability step is a coherent matrix that crosses scheduler, repository, API outcomes, relaunch, and user-visible status.

**Likely areas:** delivery engine/scheduler tests, repository test doubles, Notion API client fixtures, outbox presentation, reliability workflow.

**Prompt:**

> Build a deterministic end-to-end fault-injection test matrix for Quick Capture delivery without contacting Notion. Inspect `DeliveryEngine`, `DeliveryScheduler`, `CaptureRepository`, the capture delivery service, API client fixtures, outbox presentation, and current tests. Cover offline startup, connection loss during a multi-request delivery, 429 retry timing, retryable 5xx, permanent 4xx, ambiguous timeout after remote creation, duplicate-fingerprint reconciliation, app termination, relaunch recovery, stale claims, manual retry, and retention. Use an injected clock and scripted transport; do not add sleeps or order-dependent shared state. Assert both repository transitions and truthful user-facing summaries, including that no locally accepted capture disappears and no known delivered capture is intentionally duplicated. Consolidate test support only where it reduces duplicated behavior without hiding scenarios. Add the matrix to the appropriate CI or nightly workflow with bounded runtime. Run focused tests repeatedly and then the full Swift suite.

### 11. Self-heal shortcut registration after wake and session changes

**Why it fits:** Both panel and Quick Capture shortcuts are primary recovery paths, and Carbon registration can become unavailable or stale across system changes.

**Likely areas:** global shortcut registrar, runtime activation/service health, workspace/session notifications, menu-bar fallback, tests.

**Prompt:**

> Make both global shortcuts self-heal after wake, fast user switching, and relevant session changes. Inspect the Carbon registrar, `AppRuntime` registration paths, service-health state, menu-bar fallback, and shortcut tests. Add a narrow lifecycle coordinator that revalidates or re-registers shortcuts on supported public AppKit/Workspace notifications, coalesces bursts, and distinguishes a genuine conflict from a transient registration failure. Never remove the menu-bar fallback while the panel shortcut is unavailable. Validate that panel and Quick Capture shortcuts cannot be configured to the same chord and update both settings surfaces atomically when one registration fails. Avoid periodic polling. Add deterministic tests for sleep/wake bursts, success, persistent conflict, one-shortcut failure, settings changes during recovery, teardown, and stale callbacks. Manually verify sleep/wake and a conflicting shortcut registration. Run the full Swift suite.

### 12. Enforce performance and idle-resource budgets

**Why it fits:** Existing signposts provide observation points; the next step is preventing regressions while keeping the stashed accessory quiet.

**Likely areas:** performance signposter, test/benchmark harness, lazy presenters, WebKit activity, CI/reliability workflow, documentation.

**Prompt:**

> Establish reproducible performance budgets for launch, warm panel reveal, warm Quick Capture presentation, stashed idle CPU, and steady-state memory. Inspect existing `PerformanceSignposter` operations, lazy construction, build script telemetry mode, and reliability workflow. First define a local measurement protocol that separates cold and warm WebKit behavior and records machine/toolchain context. Add deterministic regression tests for work that can be asserted structurally—no eager Quick Capture WebView, no duplicate WebViews, no timers or repeated tasks while stashed—and a non-flaky benchmark script that reports distributions rather than failing on one sample. Introduce CI gating only for stable structural or generously bounded metrics; keep hardware-sensitive measurements advisory with artifacts. Never log page URLs, titles, captured text, workspace IDs, or tokens. Document budgets, sampling, and how to compare before/after traces. Run the full Swift suite and provide baseline measurements from the current machine.

## Architecture and maintainability prompts

### 13. Extract native editor transitions from `CaptureEditorSession`

**Why it fits:** The TypeScript editor already has a transition gate, while the native session still combines bridge transport, persistence, conflict state, lifecycle, focus, and WebKit hosting.

**Likely areas:** `CaptureEditorSession`, bridge protocol, lifecycle coordinator, conflict tests, WebKit test support.

**Prompt:**

> Refactor the native transition and conflict state machine out of `CaptureEditorSession` while preserving all behavior. Read the full session, TypeScript transition gate, bridge protocol, lifecycle coordinator, and nearby tests before proposing boundaries. Extract a small actor or value-driven state machine that owns legal transitions, revision/generation checks, in-flight operation identity, retry availability, and conflict resolution outcomes. Keep `CaptureEditorSession` as the main-actor WebKit/focus/bridge adapter. Define inputs and outputs so the state machine can be tested without `WKWebView`, and do not use `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, or broad protocol abstractions. Preserve autosave, stash, restore, renderer recovery, termination, and exact-once transition semantics. Move tests toward the new boundary while retaining a focused WebKit integration suite. Keep the diff behavior-neutral, run focused tests repeatedly, then run web tests/typecheck and the full Swift suite.

### 14. Create one versioned Swift–TypeScript bridge contract

**Why it fits:** The bridge is security- and durability-sensitive, but its message definitions are maintained independently across languages.

**Likely areas:** Swift bridge protocol, TypeScript protocol, a checked-in schema/fixture generator, build scripts, generated-asset verification.

**Dependencies:** Prefer completing #13 first so transport and state-machine responsibilities are clear.

**Prompt:**

> Replace independently maintained Swift and TypeScript Quick Capture bridge message definitions with one versioned, repository-owned contract. Inspect `CaptureBridgeProtocol.swift`, `Web/QuickCaptureEditor/protocol.ts`, canonical JSON rules, origin/frame validation, generated editor build, and cross-language tests. Choose the smallest auditable contract representation that can generate or rigorously validate both sides without adding a runtime dependency or weakening strict decoding. Preserve unknown-field policy, payload size limits, request IDs, revision semantics, canonical documents, and security checks. Generated files must be clearly marked, deterministic, committed only when appropriate, and verified in CI. Add golden fixtures shared across Swift and TypeScript for every request/reply kind plus malformed, future-version, oversized, duplicate, and unknown cases. Document the update workflow and failure diagnostics. Do not combine this with target splitting. Run generation twice to prove stability, run web tests/typecheck, verify committed assets, and run the full Swift suite.

### 15. Decompose `NotionWebSession` by responsibility

**Why it fits:** The live session is one of the largest production files and combines navigation policy, state restoration, selection, scripts, lifecycle recovery, and delegate plumbing.

**Likely areas:** `NotionWebSession`, lifecycle controller, navigation destination, selection/caret bridge, test support.

**Prompt:**

> Decompose `NotionWebSession` into focused collaborators without changing externally observable behavior. Read the entire file, its protocol surface, `NotionWebLifecycleController`, navigation/selection helpers, and the full session test suite first. Identify and extract only compiler-useful seams—for example navigation decision/policy, page-state restoration, and script-message coordination—while leaving the main-actor object as the `WKNavigationDelegate`/`WKUIDelegate` adapter and single owner of the live `WKWebView`. Collaborators must have narrow inputs, deterministic generation/cancellation rules, and no unsafe concurrency escapes. Preserve signed-in session continuity, one-WebView identity, URL validation, external routing, retained selection, scroll fallback, reload/re-pin behavior, and all failure banners. Avoid a cosmetic one-type-per-file shuffle. Add direct tests for extracted policy and retain integration tests for delegate ordering and WebKit behavior. Run historically timing-sensitive suites repeatedly, then the full Swift suite.

### 16. Replace `AppRuntime` reach-through with feature façades

**Why it fits:** `AppRuntime` is still a broad composition and observable-state surface even after controller extractions.

**Likely areas:** `AppRuntime` and extensions, Settings and menu roots, page/capture/shortcut controllers, composition in `NotionPiPApp`.

**Prompt:**

> Narrow `AppRuntime` behind feature-owned façades while preserving the current UI and composition contracts. Inspect all runtime members and call sites, existing controllers, `NotionPiPApp` composition, Settings, status menu, and runtime test support. Group only cohesive observable state and commands into small main-actor façades for page/panel, capture/connection, and shortcuts/service health; keep cross-feature orchestration explicit at composition boundaries. Views should depend on the narrowest object they use rather than reaching through a god object, but do not introduce a service locator, global singleton, or speculative generic architecture. Preserve public behavior, initialization ordering, recovery, cancellation generations, and test injectability. Migrate one vertical slice at a time with regression tests, and document any intentionally retained runtime responsibilities. Do not split SwiftPM targets in this change. Run focused runtime/UI-model tests and the full Swift suite.

### 17. Introduce dependency-enforcing SwiftPM targets

**Why it fits:** Module boundaries are valuable only after the source-level seams are clean enough to encode useful dependency direction.

**Likely areas:** `Package.swift`, source layout/imports, test target layout, access control, architecture documentation and CI.

**Dependencies:** Reassess after #13–16; do not start if the intended boundaries still require cycles or widespread `public` promotion.

**Prompt:**

> Introduce the first dependency-enforcing SwiftPM module boundary for Notion PiP, following `docs/MODULARITY_ROADMAP.md` and the current code rather than mechanically mirroring folders. Begin with a dependency graph, then extract only pure domain policies that can compile without SwiftUI, WebKit, SwiftData, or application composition. If that slice would require cycles, AppKit leakage beyond unavoidable value types, or widespread API promotion, stop with the dependency evidence and propose the narrower prerequisite instead of weakening the boundary. Keep the executable product, macOS 14 deployment, resources, signing flow, and test behavior unchanged. Prefer `package` access where appropriate, preserve Sendable/isolation contracts, and do not create empty wrapper targets. Move tests with the code they validate while retaining integration tests at the executable boundary. Document the allowed dependency direction. Build each target as it is introduced, run the complete Swift suite, run the staged-app build verification, and report target/import changes and any deferred boundary.

## Accessibility and interaction-quality prompts

### 18. Audit VoiceOver semantics across every surface

**Why it fits:** Keyboard and VoiceOver are release gates for an accessory that may have no Dock or menu-bar presence.

**Likely areas:** all SwiftUI/AppKit views, custom panel/handle controls, web editor ARIA, accessibility-focused tests and manual matrix.

**Prompt:**

> Perform a complete VoiceOver semantics audit of Notion PiP and implement the actionable fixes. Inventory onboarding, panel chrome, edge handle, page URL entry, switcher rows and pin actions, size menus, Quick Copy, Quick Capture editor/toolbar/slash menu/conflict recovery, Settings, service health, and outbox status. Check names, roles, values, hints, selected/expanded/busy states, grouping, action discoverability, reading order, and duplicate announcements. Preserve compact visual design and pointer behavior while ensuring every shortcut-only or hover-revealed action has an accessible equivalent. Add stable semantic constants or pure presentation models where they make regression tests meaningful; do not assert private SwiftUI hierarchy. Extend TypeScript ARIA tests for the bundled editor. Update the manual matrix with an exact VoiceOver pass. Run web tests/typecheck, rebuild generated assets if needed, run the full Swift suite, and report the manual VoiceOver observations that automation cannot prove.

### 19. Add keyboard focus traversal regression coverage

**Why it fits:** Multiple accessory windows, a live WebView, custom hover chrome, and global shortcuts create unusually subtle focus behavior.

**Likely areas:** window factories/presenters, page switcher, Settings, onboarding, Quick Capture, PiP chrome, focus test support.

**Prompt:**

> Define and enforce keyboard focus traversal contracts for every Notion PiP window. Inspect window roles/factories, existing focus tests, SwiftUI focus state, WebKit focus bridges, hover chrome, and command routing. Specify initial focus, Tab/Shift-Tab order, Escape behavior, default/cancel actions, focus restoration after dismissal, and behavior when Full Keyboard Access is enabled for onboarding, page URL entry, page switcher, Settings, Quick Capture, conflict recovery, and the live panel. Fix loops, traps, unreachable controls, and accidental focus theft without making the persistent panel a normal app window. Add regression coverage at the narrowest reliable layer plus targeted real-window/WebKit tests; keep tests independent and avoid assumptions about the CI display. Manually verify keyboard-only use across Spaces with VoiceOver both off and on. Run focused suites repeatedly and then the full Swift suite.

### 20. Complete system accessibility-preference support

**Why it fits:** Some chrome already respects Reduce Motion, but the full product should respond consistently to macOS accessibility display preferences.

**Likely areas:** design tokens, panel/handle transitions, onboarding, status/conflict colors, Quick Capture CSS, tests.

**Prompt:**

> Audit and complete support for macOS Reduce Motion, Increase Contrast, Differentiate Without Color, and Reduce Transparency across Notion PiP. Start from the existing Reduce Motion handling and semantic design tokens; do not replace system materials or colors gratuitously. Inventory every custom animation, opacity-only state, translucent surface, color-coded status, selection highlight, and web-editor CSS state. Disable or simplify nonessential motion, add shape/icon/text distinctions where color is currently the only signal, increase boundaries/contrast using semantic system values, and provide an opaque fallback where transparency harms legibility. Keep layout stable at compact PiP sizes and in light/dark appearance. Expose pure policy or token decisions for Swift tests, and add DOM/style tests for each Quick Capture state whose authored CSS changes. Run web tests/typecheck, rebuild assets, run the full Swift suite, and manually verify all preference combinations without claiming automated contrast tests prove the rendered result.

### 21. Announce capture and recovery state accessibly

**Why it fits:** “Saved locally,” “sending,” “delivered,” and “needs attention” are materially different states that must be understandable without watching visual badges.

**Likely areas:** capture status/outbox views, Quick Capture bridge status region, conflict/service health, delivery presentation models, accessibility notifications.

**Prompt:**

> Add deliberate, non-spammy accessibility announcements for Quick Capture persistence, delivery, conflict, and recovery state. Inspect the TypeScript editor status region, native capture/outbox presentation, delivery state model, service health, and VoiceOver tests. Define a small semantic state machine that distinguishes editing, saving locally, saved locally/queued, delivered, retry scheduled, permanent attention needed, and conflict. Announce only meaningful transitions, coalesce rapid autosave updates, never announce every keystroke, and never include captured text, page titles, URLs, workspace IDs, or tokens. Visual copy and accessibility copy must truthfully separate local durability from remote delivery. Ensure focus does not jump when status changes and repeated scheduler refreshes do not repeat announcements. Add Swift and TypeScript tests for transition mapping, deduplication, coalescing, errors, conflict resolution, and privacy. Manually verify with VoiceOver online, offline, and through a forced retry. Run web checks and the full Swift suite.

## Release and beta-readiness prompts

### 22. Build and verify the staged app bundle in CI

**Why it fits:** CI currently tests Swift and web code, but a beta can still fail because bundle assembly, resources, Info.plist metadata, or signing verification drift.

**Likely areas:** `script/build_and_run.sh`, a non-launch packaging mode or shared script library, CI workflow, version metadata.

**Prompt:**

> Add a CI-safe mode that builds and verifies the staged `dist/NotionPiP.app` without launching it or terminating a user process. Refactor `script/build_and_run.sh` only as needed to share deterministic package/verify steps while preserving all current local modes and their safety behavior. CI verification must check the executable, copied SwiftPM resource bundle, generated Quick Capture assets, bundle identifier, version/build values, minimum macOS, accessory status, URL scheme, entitlements, architecture, and ad-hoc code-signature integrity. It must fail with concise diagnostics and must not require a Notion token, signing certificate, Node for a fresh checkout beyond the existing web job, or a GUI session. Add a focused verification harness with fixtures for at least an invalid version, missing executable, missing editor asset, wrong bundle identifier, and failed signature verification. Run the new mode locally, run the full Swift suite, and update CI so pull requests exercise the staged artifact.

### 23. Add a Developer ID signing and notarization workflow

**Why it fits:** External beta distribution is blocked until an archive can be signed, notarized, stapled, and verified on a Mac that did not build it.

**Likely areas:** release scripts/workflow, entitlements and bundle verification, versioning documentation, GitHub environment/secrets documentation.

**Dependencies:** Complete #22 so packaging can be verified independently of release credentials.

**Prompt:**

> Add a secure, manually triggered Developer ID signing and notarization workflow for Notion PiP. Preserve the local ad-hoc development path. Inspect bundle construction, entitlements, version metadata, beta-readiness requirements, and current GitHub Actions permissions first. Separate deterministic unsigned packaging from credentialed signing. Use ephemeral keychain handling, `notarytool`, stapling, `codesign --verify --deep --strict`, and `spctl` assessment; never print certificates, passwords, profiles, tokens, or notarization responses containing sensitive values. Pin third-party actions by commit, use least permissions and an approval-protected release environment, validate that version/build values are intentional and the tree is clean, and upload checksummed artifacts plus verification evidence. Document required secret names and local verification without real secret values. Do not publish a release automatically in the first slice. Add safe script tests for missing configuration and run all credential-free checks locally; clearly report which signing/notarization steps require repository secrets and a clean-machine manual test.

### 24. Export a privacy-safe beta diagnostics bundle

**Why it fits:** Testers need a useful support artifact, but Notion content and credentials must not leak into it.

**Likely areas:** developer/service status, performance signposts/log collection, capture export redaction utilities, app commands/settings, tests and privacy docs.

**Prompt:**

> Add a user-invoked “Export Diagnostics…” action for beta support. Define an explicit allowlist rather than collecting arbitrary files or logs. Include app/version/build, macOS and hardware architecture, coarse display topology, service-health issue codes, shortcut registration outcomes, bounded performance metrics, crash-safe store/schema status, and redacted recent operational events. Exclude page URLs and IDs, titles, query strings, Notion/capture content, workspace identity, clipboard or Accessibility selections, cookies, web storage, tokens, Keychain data, and raw unified logs. Show a preview or manifest before save and let the user choose the destination. Reuse proven sanitization only where its contract fits; add a final secret-pattern and forbidden-field scan. Keep generation local and never upload automatically. Add deterministic tests for allowlisting, redaction, stable manifests, size bounds, cancellation, write failure, and malicious strings. Update privacy and beta-support documentation, run the full Swift suite, and manually inspect an exported bundle before handing it off.

### 25. Finish the external-beta handoff surface and smoke test

**Why it fits:** The beta checklist still requires installation guidance, support/privacy destinations, known limitations, and clean-account evidence.

**Likely areas:** README/beta docs, About/settings links, staged Info.plist metadata, manual test matrix, release checklist and smoke-test script where automation is safe.

**External input:** Actual support and privacy-policy URLs are required. The implementer must not invent or publish destinations if the project owner has not supplied them.

**Prompt:**

> Finish the repository-owned external-beta handoff surface for Notion PiP. Inspect `docs/BETA_READINESS.md`, the manual test matrix, staged Info.plist, Settings/About, README, setup instructions, and actual app behavior. Add accurate support and privacy links supplied by repository configuration, installation and first-launch instructions for a notarized build, uninstall/reset guidance that distinguishes app files from the user’s Notion account, known limitations, recovery steps, and a tester feedback template. Create a reproducible smoke-test checklist for a clean macOS 14+ user account covering install/Gatekeeper, accessory launch, sign-in, first pin, stash/restore, shortcuts and fallback access, relaunch, display changes, Quick Capture durability, offline retry, and keyboard/VoiceOver. Automate only bundle facts and noninteractive checks; leave account, Spaces, display, and accessibility evidence manual. Never request passwords, session cookies, or tokens in terminal/chat instructions. Update the readiness checklist with evidence fields rather than marking unperformed checks complete. Run all automated checks and report the remaining signing, clean-machine, and tester-owned gates.

## Dependency and parallelization guidance

The safest independent starting set is #6, #10, #12, #18, #22, and documentation-first portions of #25. The following chains should remain sequential:

1. **Named contexts:** #1 → #2; #5 may follow after the pin schema has settled.
2. **Capture internals:** #13 → #14; avoid running #3, #4, #13, #14, or #21 concurrently because they overlap bridge and session code.
3. **Application boundaries:** #13–16 → reassess → #17.
4. **Distribution:** #22 → #23 → credentialed clean-machine verification in #25.
5. **Window behavior:** avoid running #7, #8, #11, or #19 concurrently because they touch lifecycle/focus/presentation seams.

Before starting any item, run `git status --short`, inspect `git diff origin/master...`, and preserve unrelated changes. Product behavior changes require regression tests plus the manual checks named in the prompt. Architecture prompts are behavior-neutral and should not absorb adjacent features.

## Explicitly excluded ideas

This portfolio intentionally excludes multiple simultaneous PiP panels, background clipboard history, automatic foreground-app/browser/calendar following, a native Notion renderer/editor, a general launcher/action system, team collaboration, and AI summarization. Those ideas either contradict the product thesis, expand privacy exposure, or add complexity before the core glance/capture loops and beta distribution are proven.
