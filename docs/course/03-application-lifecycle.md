# Lecture 3 — Application Lifecycle

**Duration:** 60 minutes

Perch uses an explicit AppKit entry point rather than a SwiftUI `App`
scene. That choice makes the process lifecycle visible in one short path:
construct the dependency graph, install an `NSApplicationDelegate`, start the
runtime, and hand control to AppKit's event loop. From then on, callbacks and
main-actor tasks coordinate launch, external URLs, UI work, persistence, and a
quit that may need to wait or be cancelled.

This lecture describes the committed repository snapshot. Unrelated unstaged
runtime changes present while the course was authored are outside that
snapshot. Keep the [course glossary](GLOSSARY.md) open for concurrency and
AppKit terms, and use the [architecture map](ARCHITECTURE_MAP.md#flow-1--startup-and-dependency-composition)
when a lifecycle callback crosses into another subsystem.

## Learning objectives

By the end of this lecture, you can:

1. Trace the executable entry from `PerchApp.main()` to
   `NSApplication.run()` and explain why `withExtendedLifetime` matters.
2. Distinguish process entry, dependency composition, runtime startup, and
   AppKit delegate callbacks.
3. Explain when the accessory activation policy is selected and why no Dock
   icon is intentional.
4. Trace an open-URL event that arrives before or after the runtime URL handler
   is bound.
5. Interpret the `ColdLaunchToReady` signpost without claiming that all
   asynchronous bootstrap work has completed.
6. Explain how `@MainActor`, actor-backed repositories, `Task`, `async`/`await`,
   cancellation, and `Sendable` values divide concurrency responsibilities.
7. Walk through coordinated termination, including Quick Capture's veto and
   ordered pinned-page persistence.
8. Separate unit-test evidence from behavior that still requires a real macOS
   event loop, Launch Services, window server, and login session.

The primary source trail is
[`PerchApp.swift`](../../Sources/Perch/App/PerchApp.swift),
[`AppDelegate.swift`](../../Sources/Perch/App/AppDelegate.swift),
[`AppRuntime.swift`](../../Sources/Perch/App/AppRuntime.swift), and
[`AppRuntime+Persistence.swift`](../../Sources/Perch/App/AppRuntime+Persistence.swift).

## Before you begin

You need the beginner-level distinction between synchronous work—one operation
finishes before the next starts—and asynchronous work, which can suspend while
another system finishes an operation. Prior AppKit experience is not required.

Use these terms consistently:

- The **executable entry point** is the `@main` declaration Swift invokes to
  start the process. Here it is the `PerchApp` enum, not a SwiftUI scene.
- The shared **`NSApplication`** object owns the macOS application event loop.
- An **application delegate** receives lifecycle and system callbacks on behalf
  of that application object.
- An **accessory application** participates without an ordinary Dock presence.
- The **main actor** serializes UI-bound state and framework objects.
- An **actor** owns mutable state behind an isolation boundary; callers use
  `await` when crossing that boundary.
- A **manual-verification boundary** marks a behavior that source and unit tests
  cannot prove without the real operating-system integration.

Before running repository commands, inspect `git status --short` and preserve
unrelated work. The source-reading exercise in this lecture does not require
launching the app, changing system configuration, or using a Notion secret.

**Manual-verification boundary:** unit tests can call delegate methods and
inspect replies, but they do not prove how Launch Services schedules a cold
URL delivery, how the Dock reflects accessory policy, or how a real login
session and window server react. Use the
[`MANUAL_TEST_MATRIX.md`](../MANUAL_TEST_MATRIX.md) for those checks.

## Foundation

### A process, an event loop, and callbacks

A command-line program often reads like a recipe: start at the first line,
perform work, and exit from the last line. A macOS application performs a short
startup recipe and then enters an **event loop**. The event loop waits for
events—launch milestones, menu commands, global shortcuts, URL handoffs,
window input, timers, and quit requests—and dispatches the matching callback.

That model changes how to read `main()`:

```text
synchronous setup                     long-lived event processing
──────────────────────────────────    ──────────────────────────────────
begin launch signpost                 applicationWillFinishLaunching
construct dependencies                applicationDidFinishLaunching
install delegate and menu      ───▶   application(_:open:)
start runtime and bind handlers       menu/shortcut/window callbacks
call NSApplication.run                applicationShouldTerminate
```

`application.run()` is not an initialization helper that immediately returns.
It transfers control to AppKit's event loop and normally remains active for the
life of the process. Code needed by later callbacks must therefore outlive the
synchronous setup stack.

### Four lifecycle responsibilities

The committed source keeps four responsibilities distinct:

1. [`PerchApp.main()`](../../Sources/Perch/App/PerchApp.swift)
   creates the process-level objects and enters the event loop.
2. `AppComposition` constructs and retains the concrete dependency graph. It
   is the course's **composition root**; Lecture 4 examines that graph.
3. `AppStartup.start` starts feature services and binds delegate-facing
   handlers without making the delegate know the concrete runtime.
4. [`AppDelegate`](../../Sources/Perch/App/AppDelegate.swift) translates
   AppKit lifecycle callbacks into the already-bound application behavior.

This division is useful because tests can call `AppStartup.start` and delegate
methods directly. The tests do not have to run a second process or replace the
real `NSApplication` event loop to verify buffering and termination policy.

### Isolation is ownership, not a queue of mystery threads

The glossary defines [`@MainActor`](GLOSSARY.md#main-actor-mainactor) as the
isolation domain for UI-bound state. `AppStartup`, `AppComposition`,
`AppDelegate`, `AppRuntime`, window presenters, and the performance signposter
are main-actor isolated. Their mutable state is serialized with AppKit UI work.

An actor-backed repository owns database mutation elsewhere. For example,
[`PageRepository`](../../Sources/Perch/Persistence/PageRepository.swift) is
a SwiftData `@ModelActor`, while
[`PageWorkingSetPersisting`](../../Sources/Perch/Persistence/PageWorkingSetStore.swift)
is `Sendable` and exposes asynchronous operations. Awaiting `workingSet()` or
`recordVisit(_:)` lets the main-actor task suspend; it does not justify touching
AppKit from the repository actor.

The boundaries are carried by value snapshots such as
[`StoredPageSnapshot`](../../Sources/Perch/Persistence/PageRepository.swift),
[`PageWorkingSetSnapshot`](../../Sources/Perch/Domain/PageWorkingSetSnapshot.swift),
and `DurablePageRestoration`, all declared `Sendable`. `Sendable` is a compiler
contract about safe transfer between isolation domains, not a promise that an
operation is fast, atomic, or automatically persisted.

## Repository tour

Read the lifecycle as a narrow vertical slice rather than treating every file
under `App` as one owner:

| Source | Lifecycle responsibility | Evidence to pair with it |
|---|---|---|
| [`PerchApp.swift`](../../Sources/Perch/App/PerchApp.swift) | `@main` entry, composition lifetime, startup binding, and concrete termination closure | [`RuntimeTerminationTests.swift`](../../Tests/PerchTests/RuntimeTerminationTests.swift) |
| [`AppDelegate.swift`](../../Sources/Perch/App/AppDelegate.swift) | Accessory policy, launch completion, buffered URL delivery, and deferred termination reply | [`PinCoordinatorTests.swift`](../../Tests/PerchTests/PinCoordinatorTests.swift) for delegate buffering; [`RuntimePinnedPagePersistenceTests.swift`](../../Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift) for startup race policy |
| [`AppRuntime.swift`](../../Sources/Perch/App/AppRuntime.swift) | Idempotent `start()`, shortcut registration, asynchronous bootstrap, recovery, and observable UI-facing state | [`RuntimeActivationAndMenuBarTests.swift`](../../Tests/PerchTests/RuntimeActivationAndMenuBarTests.swift) |
| [`AppRuntime+Activation.swift`](../../Sources/Perch/App/AppRuntime+Activation.swift) | External URL routing into the same validated page-activation path as other entry routes | [`ExternalURLRouteTests.swift`](../../Tests/PerchTests/ExternalURLRouteTests.swift) |
| [`AppRuntime+Persistence.swift`](../../Sources/Perch/App/AppRuntime+Persistence.swift) | Restored-page task, ordered visit-save chain, generations, cancellation, and termination wait | [`RuntimePinnedPagePersistenceTests.swift`](../../Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift) |
| [`AppCommandActionRelay.swift`](../../Sources/Perch/App/AppCommandActionRelay.swift) | Converts the shared Quit command into `NSApp.terminate(nil)`, which asks the delegate rather than bypassing it | [`AppCommandTests.swift`](../../Tests/PerchTests/AppCommandTests.swift) |
| [`AppWindowPresenter.swift`](../../Sources/Perch/Platform/AppWindowPresenter.swift) | Exposes a termination participant only after the lazy Quick Capture window exists; flushes only while that window is visible | [`AppWindowPresenterTests.swift`](../../Tests/PerchTests/AppWindowPresenterTests.swift) |
| [`CaptureEditorSession.swift`](../../Sources/Perch/Platform/CaptureEditorSession.swift) | Requests a fresh editor snapshot and can veto termination when its latest draft cannot be saved | [`CaptureWebViewLifecycleTests.swift`](../../Tests/PerchTests/CaptureWebViewLifecycleTests.swift) |
| [`PerformanceSignposter.swift`](../../Sources/Perch/Platform/PerformanceSignposter.swift) | Emits first-only OSLog intervals for lifecycle and first presentations | [`PerformanceSignposterTests.swift`](../../Tests/PerchTests/PerformanceSignposterTests.swift) |

Two ownership lines prevent misleading mental models:

- `AppDelegate` does not parse a Notion route or persist a page. It buffers
  opaque `URL` values until an `ApplicationURLHandling` object is available.
- `AppRuntime` does not mutate a SwiftData `ModelContext`. It awaits a narrow
  persistence protocol implemented by an actor and receives value snapshots.

The [architecture map's ownership table](ARCHITECTURE_MAP.md#subsystem-and-ownership-map)
uses the same terms: entry and composition own process wiring; runtime owns
activation coordination; AppKit owns lifecycle mechanics; persistence owns
durable transitions.

## Runtime trace

### `PerchApp.main()` to the event loop

The exact committed sequence is:

```text
PerchApp.main()
  1. AppPerformanceSignposter.shared.begin(.coldLaunchToReady)
  2. AppComposition.init()
  3. AppDelegate.init()
  4. NSApplication.shared
  5. application.delegate = appDelegate
  6. application.mainMenu = AppMainMenuFactory.make()
  7. AppStartup.start(runtime:appDelegate:...)
       a. runtime.start()
       b. bind cold-launch signpost
       c. bind async termination handler
       d. bind runtime as URL handler; drain any buffered URLs
  8. withExtendedLifetime(composition) { application.run() }
       └─ AppKit event loop dispatches delegate, menu, window, and input events
```

The order is significant. The shared application receives its delegate before
startup handlers are bound. `AppDelegate` is therefore prepared to retain an
early URL rather than dropping it. `AppStartup` calls `runtime.start()` before
binding that URL handler; draining a buffered route can then cancel or outrank
the asynchronous saved-page restoration begun by `start()`.

`withExtendedLifetime(composition)` is not decorative. The composition root
holds strong references to the runtime, status-item controller, presenters,
panel-size controller, and relays. Keeping it alive for the duration of
`application.run()` keeps the wired object graph available to callbacks.

### What `AppRuntime.start()` starts

[`AppRuntime.start()`](../../Sources/Perch/App/AppRuntime.swift) first uses a
`started` flag to make repeated calls no-ops. Its first call:

1. registers the panel shortcut;
2. registers the Quick Capture shortcut;
3. stores a `bootstrapTask` for the saved personal-token connection;
4. creates another task to load the saved capture destination, trigger delivery
   recovery, and refresh capture history in sequence; and
5. begins saved-page restoration.

These asynchronous tasks may still be running when AppKit reports launch
completion. The UI can also start in a degraded state: the composition root
may inject unavailable persistence dependencies and a
`persistentStoreUnavailable` health issue. Launching successfully therefore
does not mean every optional service is healthy.

### Event-loop branches after setup

Once `application.run()` owns control, three lifecycle branches matter here:

```text
launch callback
  applicationWillFinishLaunching ──▶ NSApp.setActivationPolicy(.accessory)
  applicationDidFinishLaunching  ──▶ log launch; end cold-launch interval

URL callback
  application(_:open:) ──▶ handler exists? ── yes ─▶ runtime.handleOpenURLs
                                    │
                                    no
                                    ▼
                             append to URL buffer
                             (later bind drains once)

quit callback
  NSApp.terminate ──▶ applicationShouldTerminate ──▶ .terminateLater
                                  │
                                  ▼
                        one main-actor Task awaits
                        capture flush + runtime saves
                                  │
                                  ▼
                     reply(toApplicationShouldTerminate:)
```

This is event-driven, not polling. The delegate does not repeatedly ask macOS
whether a URL or quit exists. AppKit invokes the relevant method, and the
delegate either routes the event synchronously or starts one bounded
asynchronous coordination task.

## Deep dive

### Accessory policy has two cooperating declarations

During `applicationWillFinishLaunching`, the delegate calls
`NSApp.setActivationPolicy(.accessory)`. This produces the runtime no-ordinary-
Dock role described in the [glossary](GLOSSARY.md#accessory-application). The
staged app also has `LSUIElement = true` in the `Info.plist` generated by
[`build_and_run.sh`](../../script/build_and_run.sh). Bundle metadata describes
the app to macOS at launch; the delegate explicitly selects the matching
activation policy during the process lifecycle.

Neither mechanism creates or owns the floating panel. Panel roles, all-Spaces
behavior, and the edge handle belong to later AppKit platform controllers. An
absent Dock icon and a persistent all-Spaces panel are intentional product
behavior, not evidence that `NSApplication` or `NSPanel` failed.

**Manual-verification boundary:** calling the delegate method in a test can
verify source intent but cannot prove what the Dock, app switcher, menu bar,
Mission Control, or full-screen Spaces visibly do on a particular macOS build.

### Buffered open URLs preserve an early handoff

`AppDelegate` holds an optional `ApplicationURLHandling` reference and a
`[URL]` buffer. Its behavior has two paths:

1. If AppKit calls `application(_:open:)` before binding, all URLs in that
   callback are appended in arrival order.
2. The first `bind(urlHandler:)` stores the handler, copies and clears the
   buffer, then forwards the whole buffered array once. Later callbacks go
   straight to the handler. A second bind is ignored.

The runtime conforms to `ApplicationURLHandling`. It asks the pin coordinator
for valid external pages, then sends each accepted page through normal
`activate(page:source:)` with an `.externalRoute` source. Parsing is deliberately
outside the delegate and is constrained by
[`ExternalURLRoute`](../../Sources/Perch/Domain/ExternalURLRoute.swift).
Buffering preserves delivery; it does not make an untrusted URL valid.

Two regressions prove different boundaries. `PinCoordinatorTests`
[`testAppDelegateBuffersOpenURLsUntilBindingAndDrainsOnlyOnce`](../../Tests/PerchTests/PinCoordinatorTests.swift)
proves the delegate's opaque URL buffer and one-time drain directly. Separately,
[`testBufferedOpenURLWinsOverDelayedRestoreDuringStartup`](../../Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift)
passes an early route through `AppStartup`: the route activates and persists,
while runtime generation/cancellation checks reject a delayed stored-page
result. The second test proves application-level restore ordering; neither test
claims to exercise real Launch Services.

### The cold-launch interval measures a specific milestone

The first executable operation begins
`.coldLaunchToReady` through the shared
[`AppPerformanceSignposter`](../../Sources/Perch/Platform/PerformanceSignposter.swift).
The returned `PerformanceIntervalToken?` is bound into the delegate and ended
with `.success` in `applicationDidFinishLaunching`.

Interpret the name using its endpoints, not intuition:

```text
begin: first line of PerchApp.main()
  │ dependency construction, delegate/menu installation, runtime start
  ▼
end: AppDelegate.applicationDidFinishLaunching
```

It does **not** wait for saved-page restoration, token bootstrap, destination
loading, delivery recovery, capture-history refresh, first PiP presentation,
or first Quick Capture presentation. Those tasks may continue, and the two
first-presentation operations have separate signposts.

Each `PerformanceOperation` begins only once per signposter instance. A
duplicate `begin` returns `nil`; ending `nil`, an unknown token, or an already
ended token is safely ignored. The signpost test verifies this idempotence. The
source currently records a success end at AppKit launch completion and has no
failure/cancellation end for an aborted process startup.

### Main actor, tasks, actors, and `Sendable`

The concurrency path is easiest to read as an ownership table:

| Mechanism | What it owns here | What it does not imply |
|---|---|---|
| `@MainActor` | Delegate state, runtime publications, AppKit objects, presenters, composition wiring | That every awaited operation executes on the main thread |
| `Task { ... }` created from main-actor code | A cancellable unit that inherits actor context and can suspend at `await` | A detached background thread or automatic ordering with sibling tasks |
| Repository actor / `@ModelActor` | Serialized mutable persistence state and its SwiftData `ModelContext` | Permission to mutate UI state directly |
| `Sendable` value or protocol | A compiler-checked value/reference contract for crossing isolation boundaries | Deep copying, durability, or business validation by itself |
| `async`/`await` | An explicit suspension point while another isolation domain or operation progresses | Blocking the AppKit event loop for the whole wait |

`AppRuntime.start()` launches independent bootstrap work because token setup,
destination/delivery/history work, and page restoration do not need one giant
serial startup chain. Within a chain, order is explicit. Destination loading
precedes the delivery trigger and capture refresh. For pinned pages,
`enqueuePersistence` captures the prior `persistPinnedPageTask` and awaits it
before calling `recordVisit`, preserving activation order even if repository
work suspends.

Cancellation and generations solve different races:

- Cancelling `restorePinnedPageTask` asks obsolete restore work to stop.
- `Task.isCancelled` checks prevent work from being published after the
  cancellation was observed.
- `pageSelectionGeneration` prevents an older restore result or empty-result
  Settings presentation from winning after a newer direct activation.
- `persistenceGeneration` lets termination notice that another save was
  enqueued while it awaited the previous tail and then await the newer tail.

No detached task or unsafe concurrency escape is needed in this path. UI
updates remain main-actor isolated; actor calls exchange `Sendable` snapshots.

### Coordinated termination is an asynchronous handshake

The shared Quit command calls `NSApp.terminate(nil)`. AppKit then asks
`AppDelegate.applicationShouldTerminate`. The delegate cannot synchronously
wait for WebKit and actor-backed persistence, so it follows AppKit's deferred
reply protocol:

1. If a termination task already exists, return `.terminateLater` without
   starting another task.
2. Otherwise create one `Task { @MainActor ... }` and return `.terminateLater`.
3. The handler bound by `AppStartup` asks the current lazy Quick Capture
   presenter for a termination participant.
4. If a participant exists and its window is visible, it requests a fresh
   editor snapshot and attempts to persist the latest draft. Success returns
   `true`; failure returns `false` and publishes a failure status.
5. Regardless of that Boolean, `runtime.prepareForTermination()` awaits the
   ordered pinned-page persistence chain. If a newer save appears during the
   wait, the generation check loops and awaits the new tail.
6. The closure returns the capture result. The delegate replies to AppKit with
   that Boolean and clears its task so a vetoed quit can be retried.

The combined flow is:

```text
quit request
   │
   ├─ visible, live Quick Capture? ─ yes ─▶ fresh snapshot + draft save
   │                                      └─ result: allow or veto
   │
   └─ no participant/hidden window ───────── result: allow
                         │
                         ▼
              await every ordered page save
                         │
                         ▼
        reply to AppKit with capture's allow/veto result
```

This ordering protects both kinds of local work. A capture failure vetoes
termination, but page-save draining still finishes before AppKit receives the
`false` reply. A page save failure reports degraded service health but does not
veto termination; the runtime waits for the attempt to finish. If the Quick
Capture window was never created or is hidden, its presenter contributes no
flush or veto.

[`RuntimeTerminationTests`](../../Tests/PerchTests/RuntimeTerminationTests.swift)
prove that repeated quit requests share one live capture flush, a failed flush
permits a later retry, termination waits for pending and newly enqueued page
saves, and a failed page save still produces a reply. The WebKit lifecycle
tests separately prove fresh-snapshot success and failure behavior. Together
they are strong component evidence, but force-quitting, process crashes, power
loss, and an operating-system kill cannot participate in this graceful async
handshake.

## Common misconceptions and failure modes

| Misconception or symptom | Correct lifecycle model | First source or test to inspect |
|---|---|---|
| “This must be a SwiftUI `App` because the UI uses SwiftUI.” | The executable has an explicit `@main` enum and an AppKit run loop; SwiftUI supplies views later. | [`PerchApp.swift`](../../Sources/Perch/App/PerchApp.swift) |
| “`NSApplication.run()` completes startup and returns.” | It enters the long-lived event loop; callbacks happen while it is running. | `PerchApp.main()` and `withExtendedLifetime` |
| “No Dock icon means launch failed.” | Accessory policy is selected intentionally before launch finishes and is paired with `LSUIElement`. | [`AppDelegate.swift`](../../Sources/Perch/App/AppDelegate.swift), manual matrix |
| “`applicationDidFinishLaunching` means restoration and delivery finished.” | It ends the cold-launch signpost, while runtime bootstrap tasks may still be suspended or running. | [`AppRuntime.start()`](../../Sources/Perch/App/AppRuntime.swift) |
| “`ColdLaunchToReady` measures first visible PiP.” | Its end is `applicationDidFinishLaunching`; first PiP presentation has a different operation. | [`PerformanceSignposter.swift`](../../Sources/Perch/Platform/PerformanceSignposter.swift) |
| “The delegate validates and pins external URLs.” | It only buffers/routes URLs. Runtime and domain parsing own validation and activation. | [`AppRuntime+Activation.swift`](../../Sources/Perch/App/AppRuntime+Activation.swift), [`ExternalURLRoute.swift`](../../Sources/Perch/Domain/ExternalURLRoute.swift) |
| “An early URL can be overwritten by delayed restoration.” | Direct activation cancels restore and changes the selection generation; stale restore publication is rejected. | Buffered-route and delayed-restore tests |
| “Every `Task` runs in parallel on a background thread.” | Tasks inherit actor context unless explicitly changed, suspend at awaits, and need explicit sequencing when order matters. | [`AppRuntime.swift`](../../Sources/Perch/App/AppRuntime.swift), [`AppRuntime+Persistence.swift`](../../Sources/Perch/App/AppRuntime+Persistence.swift) |
| “`Sendable` makes a database object thread-safe.” | The app transfers `Sendable` snapshots; the actor retains ownership of mutable SwiftData models and context. | [`PageRepository.swift`](../../Sources/Perch/Persistence/PageRepository.swift) |
| “Quit is immediate after `NSApp.terminate`.” | AppKit receives `.terminateLater` until capture and page preservation complete. | [`RuntimeTerminationTests.swift`](../../Tests/PerchTests/RuntimeTerminationTests.swift) |
| “A failed page save cancels quit.” | Runtime waits for the attempt and reports health; only the visible Quick Capture participant returns the quit Boolean. | `AppStartup` termination closure and termination tests |
| “A force quit runs the same cleanup.” | Graceful delegate coordination is not guaranteed for force quit, crash, power loss, or termination by the OS. | Manual/recovery testing, not the delegate handshake |

When debugging, first identify the phase: synchronous entry, AppKit callback,
main-actor runtime task, actor call, or deferred termination reply. “Startup is
broken” is too broad to locate an owner.

## Presenter notes

### Suggested 60-minute pacing

- **0–7 minutes:** contrast a recipe-style program with an event-loop program.
- **7–17 minutes:** source tour from `@main` through `application.run()`.
- **17–26 minutes:** accessory policy, launch callbacks, and cold-launch
  signpost endpoints.
- **26–35 minutes:** draw the early-URL buffer and delayed-restore race.
- **35–45 minutes:** explain main-actor UI ownership, repository actors,
  inherited tasks, cancellation, generations, and `Sendable` snapshots.
- **45–54 minutes:** walk the deferred termination handshake and its two local
  preservation paths.
- **54–60 minutes:** knowledge check and exercise setup.

### Board plan and demonstration cues

Draw one horizontal line labeled `main()` ending at `application.run()`, then a
large loop to its right. Put launch, URL, and quit callbacks on that loop. This
prevents beginners from imagining that delegate callbacks occur as ordinary
statements after `run()`.

For the source demonstration:

1. Start in `PerchApp.main()` and number its statements.
2. Jump to `AppStartup.start` and identify the runtime-start/bind order.
3. Open `AppDelegate` and follow each of the three callback branches.
4. Use the buffered-route regression to show a race as an executable policy.
5. End with `applicationShouldTerminate`, then follow the closure back through
   `AppStartup`, `AppWindowPresenter`, and `AppRuntime.prepareForTermination`.

Do not launch the app merely to demonstrate source ordering. If a live demo is
planned, save work and quit any running instance before rebuilding. Explain in
advance that no Dock icon is expected, and use the menu-bar item or configured
shortcut. Treat actual Launch Services URL delivery, Dock/accessory presence,
focus, and graceful quit UI as manual observations rather than unit-test facts.

If time is short, keep three traces: `main()` to event loop, buffered URL to
normal activation, and `.terminateLater` to the final reply. Defer detailed
composition internals to Lecture 4.

## Knowledge check

1. Why does `main()` wrap `application.run()` in `withExtendedLifetime`?
2. At what callback does the process select `.accessory`, and what user-visible
   expectation follows?
3. What happens if an open-URL callback arrives before `AppStartup` binds the
   runtime?
4. Does ending `ColdLaunchToReady` prove that page restoration and delivery
   recovery finished? Why or why not?
5. Why can the main-actor runtime await `PageRepository` without giving the
   repository permission to mutate AppKit objects?
6. What are the different jobs of cancellation and `pageSelectionGeneration`
   during restoration?
7. Why does `applicationShouldTerminate` return `.terminateLater` even when no
   Quick Capture window exists?
8. Which failure can veto graceful termination: a Quick Capture fresh-snapshot
   save failure, a pinned-page save failure, or both?
9. What do repeated quit requests do while one termination task is live?
10. Name two lifecycle claims that still require manual verification.

### Answers

1. `AppComposition` strongly retains the wired runtime, presenters,
   controllers, and relays. Extending its lifetime across the event loop keeps
   those callback dependencies alive.
2. `applicationWillFinishLaunching` calls
   `NSApp.setActivationPolicy(.accessory)`. The app intentionally has no
   ordinary Dock presence; users reach it through its panel, handle, menu-bar
   item, or shortcuts.
3. The delegate appends the URLs to its buffer. The first URL-handler bind
   copies and clears that buffer, then forwards the URLs once to the runtime.
4. No. The interval ends at `applicationDidFinishLaunching`, while independent
   runtime tasks for restoration, connection, destination, delivery, and
   capture history can still be in progress.
5. Actor isolation preserves ownership. The main-actor task suspends while the
   repository actor performs its work, then receives `Sendable` value
   snapshots; the repository actor never acquires UI ownership.
6. Cancellation requests that obsolete work stop and is checked inside the
   task. The generation value rejects a stale result even when timing allowed
   the actor call to complete before cancellation took effect.
7. Runtime page persistence is asynchronous too. The delegate always uses one
   deferred handshake so it can await the bound termination handler and reply
   to AppKit afterward.
8. The visible Quick Capture participant's fresh-snapshot save failure returns
   `false` and vetoes quit. A page save failure reports degraded health, but
   after the attempt finishes the runtime does not veto.
9. They receive `.terminateLater` and share the existing task; the delegate
   does not start a duplicate capture flush. After a final reply, the task is
   cleared, so a vetoed quit can be retried.
10. Examples include actual Dock/accessory appearance, real Launch Services
    URL timing, menu-bar availability, window-server/focus behavior, and the
    visible system response to graceful termination.

## Hands-on exercise

### Exercise: annotate one event-loop trace

Without changing source, create a scratch timeline for this scenario:

1. macOS launches Perch because it received a valid
   `perch://pin` URL.
2. The URL reaches `AppDelegate` before its runtime handler is bound.
3. `AppStartup.start` begins a delayed saved-page restore and then binds the
   runtime.
4. The user opens Quick Capture, edits during its debounce window, and chooses
   Quit while a newer pinned-page save is also queued.
5. The capture snapshot saves successfully and all page saves finish.

For every step, record:

- the callback or method name;
- the current owner (`NSApplication`, delegate, main-actor runtime/presenter,
  WebKit session, or repository actor);
- whether the step is synchronous, starts a task, or crosses an `await`;
- the value or event crossing the boundary; and
- the source or test that establishes the behavior.

Use focused searches to locate the symbols:

```sh
rg -n "static func main|applicationWillFinishLaunching|applicationDidFinishLaunching" \
  Sources/Perch/App
rg -n "bufferedOpenURLs|handleOpenURLs|pageSelectionGeneration" \
  Sources/Perch/App Tests/PerchTests
rg -n "applicationShouldTerminate|prepareForTermination|persistenceGeneration" \
  Sources/Perch Tests/PerchTests
```

Do not edit production files. Compare source before test names so your timeline
describes behavior, not merely assertion vocabulary.

### Expected answers and observations

A complete trace should contain these transitions:

```text
PerchApp.main begins signpost and installs delegate
  └─ early application(_:open:) stores URL in AppDelegate.bufferedOpenURLs

AppStartup.start
  ├─ AppRuntime.start creates asynchronous restore/bootstrap work
  └─ bind(urlHandler:) drains URL to AppRuntime.handleOpenURLs
       └─ validated route activates direct page
            ├─ cancels/invalidates stale restore
            └─ enqueues ordered page persistence on repository actor

applicationWillFinishLaunching selects accessory policy
applicationDidFinishLaunching ends the cold-launch interval

NSApp.terminate → applicationShouldTerminate returns .terminateLater
  └─ one main-actor termination task
       ├─ visible Quick Capture fresh snapshot crosses WebKit/native boundary
       │    └─ capture repository actor saves; result is true
       ├─ runtime awaits current and newly enqueued page-save tails
       └─ delegate replies true to NSApplication
```

The direct URL should remain active even if the older restore later returns.
The URL buffer itself does not validate the route. The cold-launch interval can
end before either preservation chain in the later quit scenario. The final
termination reply occurs only after capture and runtime preservation have both
completed.

As an extension, change only the scratch scenario so the capture save fails.
The page-save chain still drains, the delegate replies `false`, the process
stays alive, and a later quit request may create a new termination task.

## Recap

- `PerchApp.main()` performs explicit AppKit setup and then enters the
  long-lived `NSApplication` event loop.
- `AppComposition` is retained across that loop; `AppStartup` starts runtime
  work and binds lifecycle handlers; `AppDelegate` adapts AppKit callbacks.
- Accessory activation is intentional and is selected before launch finishes.
- Early open URLs are buffered, drained once after binding, validated outside
  the delegate, and routed through normal activation. Generations and
  cancellation keep stale restoration from winning.
- `ColdLaunchToReady` measures entry to `applicationDidFinishLaunching`, not
  completion of every asynchronous bootstrap or first presentation.
- Main-actor objects own UI coordination, repository actors own mutable
  persistence, tasks express cancellable async work, and `Sendable` snapshots
  cross isolation boundaries.
- Graceful quit is a deferred AppKit handshake: one task flushes a visible
  Quick Capture, awaits all ordered page-save work, and then replies allow or
  veto.
- Unit tests establish lifecycle policy and race handling. Launch Services,
  Dock/accessory appearance, the window server, focus, and real process
  termination remain manual-verification boundaries.

Next, Lecture 4 in the [course navigation](README.md#course-navigation) opens
the composition root and explains how concrete dependencies, relays,
presenters, controllers, and the runtime facade fit together.
