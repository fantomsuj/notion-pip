# Notion PiP Glossary

Use this alphabetized reference while reading the course. Definitions describe
how the term is used in this repository; each entry links to a concrete source
example rather than treating the framework concept in isolation. See the
[architecture map](ARCHITECTURE_MAP.md) when a term participates in an
end-to-end flow.

## A

### Accessory application

An AppKit application activation policy for a UI that runs without an ordinary
Dock presence. Notion PiP deliberately selects `.accessory`; its menu-bar icon,
global shortcut, floating panel, and edge handle are the intended access paths.
See [`AppDelegate.applicationWillFinishLaunching`](../../Sources/NotionPiP/App/AppDelegate.swift).

### Actor

A Swift reference type that serializes access to its isolated mutable state.
Notion PiP uses actors for repositories, delivery, and capture lifecycle work
that can be called asynchronously from the main-actor UI. See
[`DeliveryEngine`](../../Sources/NotionPiP/Services/DeliveryEngine.swift).

### AppKit

The macOS UI framework that owns application lifecycle, windows, panels,
status items, and event integration beneath the SwiftUI views. See the AppKit
panel implementation in
[`PiPPanelCoordinator.swift`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift).

### Autosave acknowledgement

The reply that confirms a debounced editor change reached native persistence.
The TypeScript editor retains a failed request for explicit retry and treats a
stale-revision reply as a transition-stopping conflict rather than pretending
the change was saved. See
[`DebouncedChangePublisher`](../../Web/QuickCaptureEditor/bridge/debounced-change-publisher.ts).

## B

### Bridge (Swift–JavaScript)

