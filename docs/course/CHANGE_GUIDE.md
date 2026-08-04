# Notion PiP Change Guide

This is the maintainer playbook for deciding where a change belongs, changing it
safely, diagnosing failures, and selecting evidence that actually covers the
affected behavior. It complements the [architecture map](ARCHITECTURE_MAP.md),
[course navigation](README.md#course-navigation), and
[testing and debugging lecture](12-testing-debugging-and-change-workflow.md).

The source facts in this guide were revalidated against committed baseline
`33cdf42757a84ae0f15a465db318dcb63409ccc5`, not against uncommitted product or
test edits in the working tree. A link opens the current checkout, so re-run the
discovery commands and compare important contracts with
`git show 33cdf42:<path>` before implementing a later change.

The shortest safe rule is:

> Put the decision in the lowest layer that has enough information to make it;
> keep framework effects in their owning adapter; let App coordinate the two.

## Choosing the owning layer

Start with the earliest point where observed behavior diverges from its
contract. A wrong menu label can be a command-model defect rather than a view
defect. A correct rectangle followed by wrong Space placement is a platform or
window-server problem rather than a geometry-policy problem. Trace inputs and
outputs before choosing a file.

Use these questions in order:

1. Is the behavior deterministic from values alone? Start in **Domain**.
2. Is it a durable transaction or schema/reopen concern? Start in
   **Persistence**.
3. Does it coordinate delivery, retries, conversion, or HTTP through ports?
   Start in **Services**.
4. Does it combine user intent, published state, and multiple subsystems?
   Start in **App**.
5. Does it directly own AppKit, WebKit, Keychain, shortcuts, pasteboard, or
   system URLs? Start in **Platform**.
6. Is the contract correct and only its SwiftUI rendering or binding wrong?
   Start in **Views**.
7. Does it live in the Tiptap editor, DOM, or JavaScript side of the native
   bridge? Start in **Web**.

Cross-layer work is normal. It does not justify putting all behavior in the
highest layer. Define a narrow value or protocol at the boundary, keep actor
crossings explicit, and let the composition root know concrete implementations.
The [six runtime flows](ARCHITECTURE_MAP.md#flow-1--startup-and-dependency-composition)
show the existing direction.

### Domain

| Dimension | Contract |
|---|---|
| Inputs | Validated values, snapshots, policy parameters, and deterministic time or geometry values supplied by callers. |
| Outputs | New values, mutations, rankings, transitions, or typed errors with no external side effect. |
| Isolation | Prefer value semantics and `Sendable`. Most domain code needs no actor because it owns no mutable process-global state. |
| Examples | [`NotionPageReference`](../../Sources/NotionPiP/Domain/NotionPageReference.swift), [`PageWorkingSetPolicy`](../../Sources/NotionPiP/Domain/PageWorkingSetPolicy.swift), [`PageSwitcherMatcher`](../../Sources/NotionPiP/Domain/PageSwitcherMatcher.swift), [`RetryPolicy`](../../Sources/NotionPiP/Domain/RetryPolicy.swift), and [`CaptureExport`](../../Sources/NotionPiP/Domain/CaptureExport.swift). |
| Tests | Small table-driven XCTest cases with values in and exact values/errors out, such as [`PageSwitcherMatcherTests`](../../Tests/NotionPiPTests/PageSwitcherMatcherTests.swift) and the retry-policy cases in [`DeliveryEngineTests`](../../Tests/NotionPiPTests/DeliveryEngineTests.swift). |
| Exclusions | No database contexts, windows, WebViews, Keychain, network requests, `UserDefaults.standard`, or UI orchestration. |

Domain is the right owner for a reusable rule even when the visible symptom is
in a view. Two present exceptions explain why folder names are not absolute:
`DesignTokens` imports platform-aware color types, and page policies consume
`StoredPageSnapshot` values defined by persistence. Do not expand those seams
without first deciding whether a smaller value type would clarify dependency
direction. See [Lecture 7](07-domain-modeling-and-policies.md).

### Persistence

| Dimension | Contract |
|---|---|
| Inputs | Domain mutations, expected revisions, validated identifiers, snapshots, retention rules, and explicit store configuration. |
| Outputs | `Sendable` snapshots, committed revisions, ordered working sets, or typed transaction/conflict errors. |
| Isolation | SwiftData repositories are model actors with private model contexts. Save or roll back explicitly, and do not let `@Model` instances escape. Synchronous `UserDefaults` stores are a narrow exception. |
| Examples | [`NotionPiPPersistence`](../../Sources/NotionPiP/Persistence/NotionPiPPersistence.swift), [`PageRepository`](../../Sources/NotionPiP/Persistence/PageRepository.swift), [`CaptureRepository`](../../Sources/NotionPiP/Persistence/CaptureRepository.swift), [`QuickCaptureDestinationRepository`](../../Sources/NotionPiP/Persistence/QuickCaptureDestinationRepository.swift), and [`PanelSizePreferencesStore`](../../Sources/NotionPiP/Persistence/PanelSizePreferencesStore.swift). |
| Tests | Fresh in-memory containers for transaction policy; UUID-named temporary disk stores for reopen and migration; unique defaults suites for preference stores. See [`CaptureRepositoryTests`](../../Tests/NotionPiPTests/CaptureRepositoryTests.swift) and [`SchemaMigrationTests`](../../Tests/NotionPiPTests/SchemaMigrationTests.swift). |
| Exclusions | No SwiftUI presentation, AppKit ownership, remote delivery, browser navigation, or leaked mutable model objects. |

Use Persistence when the contract contains words such as *commit*, *revision*,
*rollback*, *reopen*, *migration*, *retention*, or *unique record*. In-memory
SwiftData cannot prove a migration. A migration test must close the old
container, reopen a temporary on-disk store through the intended schema path,
and clean up only its exact temporary directory. See [Lecture 8](08-persistence-and-restoration.md).

### Services

| Dimension | Contract |
|---|---|
| Inputs | Repository and transport protocols, domain snapshots, credentials supplied through a port, clocks, retry delays, and cancellation. |
| Outputs | Delivery receipts, state transitions, converted blocks, scheduled work, search results, and bounded user-safe failures. |
| Isolation | Actors or `Sendable` protocols own mutable asynchronous work. Use structured tasks, injected clocks, and explicit cancellation/ambiguity handling. |
| Examples | [`QuickCaptureLifecycleCoordinator`](../../Sources/NotionPiP/Services/QuickCaptureLifecycleCoordinator.swift), [`DeliveryScheduler`](../../Sources/NotionPiP/Services/DeliveryScheduler.swift), [`DeliveryEngine`](../../Sources/NotionPiP/Services/DeliveryEngine.swift), [`NotionCaptureDeliveryService`](../../Sources/NotionPiP/Services/NotionCaptureDeliveryService.swift), and [`NotionAPIClient`](../../Sources/NotionPiP/Services/NotionAPIClient.swift). |
| Tests | Protocol fakes that record requests, injected clocks/delays, continuations for ordering, and status/error fixtures. See [`DeliveryEngineTests`](../../Tests/NotionPiPTests/DeliveryEngineTests.swift) and [`NotionAPIClientTests`](../../Tests/NotionPiPTests/NotionAPIClientTests.swift). |
| Exclusions | No views, retained windows, browser cookies, direct SwiftData model access, or policy hidden inside a transport fake. |

Services own remote-work semantics, not credentials or UI. Notion cookies stay
inside the live browser session; the optional personal integration token stays
in Keychain; only the necessary credential value crosses the service port. A
timeout after a remote write may be *ambiguous*, not a safe automatic retry.
See [Lecture 10](10-notion-api-and-delivery.md).

### App

| Dimension | Contract |
|---|---|
| Inputs | View commands, platform callbacks, repository/service publications, validated routes, and dependency implementations supplied by composition. |
| Outputs | Observable UI state, unified activation, ordered coordination calls, degradation state, and facade methods used by views. |
| Isolation | Runtime and UI-facing controllers are `@MainActor`. Structured child tasks may call actors and return `Sendable` values; ordering requirements remain explicit. |
| Examples | [`AppRuntime`](../../Sources/NotionPiP/App/AppRuntime.swift), [`PinCoordinator`](../../Sources/NotionPiP/App/PinCoordinator.swift), [`PageSwitcherController`](../../Sources/NotionPiP/App/PageSwitcherController.swift), [`PanelSizeController`](../../Sources/NotionPiP/App/PanelSizeController.swift), and [`NotionPiPApp`](../../Sources/NotionPiP/App/NotionPiPApp.swift). |
| Tests | Runtime/controller tests with fake repositories, panels, presenters, pasteboards, shortcut registrars, and services. Reuse [`AppRuntimeTestSupport`](../../Tests/NotionPiPTests/AppRuntimeTestSupport.swift). |
| Exclusions | No low-level AppKit geometry, WebKit delegate implementation, SwiftData model mutation, HTTP serialization, or duplicated domain policy. |

App is the orchestration owner: it says *when* to persist, present, activate, or
publish, but delegates *how* to the appropriate layer. `AppComposition` is
allowed to know the concrete object graph; ordinary controllers should depend
on narrow protocols or closures. See [Lecture 4](04-composition-and-runtime.md).

### Platform

| Dimension | Contract |
|---|---|
| Inputs | App-level commands, validated URLs, snapshots, window roles, shortcut definitions, and service calls exposed through narrow closures. |
| Outputs | AppKit windows/panels, WebKit lifecycle and delegate events, global shortcuts, Keychain/defaults/system-URL effects, and framework-derived state. |
| Isolation | AppKit, SwiftUI hosting, and WebKit objects are `@MainActor`; adapters must respect framework callback lifetimes. Use actors only for genuinely independent mutable work. |
| Examples | [`PiPPanelCoordinator`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift), [`NotionWebSession`](../../Sources/NotionPiP/Platform/NotionWebSession.swift), [`CaptureEditorSession`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift), [`GlobalShortcutRegistrar`](../../Sources/NotionPiP/Platform/GlobalShortcutRegistrar.swift), and [`PersonalTokenCredentialVault`](../../Sources/NotionPiP/Platform/PersonalTokenCredentialVault.swift). |
| Tests | Extracted geometry/navigation/role policies, fake framework boundaries, constructed AppKit objects where reliable, local real-WebKit tests, and bounded manual matrix rows. |
| Exclusions | No product ranking/retention policy, delivery retry policy, view-owned local presentation state, or direct database mutation. |

Framework callbacks are evidence, not permission to collapse layers. Convert
them to small values or events, then call App. The floating all-Spaces panel and
accessory activation policy are intentional product behavior. Actual Spaces,
focus, Dock edges, displays, and assistive technology still require the
[manual matrix](../MANUAL_TEST_MATRIX.md). See [Lectures 5](05-panel-stashing-and-controls.md)
and [6](06-webkit-notion-session.md).

### Views

| Dimension | Contract |
|---|---|
| Inputs | Injected observable owners, bindings, immutable display values, local presentation state, and callbacks representing user intent. |
| Outputs | SwiftUI hierarchy, accessibility surfaces, and user actions routed to the injected owner. |
| Isolation | SwiftUI-facing work is main-actor-bound. Use `@ObservedObject` for an injected owner, `@StateObject` only for a view-created owner, `@Binding` for parent-owned values, and `@State` for local presentation. |
| Examples | [`SettingsView`](../../Sources/NotionPiP/Views/SettingsView.swift), [`PiPChromeView`](../../Sources/NotionPiP/Views/PiPChromeView.swift), [`PageSwitcherView`](../../Sources/NotionPiP/Views/PageSwitcherView.swift), and [`QuickCaptureView`](../../Sources/NotionPiP/Views/QuickCaptureView.swift). |
| Tests | Test controller state and callbacks first; use platform/menu construction tests where present; manually inspect layout, focus, keyboard access, and VoiceOver when those are the changed contract. |
| Exclusions | No direct persistence/network/window ownership, duplicated URL or policy validation, long-lived background tasks, or private source of truth shadowing App. |

If a control merely reflects and changes runtime state, the view should receive
a binding or action closure. If saving can fail or state has precedence rules,
the App owner exposes a method and publishes the authoritative result. See
[Lecture 11](11-views-settings-and-state.md).

### Web

| Dimension | Contract |
|---|---|
| Inputs | Native versioned replies, Tiptap transactions, owned DOM events, editor snapshots, and injected bridge dispatch. |
| Outputs | Exact versioned bridge requests, ProseMirror JSON, debounced changes, serialized transitions, and editor DOM/accessibility state. |
| Isolation | The JavaScript event loop owns editor state. Debounced publication and transition gates serialize acknowledgement-dependent work; native actors remain outside this layer. |
| Examples | [`QuickCaptureEditorController`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.ts), [`protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts), [`DebouncedChangePublisher`](../../Web/QuickCaptureEditor/bridge/debounced-change-publisher.ts), and [`EditorTransitionGate`](../../Web/QuickCaptureEditor/state/editor-transition-gate.ts). |
| Tests | `node:test` for state/protocol code, fresh `happy-dom` windows for owned DOM behavior, then Swift protocol, flow, and real local-WebKit tests for the packaged bridge. |
| Exclusions | No native repository or Keychain access, direct Notion API calls, assumptions about live Notion cookies, or hand edits to generated [`editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js). |

TypeScript authoring source and native decoding form one protocol contract. The
request ID, version, exact fields, origin/main-frame checks, one-megabyte bound,
revision, reply shape, and retry semantics must agree. Regenerate the checked-in
asset with `npm run build:editor`; never patch the generated bundle. See
[Lecture 9](09-quick-capture-editor-bridge.md).

## Safe change workflow

Follow this exact sequence:

**Dirty tree → tracing → tests → implementation → full checks → manual steps.**

Do not reorder it because a change appears small. A fast edit made before
source tracing can target a visible consumer instead of the owner.

### 1. Preserve and classify the dirty tree

```sh
git status --short
git diff --stat
git diff -- path/to/relevant/file
git diff --cached --stat
```

Label each existing edit as yours, the user's, or unknown. Do not discard,
rewrite, stage, format, or test-fix unrelated work. When existing edits overlap
the investigation, compare the committed authority without changing the tree:

```sh
git show HEAD:Sources/NotionPiP/Path/To/File.swift
git diff HEAD -- Sources/NotionPiP/Path/To/File.swift
```

Stop if safe ownership cannot be established. A build command is not read-only:
it may create artifacts, and the repository build script can terminate a
running app.

### 2. Trace the contract before editing

Write one line describing the behavior as:

```text
input/event → decision owner → actor/framework boundary → durable/UI output
```

Then locate definitions, call sites, tests, failure branches, and construction:

```sh
rg -n "TypeName|methodName|errorCase" Sources Tests Web
rg -n "TypeName\(" Sources/NotionPiP/App Tests
git log -S'methodName' --oneline -- Sources Tests Web
```

Record invariants: actor isolation, ordering, revisions, idempotency, validation,
secret handling, public API, macOS 14, signing/entitlements, and generated
resources. Use the [architecture map](ARCHITECTURE_MAP.md) to follow adjacent
flows, but let current source and tests win if course prose has drifted.

### 3. Add the smallest independent regression test

Choose evidence at the owning boundary. Confirm the new test fails for the
intended reason when practical, not because its fixture or toolchain is broken.

- Pure policy: values in, exact values/errors out.
- Controller/service: recording fake plus controlled clock, delay, or callback.
- Persistence: a fresh in-memory container; use a unique temporary disk store
  only for reopen or migration.
- Preferences: a UUID-named `UserDefaults` suite, never `.standard`.
- Bridge: TypeScript protocol/state tests plus native protocol/flow tests.
- Framework: extracted policy first; real local WebKit or constructed AppKit
  only when that boundary is part of the contract.

Swift tests may run in parallel. No test may depend on method order, shared
global state, a real credential, a live API, a fixed sleep, or another test's
cleanup.

### 4. Implement at the owner and keep the seam narrow

Make the minimum source change that satisfies the regression. Preserve Swift
6.2, macOS 14, public API, signing, entitlements, and generated-resource
contracts unless the task explicitly changes them. Prefer structured
concurrency, actor-owned mutation, and `Sendable` values. Do not silence a
compiler error with `@unchecked Sendable`, `nonisolated(unsafe)`, or a detached
task unless a documented invariant truly justifies it.

If multiple layers change, make their responsibilities legible at the call
site: Domain decides, Persistence commits, Services coordinate remote work,
App orchestrates, Platform performs framework effects, Views render intent,
and Web owns editor behavior.

### 5. Run focused and adjacent checks

Run the smallest relevant filter while iterating, then its affected neighbors:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter TypeName/testName
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter AdjacentTypeName
git diff --check
```

For TypeScript authoring changes, work from repository-pinned dependencies:

```sh
npm ci
npm test
npm run typecheck
npm run build:editor
git diff -- Sources/NotionPiP/Resources/QuickCapture/editor.js
```

`happy-dom` does not prove WebKit, and a real-WebKit filter does not replace the
Node state tests. Review the generated asset intentionally.

### 6. Run full relevant checks

Every Swift behavior change reaches the repository gate:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Web editor changes also reach `npm test`, `npm run typecheck`, and
`npm run build:editor`. Re-run `git status --short`, `git diff --stat`, and
`git diff --check` afterward. Inspect unexpected artifacts before staging them;
do not assume the tool meant to change them.

### 7. Perform build and manual steps only when the risk requires them

For bundle, resource, entitlement, signing, launch, window, WebKit, or shortcut
changes, first confirm the host/toolchain requirements in [`AGENTS.md`](../../AGENTS.md):

```sh
sw_vers -productVersion
test -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version
pgrep -x NotionPiP
```

If `NotionPiP` is running, ask the user to save work and quit it. The next
command terminates processes named `NotionPiP`, rebuilds, stages, ad-hoc signs,
launches, and verifies the development app:

```sh
./script/build_and_run.sh --verify
```

A success line identifies `dist/NotionPiP.app` and its PID. It is not a full
test-suite pass, notarization proof, or manual UI pass. Execute only affected
rows from the [manual matrix](../MANUAL_TEST_MATRIX.md), recording environment,
actual result, and untested combinations.

### 8. Review and hand off exact evidence

```sh
git diff --check
git status --short
git diff --name-only
git diff --cached --name-only
git diff --cached
```

Stage only intended paths. Report each command and result, relevant manual
observations, generated files, and every unverified integration. A focused
filter is evidence for that filter, not “all tests pass.”

## Diagnostic playbook

Begin with the exact observation, environment, last known good behavior, and a
small reproduction. Trace backward from symptom to the earliest wrong value or
effect. Logs can locate a boundary; they do not establish correctness. Never
include page content, cookies, tokens, passwords, or Keychain data in a command,
fixture, log, screenshot, or report.

| Branch | First evidence | Likely owner and next move | Do not do |
|---|---|---|---|
| Concurrency | Capture the compiler diagnostic or race ordering; `rg -n "Task|await|@MainActor|actor|Sendable"` around producer and consumer; run the smallest ordering test repeatedly through SwiftPM. | Domain values should cross boundaries as `Sendable`; Persistence/Services own actor mutation; App/Platform UI objects stay `@MainActor`. Add a controllable gate or continuation and assert ordering/cancellation. | Do not reach for `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, arbitrary sleeps, or main-actor annotations that merely hide ownership. |
| Migration | Identify source schema, target schema, store URL, reopen step, and actual model error. Inspect [`NotionPiPSchema.swift`](../../Sources/NotionPiP/Persistence/NotionPiPSchema.swift), container construction, and [`SchemaMigrationTests`](../../Tests/NotionPiPTests/SchemaMigrationTests.swift). | Persistence owns schema/version/transaction behavior. Reproduce with a unique temporary on-disk store created under the old schema, release it, then reopen through the supported path and assert values. | Do not infer migration safety from an in-memory test, delete the user's store, reuse one disk URL across parallel tests, or add silent data loss as recovery. |
| Bridge | Save one exact request/reply envelope and correlation ID; compare [`protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts), [`CaptureBridgeProtocol.swift`](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift), and nearby protocol tests. | Web owns request construction/state; Platform validates and dispatches; Persistence owns revisions. Check version, main frame, exact file origin/path, bounded ID/message, exact keys, request/result kinds, expected revision, and retry identity. | Do not relax exact-field/origin checks, treat a stale revision as a generic save failure, retry a state transition with new identity, or patch generated `editor.js`. |
| WebKit | Decide whether failure is local editor, live Notion session, navigation policy, lifecycle suspension, focus, or resource loading. Run the nearest `CaptureWebView...Tests` or `NotionWeb...Tests`; inspect `--logs` only after a staged reproduction. | Platform owns `WKWebView`, data store, delegates, lifecycle, and navigation; Web owns local editor state. Confirm the local editor uses its bounded file URL and non-persistent trust domain while the live Notion session retains its own cookies. | Do not ask for cookies, use live Notion DOM as a stable fixture, claim `happy-dom` proves WebKit, or broaden navigation/origin rules to make a test pass. |
| API and delivery | Record method/path/status, request ID if safe, `Retry-After`, local record state, and whether the remote write may have committed. Use transport fakes and run `NotionAPIClientTests`, `DeliveryEngineTests`, or scheduler tests as ownership indicates. | Services own serialization, error mapping, retry, scheduling, ambiguity, and cancellation; Persistence owns the durable outbox state. Distinguish 401/403 reconnection, 409 conflict, 429 backoff, 5xx retry, and a timeout after a possible write. | Do not call the live API in tests, log token/content, turn all errors into retries, or duplicate a possibly committed write merely because no reply arrived. |
| Build and signing | Run the four read-only host/toolchain checks from the safe workflow. Inspect actual build output, [`Package.swift`](../../Package.swift), [`build_and_run.sh`](../../script/build_and_run.sh), plist, resources, and `codesign -dv --verbose=4 dist/NotionPiP.app`. | Build configuration owns Swift/macOS constraints; the script stages resources, writes plist, applies sandbox/network entitlements, ad-hoc signs, and launches. Explain if existing `node_modules` triggered editor regeneration. | Do not install large tools, accept a license with `sudo`, change entitlements/signing, replace dependencies, or move `node_modules` without a concrete failure and approval. Ad-hoc signing is not notarization. |
| Accessory app seems hidden | Run `pgrep -x NotionPiP`; inspect verification output and bounded logs for termination. Then check the menu-bar icon preference, edge handle, and configured global shortcut. | App/Platform own accessory activation and reachability. No Dock icon is expected. A shortcut-registration failure temporarily forces the menu-bar icon visible; a stashed PiP remains reachable from its handle. | Do not report missing Dock presence or the persistent all-Spaces `NSPanel` as a crash/defect. Do not rebuild until active captures are saved and the running app is quit. |

Useful escalation order:

1. Reproduce at the smallest owner and record expected versus actual.
2. If the owner returns the correct value, inspect its caller's input mapping.
3. If local integration passes, expand one boundary: repository reopen, real
   WebKit, staged bundle, or affected manual row.
4. If the failure cannot be reproduced, report the missing environment/state
   instead of changing code speculatively.

For window-server, Spaces, focus, display, login-session, Launch Services, and
accessibility behavior, pair extracted policy tests with the relevant manual
matrix row. A passing rectangle test cannot prove Mission Control.

## Worked scenarios

The scenarios are templates, not pre-authorized product changes. Each starts by
revalidating source because paths, signatures, protocol versions, and invariants
can change after this guide's baseline.

### Beginner — policy edit: adjust page-switcher ranking

**Proposed behavior.** Suppose a product decision says a word-start title match
must rank above an otherwise equal interior subsequence, without changing empty
query grouping or deterministic tie-breakers.

**Discovery commands.** Run these before choosing an edit:

```sh
git status --short
rg -n "PageSwitcherMatcher|subsequenceScore|EqualScores|word" \
  Sources/NotionPiP Tests/NotionPiPTests
git show HEAD:Sources/NotionPiP/Domain/PageSwitcherMatcher.swift
git show HEAD:Tests/NotionPiPTests/PageSwitcherMatcherTests.swift
```

**Files and ownership.** The decision belongs in
[`PageSwitcherMatcher.swift`](../../Sources/NotionPiP/Domain/PageSwitcherMatcher.swift).
Its regression belongs in
[`PageSwitcherMatcherTests.swift`](../../Tests/NotionPiPTests/PageSwitcherMatcherTests.swift).
Read [`PageSwitcherController.swift`](../../Sources/NotionPiP/App/PageSwitcherController.swift)
and [`PageSwitcherView.swift`](../../Sources/NotionPiP/Views/PageSwitcherView.swift)
as consumers; do not edit them unless tracing proves their mapping or rendering
is independently wrong.

**Invariants.** Preserve case/diacritic/whitespace normalization, title matches
ahead of page-ID matches, pinned-before-recent ties, newer-before-older ties,
stable page-ID ordering, case-insensitive deduplication, active-row marking, and
the stored pinned/recent order for an empty query. The score must be
deterministic and independent of locale-sensitive mutable state.

**Tests first.** Add one pair of pages for which word-start and interior matches
previously tie or rank incorrectly. Assert exact ID order. Keep the existing
empty-query, normalization, title/ID precedence, and equal-score tests green.
Avoid testing a private numeric score; test the public section ordering.

**Implementation and verification.** Change only the scoring policy, then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter PageSwitcherMatcherTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
git diff --check
git diff -- Sources/NotionPiP/Domain/PageSwitcherMatcher.swift \
  Tests/NotionPiPTests/PageSwitcherMatcherTests.swift
```

No bundle or manual check is normally required for a pure ranking rule unless
the product request includes perceived search quality; if so, manually try the
agreed query corpus and report it separately.

**Source-revalidation warning.** Before editing, repeat the discovery search
and read current tests. If scoring moved, a new ranking contract appeared, or
the controller now post-processes results, stop and redraw the trace rather than
forcing this baseline's two-file plan.

### Intermediate — persisted setting: show developer diagnostics

**Proposed behavior.** Suppose Settings gains a “Show developer diagnostics”
toggle, defaulting off, and `DeveloperStatusView` becomes visible only when the
saved preference is on. This is a UserDefaults preference, not durable product
content, so it does not require a SwiftData schema migration.

**Discovery commands.** First copy the repository's existing preference and
binding patterns, not their names blindly:

```sh
git status --short
rg -n "MenuBarIconPreferenceStore|savedMenuBarIconVisibility|Binding\(|Toggle\(" \
  Sources/NotionPiP Tests/NotionPiPTests
rg -n "DeveloperStatusView|developer" Sources/NotionPiP/Views Tests
git show HEAD:Sources/NotionPiP/Platform/MenuBarIconPreferenceStore.swift
git show HEAD:Sources/NotionPiP/App/AppRuntime.swift
git show HEAD:Sources/NotionPiP/Views/SettingsView.swift
```

**Files and ownership.** A small preference adapter can follow
[`MenuBarIconPreferenceStore.swift`](../../Sources/NotionPiP/Platform/MenuBarIconPreferenceStore.swift)
or be generalized only if current call sites already justify it. App ownership
belongs in [`AppRuntime.swift`](../../Sources/NotionPiP/App/AppRuntime.swift):
load the saved value, publish one authoritative property, and expose a setter.
[`SettingsView.swift`](../../Sources/NotionPiP/Views/SettingsView.swift) renders
the binding; [`DeveloperStatusView.swift`](../../Sources/NotionPiP/Views/DeveloperStatusView.swift)
remains presentation. Add store tests and runtime/view-projection tests beside
the nearest existing examples. Planned filenames must be revalidated before
creating them.

**Invariants.** Default off when the key is absent; preserve an explicit saved
value across runtime recreation; use a namespaced stable key; never store
credentials or content in defaults; publish and mutate UI state on the main
actor; avoid a second view-owned source of truth. Decide the failure contract
before coding—`UserDefaults.set` has no transactional error result, so do not
invent “save succeeded” UI. Existing menu-bar forced-visibility precedence is
unrelated and must not be reused for this preference.

**Tests first.** Use a unique suite such as
`ChangeGuide.DeveloperDiagnostics.<UUID>` and remove its persistent domain in
cleanup. Prove absent → false, true/false round trips, runtime initialization,
setter persistence, and Settings action routing. Tests must not use
`.standard`, depend on order, or inspect private SwiftUI storage.

**Implementation and verification.** Implement store → App owner → view
projection in that order, keeping one source of truth. Then run the actual
new/adjacent test types discovered above, followed by:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter MenuBarIconPreferenceStoreTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter RuntimeActivationAndMenuBarTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
git diff --check
```

Manually relaunch the staged app only if the task requires UI/relaunch proof:
save active work, confirm `pgrep -x NotionPiP` is empty, run
`./script/build_and_run.sh --verify`, toggle the setting, relaunch, and record
visibility plus keyboard/VoiceOver behavior. Do not describe that as migration
coverage.

**Source-revalidation warning.** Re-run the searches before implementation. If
diagnostic visibility is already derived from service health, a new settings
owner exists, or preferences moved layers, integrate with that current owner.
Do not create a parallel store or runtime property based only on this scenario.

### Advanced — bridge extension: explicitly discard a draft

**Proposed behavior.** Suppose product and UX explicitly approve a destructive
“Discard draft” action after confirmation. The web editor requests it; native
code validates the request and revision; persistence deletes only the expected
active draft; the editor transitions only after an authoritative reply. This is
advanced because one semantic action crosses Web, Platform, Services, and
Persistence and must remain safe if an acknowledgement is lost.

**Discovery commands.** Trace both languages and the existing native lifecycle:

```sh
git status --short
rg -n "BridgeRequest|resolveConflict|stash|restore|requestTypes|makeRequest" \
  Web/QuickCaptureEditor Sources/NotionPiP/Platform Tests/NotionPiPTests
rg -n "discardDraft|QuickCaptureLifecycle|expectedRevision|transition" \
  Sources/NotionPiP Tests/NotionPiPTests Web/QuickCaptureEditor
git show HEAD:Web/QuickCaptureEditor/protocol.ts
git show HEAD:Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift
git show HEAD:Sources/NotionPiP/Platform/CaptureEditorSession.swift
```

**Files and ownership.** Likely authoring files are
[`protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts),
[`quick-capture-editor-controller.ts`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.ts),
and [`editor-transition-gate.ts`](../../Web/QuickCaptureEditor/state/editor-transition-gate.ts).
Native validation/dispatch belongs in
[`CaptureBridgeProtocol.swift`](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift)
and [`CaptureEditorSession.swift`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift).
Reuse the existing [`CapturePersistencePorts`](../../Sources/NotionPiP/Services/CapturePersistencePorts.swift),
[`QuickCaptureLifecycleCoordinator`](../../Sources/NotionPiP/Services/QuickCaptureLifecycleCoordinator.swift),
and [`CaptureRepository`](../../Sources/NotionPiP/Persistence/CaptureRepository.swift)
only if their current discard semantics match the approved contract. Update
TypeScript protocol/transition/controller tests, Swift bridge/flow/repository
tests, real-WebKit tests, and the generated editor asset.

**Invariants and design decision.** Require explicit user confirmation outside
the bridge; main-frame and exact local-file-origin validation; exact allowed
fields; bounded nonempty correlation ID; message-size limit; canonical document
rules where a snapshot is present; nonnegative expected revision; one active
transition; autosave drained or deliberately cancelled; no stale-revision
delete; and no success UI before durable deletion. Decide and document whether
this is a backward-compatible v1 addition or requires a version bump—do not
assume. Define duplicate/lost-ack behavior before implementation: an exact retry
must return a stable outcome or a specific already-discarded/not-found result,
not delete some newer draft. A failed or ambiguous reply must leave recovery
possible.

**Tests first.** In TypeScript, prove exact request construction, confirmation
routing, transition locking, pending-autosave behavior, success, recoverable
failure, duplicate reply, and exact retry identity. In Swift, prove version and
exact-key decoding, bad origin/frame/ID/revision rejection, dispatch to one
recording port, stale conflict, successful durable deletion, and lost-ack
reconciliation. In real WebKit, prove the packaged editor locks during discard,
does not show success before the native reply, and lands in the agreed state
after success/failure. Use a fresh repository/container per test.

**Implementation and verification.** Evolve TypeScript and Swift contracts
together. After focused Node and Swift filters pass, regenerate rather than edit
the bundle:

```sh
npm ci
npm test
npm run typecheck
npm run build:editor
git diff -- Sources/NotionPiP/Resources/QuickCapture/editor.js
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CaptureBridgeProtocolTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CaptureEditorFlowTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CaptureWebView
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
git diff --check
```

For manual proof, save all capture work and quit the running app before
`./script/build_and_run.sh --verify`. Exercise confirmed discard, cancel,
stale-revision recovery, rapid edit-before-discard, relaunch, keyboard focus,
and VoiceOver wording. Never use a real valuable draft as the fixture.

**Source-revalidation warning.** This scenario is intentionally conditional on
current product approval and current protocol semantics. If discard is already
owned entirely by close/finalization, the version changed, the transition gate
changed, or repository deletion is not retry-safe, stop. Redesign the protocol
and recovery contract from current source instead of appending a `switch` case.

## Verification ladder

Climb only as high as the change's risk requires, but never skip lower rungs.
Each rung answers a different question.

| Rung | Evidence | What it establishes | Required when |
|---:|---|---|---|
| 0 | `git status --short`, baseline comparison, source/call-site/test trace | The working tree is preserved and the proposed owner is based on current source. | Every change. |
| 1 | New focused regression and smallest existing filter | The owning rule fails before and passes after the implementation. | Every behavior change. |
| 2 | Adjacent controller/repository/service/protocol/WebKit filters | Values and effects still agree across each changed seam. | Any cross-file or cross-layer change. |
| 3 | Full `swift test`; plus Node test, typecheck, build, and generated diff for Web | The full relevant automated suites pass together under repository toolchains. | Every Swift behavior change; all Web steps for editor authoring changes. |
| 4 | `./script/build_and_run.sh --verify` after the process safety check | The development bundle stages, carries expected plist/resource/signature, launches, and survives the bounded startup gate. | Bundle/resource/signing/startup/WebKit/window/shortcut changes, or when explicitly requested. |
| 5 | Named rows from `docs/MANUAL_TEST_MATRIX.md` with environment and actual result | The affected behavior works in the real macOS/window-server/accessibility environment tested. | Spaces, displays, Dock edges, focus, shortcuts, lifecycle, live WebView, keyboard, or assistive-technology changes. |

Use this risk map to choose the top rung:

| Change | Minimum top rung |
|---|---:|
| Pure Domain rule | 3; manual only for a separately stated experience judgment |
| Repository transaction | 3 with fresh in-memory store |
| Schema, reopen, or relaunch persistence | 3 with temporary-disk coverage; 4/5 if real relaunch is part of acceptance |
| Service/API policy | 3 with transport fakes; manual live API only when explicitly authorized and safely scoped |
| App/View state projection | 3; 5 for visual, focus, keyboard, or VoiceOver acceptance |
| Platform window, shortcut, WebKit, resource, signing | 4 plus affected rung-5 rows |
| Web editor or bridge | 3 across Node + Swift + real WebKit, then 4/5 for packaged UI behavior |

Before claiming completion, capture this evidence:

```text
Changed contract:
Owning layer and traced seams:
Focused checks and results:
Full checks and results:
Build verification and staged path, or why not required:
Manual rows/environment/results, or explicitly not run:
Dirty/generated files reviewed:
Remaining concerns or unverified integrations:
```

Stop and report rather than improvise when the required Xcode/host is missing,
the running app contains unsaved work, a destructive or live external action
lacks approval, a dirty file's ownership is unknown, a migration would touch
user data, or current source invalidates the planned contract. Verification is
complete only when the report states both what passed and what it did not prove.