The versioned, request/reply boundary between the local TypeScript editor in a
`WKWebView` and native Swift persistence. Every request carries a correlation
ID, and revision-sensitive draft operations also carry an expected revision;
both sides validate their own representation. Compare
[`protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts) with
[`CaptureBridgeProtocol.swift`](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift).

## C

### Canonical JSON

A stable encoded representation used to compare and persist editor documents
without depending on dictionary ordering. The repository canonicalizes every
draft mutation before revision checks and storage. See
[`CanonicalJSON`](../../Sources/NotionPiP/Domain/CaptureSnapshot.swift).

### Combine observation

Publisher/subscriber propagation used beside SwiftUI observation. For example,
the status item subscribes to the runtime's effective icon visibility, while
the runtime forwards changes from child controllers. See
[`StatusItemController`](../../Sources/NotionPiP/Platform/StatusItemController.swift).

### Composition root

The one place that constructs concrete dependencies and wires callbacks across
layers. `AppComposition` creates the shared persistent container, repositories,
delivery pipeline, WebKit session, panel, runtime, and window presenters. See
[`NotionPiPApp.swift`](../../Sources/NotionPiP/App/NotionPiPApp.swift).

## D

### Delivery journal

Durable progress metadata for a multi-request Notion page creation. After a
page or block batch is accepted remotely, the next batch index is persisted so
recovery does not blindly repeat completed work. See
[`NotionCaptureDeliveryService`](../../Sources/NotionPiP/Services/NotionCaptureDeliveryService.swift).

### Delivery outbox

The local `CaptureRecordModel` rows that separate accepting a Quick Capture
from successfully sending it to Notion. Records move through queued,
in-flight, retry, blocked, uncertain, and delivered states under repository
transition rules. See
[`CaptureRecordModel.swift`](../../Sources/NotionPiP/Persistence/CaptureRecordModel.swift)
and [`DeliveryState.swift`](../../Sources/NotionPiP/Domain/DeliveryState.swift).

### Durable restoration

Cross-launch page state consisting of a trusted last URL plus scroll position
and progress. It is distinct from WebKit's richer in-memory interaction state,
which is available only while the process retains it. See
[`DurablePageRestoration`](../../Sources/NotionPiP/Domain/PageWorkingSetSnapshot.swift).

## E

### Edge stash

The intentional presentation state in which the PiP panel is hidden and a
small draggable handle remains on the nearest screen edge. Geometry selection
is pure policy; AppKit controllers present the panel and handle. See
[`PanelStashPolicy.swift`](../../Sources/NotionPiP/Platform/PanelStashPolicy.swift).

## G

### Generated editor asset

The bundled JavaScript loaded by Quick Capture at runtime. Its authored source
lives under `Web/QuickCaptureEditor`; `build:editor` produces the checked-in
resource and ordinary native builds reuse it unless `node_modules` is already
present. See the build entry point in
[`build.ts`](../../Web/QuickCaptureEditor/build.ts) and the conditional rebuild
in [`build_and_run.sh`](../../script/build_and_run.sh).

### Global shortcut

A persisted key-code/modifier value registered through Carbon. The panel
shortcut emits press and release events so a tap can toggle and a hold can
temporarily peek; Quick Capture has a separate shortcut. See
[`GlobalShortcutRegistrar.swift`](../../Sources/NotionPiP/Platform/GlobalShortcutRegistrar.swift).

## K

### Keychain

The macOS credential store used for the optional personal Notion token. The
item is device-only and available when unlocked; token text is not put in URLs,
logs, UserDefaults, or either WebKit view. See
[`KeychainSecretStore`](../../Sources/NotionPiP/Platform/PersonalTokenCredentialVault.swift).

## M

### Main actor (`@MainActor`)

Swift's global actor for UI-bound state and framework objects. Runtime,
window, and WebKit coordination stay on the main actor, while actor-backed
repositories and services are awaited across that boundary. See
[`AppRuntime`](../../Sources/NotionPiP/App/AppRuntime.swift).

### Manual-verification boundary

Behavior whose correctness depends on the real window server, Spaces, focus,
login session, or Launch Services and therefore is not proven by unit tests
alone. The repository keeps an explicit matrix for those checks. See
[`MANUAL_TEST_MATRIX.md`](../MANUAL_TEST_MATRIX.md).

### Model actor (`@ModelActor`)

A SwiftData actor whose executor owns a `ModelContext`. The repositories turn
off implicit autosave, validate transitions, explicitly save, and roll back on
failure. See
[`CaptureRepository`](../../Sources/NotionPiP/Persistence/CaptureRepository.swift).

## N

### Notion API client

The narrow authenticated HTTP layer for validating a token, searching a
workspace, inspecting a data source, creating a page, and appending children.
Delivery obtains the token through the native credential vault, not through the
embedded Notion session. See
[`NotionAPIClient`](../../Sources/NotionPiP/Services/NotionAPIClient.swift).

### Notion page reference

A validated value containing a canonical HTTPS Notion URL and stable page ID.
It prevents arbitrary URLs from entering pinning, restoration, and external-
route flows. See
[`NotionPageReference`](../../Sources/NotionPiP/Domain/NotionPageReference.swift).

### `NSPanel`

An AppKit window class suited to auxiliary floating UI. Notion PiP's subclass
can become key for editing and intentionally follows its all-Spaces picture-in-
picture role; this persistent behavior is not a defect. See
[`KeyCapablePiPPanel`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift)
and the role policy in
[`WindowRolePolicy.swift`](../../Sources/NotionPiP/Platform/WindowRolePolicy.swift).

### `NSViewRepresentable`

The SwiftUI adapter protocol for hosting an AppKit view. The PiP chrome uses it
to place the retained Notion `WKWebView` inside a SwiftUI hierarchy without
giving SwiftUI ownership of the browser session. See
[`NotionWebView`](../../Sources/NotionPiP/Platform/NotionWebView.swift).

## O

### Observable object

A reference type whose published changes invalidate observing SwiftUI views.
`AppRuntime` is the UI-facing facade; focused controllers publish their own
state and the runtime forwards their change notifications. See
[`QuickCaptureDestinationController`](../../Sources/NotionPiP/App/QuickCaptureDestinationController.swift).

### Optimistic concurrency

A write rule in which the caller supplies the revision it last observed. A
mismatch becomes an explicit stale-revision conflict, preventing an older web
snapshot from silently overwriting newer local work. See
[`CaptureRepository.saveDraft`](../../Sources/NotionPiP/Persistence/CaptureRepository.swift).

## P

### ProseMirror JSON

The tree-shaped `doc`/`content` document representation emitted by Tiptap and
persisted locally. Native code validates and canonicalizes it, and the delivery
converter maps supported nodes and marks into Notion blocks. See
[`NotionBlockConverter`](../../Sources/NotionPiP/Services/NotionBlockConverter.swift).

## R

### Repository

An actor-backed persistence boundary that exposes domain snapshots rather than
SwiftData model objects. Page and capture repositories centralize validation,
deduplication, ordering, transitions, save, and rollback behavior. See
[`PageRepository`](../../Sources/NotionPiP/Persistence/PageRepository.swift).

### Retry policy

Pure rules for bounded exponential backoff, `Retry-After`, attention age, and
retention windows. The delivery engine applies these rules while the scheduler
owns when another drain occurs. See
[`RetryPolicy.swift`](../../Sources/NotionPiP/Domain/RetryPolicy.swift).

## S

### `Sendable`

A Swift concurrency contract stating that a value can cross isolation
boundaries safely. Domain snapshots and protocol payloads use value semantics
and `Sendable` so UI, repositories, and service actors can exchange them. See
[`CaptureSnapshot.swift`](../../Sources/NotionPiP/Domain/CaptureSnapshot.swift).

### Structured concurrency

Swift's scoped `async`/`await` and `Task` model for asynchronous work,
cancellation, and sequencing. Runtime persistence chains each write after the
previous task so page visits cannot finish out of activation order. See
[`AppRuntime+Persistence.swift`](../../Sources/NotionPiP/App/AppRuntime+Persistence.swift).

### SwiftData

Apple's model and persistence framework used for pinned/recent pages,
restoration, Quick Capture drafts, outbox records, and the selected destination.
All model versions share one container and an explicit migration plan. See
[`NotionPiPPersistence.swift`](../../Sources/NotionPiP/Persistence/NotionPiPPersistence.swift)
and [`NotionPiPSchema.swift`](../../Sources/NotionPiP/Persistence/NotionPiPSchema.swift).

### SwiftUI

The declarative view layer used for PiP chrome, settings, page switching,
status, and recovery surfaces. It observes controller state but delegates
window and WebKit ownership to AppKit-facing platform types. See
[`PiPChromeView`](../../Sources/NotionPiP/Views/PiPChromeView.swift).

## T

### Tiptap

The TypeScript editor toolkit built on ProseMirror. Quick Capture configures
StarterKit, placeholder, and task-list extensions, then adds repository-owned
slash-menu, formatting, transition, and bridge controllers. See
[`QuickCaptureEditorController`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.ts)
and pinned versions in [`package.json`](../../package.json).

### Transition gate

The editor-side serializer that flushes pending autosave before state changes
such as stash or restore and keeps ambiguous operations retryable with the same
request ID. Native code independently makes those transitions idempotent. See
[`EditorTransitionGate`](../../Web/QuickCaptureEditor/state/editor-transition-gate.ts).

## U

### UserDefaults

The local preference store for non-secret settings such as shortcuts, menu-bar
visibility, trusted capture toggles, and panel-size presets. Credentials use
Keychain and durable content uses SwiftData instead. See
[`PanelSizePreferencesStore`](../../Sources/NotionPiP/Persistence/PanelSizePreferencesStore.swift).

## W

### `WKScriptMessageHandlerWithReply`

The WebKit API that accepts a page-world message and asynchronously returns a
value to JavaScript. The weak adapter checks the trusted local document,
decodes the bounded protocol, and avoids a WebKit-to-session retain cycle. See
[`WeakScriptMessageHandler`](../../Sources/NotionPiP/Platform/WeakScriptMessageHandler.swift).

### `WKWebView`

WebKit's embeddable browser view. Notion PiP has two distinct uses: one retained
live Notion session with a persistent website data store, and one local Quick
Capture editor with a non-persistent store and tightly scoped navigation. See
[`NotionWebSession`](../../Sources/NotionPiP/Platform/NotionWebSession.swift)
and [`CaptureEditorSession`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift).
