# Lecture 9 — Quick Capture Editor and Native Bridge

> **Estimated duration:** 90 minutes (10 minutes foundation, 20 minutes
> repository tour, 15 minutes runtime trace, 20 minutes deep dive, 10 minutes
> knowledge check, and 15 minutes exercise)

Quick Capture is a hybrid editor: a Swift-owned window embeds a local WebKit
document, Tiptap owns the live ProseMirror state, and a deliberately small
versioned bridge moves snapshots to a SwiftData repository. The difficult part
is not sending JSON across WebKit. It is knowing which side owns each state,
when an edit becomes durable, and how a retry avoids applying a state
transition twice.

This lecture documents committed source at baseline
`47afd8574aecb3e8450cca3c72e1e882ab4fbc04`. The working tree contained
uncommitted product and test changes during course production; those changes
are excluded from every claim below. When a linked file differs, inspect the
taught blob with `git show 47afd85:<path>`.

## Learning objectives

By the end of this lecture, you will be able to:

1. identify the native session, WebKit bridge, Tiptap controller, repository,
   and SwiftUI view owners without treating them as one editor object;
2. explain how the packaged HTML, CSS, and generated JavaScript reach a
   nonpersistent local `WKWebView`;
3. read every bridge v1 request and reply shape and state the native and web
   validation boundaries;
4. trace one edit through the 300-millisecond debounce, native repository save,
   authoritative revision acknowledgement, and UI status update;
5. explain why ready, stash, restore, and conflict recovery lock mutation and
   why ambiguous transitions retry the exact request;
6. distinguish a ProseMirror document, a bridge snapshot, and a durable draft
   snapshot; and
7. choose the right tests for protocol validation, pure TypeScript behavior,
   real WebKit integration, persistence, conflict recovery, and manual UI
   behavior.

The lecture has three layers. **Foundation** introduces the hybrid ownership
model. **Repository tour** maps the concrete files and protocol. **Deep dive**
focuses on acknowledgement, idempotency, conflict recovery, and security.

## Before you begin

Recommended context:

- [Lecture 4](04-composition-and-runtime.md) for the composition root and
  main-actor window ownership;
- [Lecture 8](08-persistence-and-restoration.md) for `CaptureRepository`, draft
  revisions, save-or-rollback, and active/stashed dispositions;
- [`Package.swift`](../../Package.swift) for the copied Quick Capture resource
  directory; and
- [`package.json`](../../package.json) for the pinned Tiptap packages and web
  editor scripts.

Keep these terms separate:

| Term | Meaning |
|---|---|
| ProseMirror document | JSON tree rooted at `{type: "doc", content: [...]}` that represents editor content |
| Editor snapshot | Bridge value containing draft ID, title, document, and—only in native replies/current web state—an authoritative revision |
| Draft mutation | Native request to save title/document/disposition against an expected repository revision |
| Draft snapshot | Durable repository value returned after save, with revision, timestamps, disposition, and links |
| Acknowledgement | Typed bridge reply proving what native code accepted or rejected; it is not merely completion of `postMessage` |
| State transition | Ready, stash, restore, or conflict recovery operation that can replace the installed editor snapshot |

**Verification boundary:** TypeScript tests exercise pure protocol, debounce,
formatting, slash-menu, and transition logic under Node and `happy-dom`. Swift
tests exercise native decoding, model-actor persistence, and real `WKWebView`
behavior. They do not prove IME behavior for every language, every VoiceOver
path, visual placement at every window size, survival of power loss during a
store write, or compatibility with an independently deployed web client. Those
remain manual, accessibility, and system-integration boundaries.

## Foundation

### One editor, five ownership domains

```text
AppWindowFactory / QuickCaptureView       @MainActor window and conflict UI
                 │ owns/observes
                 ▼
CaptureEditorSession                      @MainActor WKWebView + native orchestration
                 │ captureBridge v1
                 ▼
QuickCaptureEditorController              browser event and editor coordination
          │                     │
          ▼                     ▼
Tiptap / ProseMirror              debounce + transition gate
                 │ versioned snapshot
                 ▼
CaptureRepository                        @ModelActor durable draft rows
```

`QuickCaptureView` does not own document structure. It embeds the session's
`WKWebView` and, when `session.conflict` exists, adds native recovery controls.
`CaptureEditorSession` does not synthesize rich-text DOM. It validates bridge
requests, calls `CaptureRepository`, publishes native status/conflict state,
and returns typed replies. `QuickCaptureEditorController` owns the Tiptap
instance, DOM events, local snapshot revision, status text, and web-side
serialization gates.

The live Tiptap document is fast, mutable UI state. The SwiftData draft is the
durable authority. The bridge revision connects them: a request proposes
content against `expectedRevision`; a successful reply advances the web
client to the revision the repository actually committed.

### Bundled web code is application code

Quick Capture does not navigate to a hosted editor. SwiftPM copies
[`Resources/QuickCapture`](../../Sources/NotionPiP/Resources/QuickCapture) as a
resource directory. `CaptureEditorResources.editorURL` first looks for the
packaged app's nested `NotionPiP_NotionPiP.bundle/QuickCapture/index.html`, then
the SwiftPM bundle's `QuickCapture/index.html`, and finally returns a deliberate
missing-file sentinel. A missing editor changes session status to a safe
failure instead of loading arbitrary fallback content.

The HTML loads one stylesheet and one script from the same local directory.
Its Content Security Policy denies everything by default, permits only
same-origin local scripts/styles and data images, and denies connections, fonts, media, objects,
frames, base URLs, and form actions. This defense complements native origin
validation; neither one makes arbitrary JavaScript safe.

### Values cross; mutable owners stay put

The bridge types are `Sendable` Swift values, plain TypeScript objects, and
canonical JSON bytes. `WKWebView`, Tiptap `Editor`, SwiftData models, and DOM
elements stay with their owners. This is the same snapshot boundary used in
the persistence layer: no `CaptureDraftModel` enters WebKit, and no DOM node
enters the model actor.

## Repository tour

### Native source map

| File | Responsibility | Focused evidence |
|---|---|---|
| [`AppWindowFactory.swift`](../../Sources/NotionPiP/Platform/AppWindowFactory.swift) | Creates the key-capable Quick Capture window, session, SwiftUI view, close lifecycle, termination flush, and disposal hook | [`CaptureEditorFlowTests.swift`](../../Tests/NotionPiPTests/CaptureEditorFlowTests.swift), window-presenter tests |
| [`QuickCaptureView.swift`](../../Sources/NotionPiP/Views/QuickCaptureView.swift) | Embeds the session web view and presents native conflict recovery | [`CaptureWebViewConflictTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewConflictTests.swift) |
| [`CaptureEditorSession.swift`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift) | Owns local WebKit, repository orchestration, status, transition receipts, conflicts, navigation, reload, termination persistence, and teardown | editor-flow and all `CaptureWebView…Tests.swift` integration suites |
| [`CaptureBridgeProtocol.swift`](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift) | Defines bridge v1 request/result/error values plus strict native decode and encode | [`CaptureBridgeProtocolTests.swift`](../../Tests/NotionPiPTests/CaptureBridgeProtocolTests.swift) |
| [`WeakScriptMessageHandler.swift`](../../Sources/NotionPiP/Platform/WeakScriptMessageHandler.swift) | Adapts `WKScriptMessageHandlerWithReply`, derives frame/origin context, and weakly forwards decoded requests | flow/lifecycle teardown tests |
| [`QuickCaptureLifecycleCoordinator.swift`](../../Sources/NotionPiP/Services/QuickCaptureLifecycleCoordinator.swift) | On close, saves the latest snapshot, discards empty work or enqueues nonempty work after destination/token checks | [`QuickCaptureLifecycleTests.swift`](../../Tests/NotionPiPTests/QuickCaptureLifecycleTests.swift) |
| [`index.html`](../../Sources/NotionPiP/Resources/QuickCapture/index.html) | Accessible title, status/retry/new-note controls, editor mount, slash listbox, formatting toolbar, CSP | focus, lifecycle, slash-menu, toolbar, and danger-contrast tests |
| [`composer.css`](../../Sources/NotionPiP/Resources/QuickCapture/composer.css) | Editor/overlay layout, focus styles, task blocks, adaptive danger color, reduced-motion behavior | [`QuickCaptureDangerContrastTests.swift`](../../Tests/NotionPiPTests/QuickCaptureDangerContrastTests.swift) and WebKit UI tests |
| [`editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js) | Checked-in generated browser bundle loaded by the app | real WebKit integration tests |

`AppWindowFactory` keeps the session alive through the view/presenter, asks the
session for a live snapshot before close, and delegates final discard/enqueue
to the lifecycle actor. A visible capture window also participates in app
termination: quit proceeds only if `prepareForTermination()` can persist the
latest live snapshot. Releasing the presenter calls `session.dispose()`.

### Web source map

Every committed source under `Web/QuickCaptureEditor` belongs to one of these
roles:

| Source | Responsibility |
|---|---|
| [`editor.ts`](../../Web/QuickCaptureEditor/editor.ts) | DOM bootstrap and public exports |
| [`quick-capture-editor-controller.ts`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.ts) | Tiptap configuration, DOM controls, snapshot installation, status, and native surface |
| [`protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts) | Bridge v1 TypeScript shapes, allowlisted request construction, and exact reply guards |
| [`bridge-client.ts`](../../Web/QuickCaptureEditor/bridge/bridge-client.ts) | Dispatch, five-second acknowledgement timeout, reply validation, and correlation check |
| [`debounced-change-publisher.ts`](../../Web/QuickCaptureEditor/bridge/debounced-change-publisher.ts) | Latest-change debounce, serialized delivery, exact failed-request retry, and change drain |
| [`editor-transition-gate.ts`](../../Web/QuickCaptureEditor/state/editor-transition-gate.ts) | Mutation lock, transition serialization, exact request capture/retry, and terminal receipts |
| [`editor-state.ts`](../../Web/QuickCaptureEditor/editor-state.ts) | Empty-document normalization, recursive key ordering, focus routing, and monotonic snapshot rule |
| [`formatting.ts`](../../Web/QuickCaptureEditor/formatting.ts) | Six mark commands/state and safe HTTP(S)-only selected-text link paste |
| [`block-commands.ts`](../../Web/QuickCaptureEditor/block-commands.ts) | Ten slash commands, filtering, slash-query detection, command dispatch, IME-safe key routing |
| [`formatting-toolbar-controller.ts`](../../Web/QuickCaptureEditor/controllers/formatting-toolbar-controller.ts) | Contextual toolbar position, active state, focus traversal, link prompt, and mutation lock |
| [`slash-menu-controller.ts`](../../Web/QuickCaptureEditor/controllers/slash-menu-controller.ts) | Listbox rendering, caret position, active descendant, wrapped keyboard selection, and cleanup |
| [`build.ts`](../../Web/QuickCaptureEditor/build.ts) | esbuild recipe for the checked-in `editor.js` bundle |
| [`test-support/dom.ts`](../../Web/QuickCaptureEditor/test-support/dom.ts) | Installs a `happy-dom` global environment for controller tests |

The matching `.test.ts` files cover protocol guards, autosave queues, all block
commands, formatting, both overlay controllers, controller bootstrap, and
transition behavior. Swift real-WebKit suites then verify the generated bundle,
DOM behavior, repository integration, and lifecycle on macOS.

| Web test | Protects |
|---|---|
| [`protocol.test.ts`](../../Web/QuickCaptureEditor/protocol.test.ts) | Allowlisted request construction and exact kind/error/snapshot reply guards |
| [`autosave.test.ts`](../../Web/QuickCaptureEditor/autosave.test.ts) | Debounce, deferred snapshots, acknowledgement ordering, timeouts, and exact retries |
| [`transition.test.ts`](../../Web/QuickCaptureEditor/transition.test.ts) | Initial lock, drain/discard rules, ambiguous retry, terminal receipts, and monotonic installation |
| [`quick-capture-editor-controller.test.ts`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.test.ts) | Bootstrap, ready request, authoritative snapshot installation, status, and exported bridge surface |
| [`block-commands.test.ts`](../../Web/QuickCaptureEditor/block-commands.test.ts) | Stable command catalog, filtering, slash ranges, Tiptap dispatch, focus routing, and IME-safe keys |
| [`formatting.test.ts`](../../Web/QuickCaptureEditor/formatting.test.ts) | Document normalization, mark state/dispatch, and HTTP(S)-only link paste |
| [`formatting-toolbar-controller.test.ts`](../../Web/QuickCaptureEditor/controllers/formatting-toolbar-controller.test.ts) | Toolbar position, active state, locking, keyboard traversal, commands, and dismissal |
| [`slash-menu-controller.test.ts`](../../Web/QuickCaptureEditor/controllers/slash-menu-controller.test.ts) | Filtered options, positioning, active descendant, keyboard selection, and cleanup |

### Tiptap and ProseMirror configuration

The controller constructs one Tiptap `Editor` with:

- `StarterKit`, with link opening and automatic link-on-paste disabled;
- `Placeholder` with “Type '/' for commands”;
- `TaskList` and nested `TaskItem`;
- a noneditable initial state until native ready succeeds;
- ARIA textbox, label, multiline, listbox-control, expansion, and popup
  attributes; and
- update, transaction, focus, blur, keydown, and paste callbacks owned by the
  controller.

Supported contextual marks are bold, italic, underline, strike, inline code,
and link. A pasted link becomes a mark only when text is selected and the
trimmed clipboard value is one whitespace-free HTTP or HTTPS URL. The slash
catalog is Text, Heading 1/2/3, Bulleted list, Numbered list, To-do list, Quote,
Code block, and Divider. A slash query must begin at the start of the current
text block; executing a command deletes the `/query` range first.

StarterKit input rules also permit familiar Markdown-like heading, quote, and
list markers. These are editor behaviors, not a Markdown storage format: the
bridge persists normalized ProseMirror JSON.

### Bridge v1 request and reply grammar

Every request has `version: 1`, a nonempty correlation `id`, and one exact
allowlisted shape:

| Type | Payload | Native result kind |
|---|---|---|
| `ready` | no payload | `ready` plus authoritative snapshot/revision |
| `changed` | snapshot without revision + nonnegative `expectedRevision` | `changed` plus committed revision |
| `save` | snapshot without revision + nonnegative `expectedRevision` | `saved` plus committed revision |
| `stash` | snapshot without revision + nonnegative `expectedRevision` | `stashed` plus successor snapshot/revision |
| `restore` | draft ID + nonnegative `expectedRevision` | `restored` plus target snapshot/revision |
| `resolveConflict` | `reloadLatest`, `saveAsNew`, or `openInNotion` + snapshot | `conflictResolved`, optionally with snapshot/revision |

A reply has the same version and correlation ID plus exactly one of:

```text
{ version, id, ok: true,  result: { kind, revision?, snapshot? } }
{ version, id, ok: false, error:  { code, message, recoverable, latest? } }
```

The five error codes are `invalidMessage`, `staleRevision`, `draftNotFound`,
`persistenceFailure`, and `unsupportedAction`. Only stale-revision errors may
carry `latest` in the web reply guard. Ready/stashed/restored require a snapshot
whose revision equals the result revision; changed/saved carry a revision but
no snapshot; conflict resolution may carry neither or both.

Native decoding caps each message at 1,048,576 bytes, requires the main frame,
requires an empty-host `file:` origin, and requires the symlink-resolved source
URL to equal the allowed bundled `index.html`. Request IDs are at most 128 UTF-8
bytes, draft IDs at most 256, titles at most 32,768, revisions are nonnegative
integers, and the document must be a JSON object with `type: "doc"` and an array
`content`. Request envelopes and snapshot fields reject unknown or missing
fields. Native reply encoding is also capped at 1 MiB.

The TypeScript side independently constructs allowlisted requests and rejects
unknown reply keys, kinds, errors, invalid revisions, invalid identifiers, and
malformed snapshots. This is defense in depth across a privilege boundary, not
evidence that the two validators are byte-for-byte identical.

### Weak handler, bootstrap, and teardown

`WKUserContentController` retains its script-message handler. The handler's
delegate is therefore `weak`; otherwise the session → web view/configuration →
handler → session path would leak. After native construction sets the weak
delegate and navigation delegate, `loadFileURL` allows reads only from the
resource directory.

`editor.ts` waits for `DOMContentLoaded` when needed. It starts only if the
`captureBridge` handler and all required editor/title/status/overlay elements
exist. The controller installs `window.NotionPiPBridge` and sends `ready`.
Controls stay locked until a valid ready snapshot is applied. Teardown removes
the named handler from the page content world, nils delegates, cancels tasks,
stops loading, and removes the web view from its superview.

## Runtime trace

### Edit → debounce → native save → acknowledgement

```mermaid
sequenceDiagram
    participant U as User / Tiptap
    participant C as QuickCaptureEditorController
    participant D as DebouncedChangePublisher
    participant B as BridgeClient + captureBridge
    participant S as CaptureEditorSession
    participant R as CaptureRepository

    U->>C: title input or Tiptap onUpdate
    C->>C: show Saving…
    C->>D: changed(snapshot closure, revision closure)
    Note over D: reset 300 ms timer; keep latest pending change
    D->>D: serialize snapshot only when delivery reaches flush
    D->>B: changed(id, snapshot, expectedRevision N)
    B->>S: WKScriptMessageWithReply
    S->>S: main-frame/origin/path/shape validation
    S->>R: saveDraft(mutation, expectedRevision: N)
    R-->>S: durable snapshot, revision N+1
    S-->>B: changed reply, revision N+1
    B->>B: validate shape + correlation ID
    B-->>C: typed acknowledgement
    C->>C: revision = max(current, N+1); show Saved
```

Step by step:

1. Ready installs an authoritative native snapshot and unlocks title, Tiptap,
   New note, and formatting controls.
2. Title `input` or Tiptap `onUpdate` calls `scheduleChange`, unless native code
   is currently installing a snapshot, a transition is locked, or no draft ID
   exists.
3. The publisher waits 300 milliseconds. Repeated edits replace the pending
   snapshot closure; serialization is deferred until flush, so it captures the
   latest title/document rather than one JSON copy per keystroke.
4. Deliveries are chained. A second flush waits for the first acknowledgement,
   then reads the now-authoritative revision before creating its request.
5. Native validation converts the document to sorted-key canonical JSON. The
   session calls `CaptureRepository.saveDraft` with `expectedRevision`.
6. The repository either commits and increments the revision or returns a
   typed failure. Native code never acknowledges a successful change before
   the repository save returns.
7. `BridgeClient` allows at most five seconds, validates the complete reply,
   and requires its correlation ID to equal the request ID.
8. The controller applies the committed revision and reports Saved. A negative
   acknowledgement reports the native message and enters the appropriate retry
   or conflict path.

### New note and restore are ordered transitions

New note means “stash this active draft, then install the active successor.”
The transition gate locks mutation first, flushes and acknowledges pending
changes, captures a stash request using the updated revision, and only then
dispatches it. Native code may persist supplied content, stash the row, and
create or recover the next active draft. One successful reply installs that
successor and focuses its title.

Restore uses the same drain-before-switch rule: queued edits for the old draft
must be durable before a different draft becomes active. Conflict recovery is
different. Its pending autosave represents work superseded by the explicitly
captured conflict snapshot, so the conflict operation discards pending changes
instead of draining them.

## Deep dive

### Acknowledgement is the revision protocol

Debounce alone does not prevent stale writes. The revision protocol does:

```text
web snapshot revision N
        │ changed(expectedRevision: N)
        ▼
repository compares current revision
        ├─ equal → commit N+1 → acknowledge N+1
        └─ different → staleRevision + latest snapshot
```

The web publisher retains the exact emitted request after timeouts,
transport-like errors, or recoverable persistence failures. Retry sends that
same ID, snapshot, and expected revision before newer pending work. This lets
native/repository idempotency reconcile an acknowledgement that was lost after
a commit. A stale-revision negative acknowledgement is definitive for that
autosave; retaining and replaying it cannot make it valid, so it aborts a
not-yet-captured state transition and moves to conflict recovery.

Explicit `save` is part of bridge v1 and native handling, although the current
HTML has no Save button: ordinary editing uses `changed`, and window close or
app termination obtains a live snapshot directly from
`window.NotionPiPBridge.snapshot()`.

### Transition gate on both sides

The web `EditorTransitionGate` starts locked. For each transition it:

1. rejects a different operation while one is pending;
2. locks mutation controls;
3. drains or discards pending changes as specified;
4. creates the request exactly once;
5. validates correlation and expected result kind;
6. applies the reply before unlocking; and
7. retains exact pending requests after ambiguous failures.

Conflict operations retain up to 64 terminal receipts so a native retry after
an already-applied success does not redispatch or reapply it.

Native code independently tracks in-flight state transitions and retains
bounded sets of up to 64 committed receipts and 64 ambiguous operations keyed
by request ID. Reusing an ID with a different stash,
restore, or conflict operation is `invalidMessage`. Concurrent identical
requests share one task; committed requests replay one reply. If a post-commit
hook fails, an exact retry inspects repository state and reconciles stash or
restore without blindly repeating the whole transition.

Stash is especially important because it spans observable milestones:

```text
persist latest active content → mark old draft stashed → obtain/create successor
```

Recovery handles failure after persistence, after stashing, or after successor
creation. “Retry” therefore means reconcile the recorded operation, not “run
three mutations again and hope.”

### Revision conflicts and recovery actions

When the repository reports stale revision and native code can load the stored
draft, the session retains both `currentWork` and `latest` in `CaptureConflict`.
SwiftUI offers all three actions:

| Action | Native effect | Editor effect |
|---|---|---|
| `reloadLatest` | Fetch current durable draft | Install latest snapshot, intentionally replacing conflicting current work |
| `saveAsNew` | Save captured current work under a new draft ID at revision 1 | Install the new durable copy |
| `openInNotion` | Invoke the supplied external action | No replacement snapshot; conflict remains available |

Native UI asks the web surface to resolve using a stable operation ID and the
latest live editor snapshot. Resolution is single-flight. If applying or
acknowledging it fails, retry uses the same operation ID; a committed save-as-new
receipt cannot create another copy.

`canInstallSnapshot` supplies a final web guard: for the same draft, a lower
revision cannot replace newer live DOM; the same or higher revision can. A
different draft ID may install even when its revision is numerically lower,
because revisions are per draft, not global.

### Renderer termination, close, and app termination

If WebKit's content process terminates, the session marks loading and reloads
the local editor once. Ready restores the repository's persisted active draft.
An edit still inside the debounce window is not promised to survive an abrupt
renderer death; the durable boundary remains the acknowledged save.

Normal window close first calls the live `snapshot()` surface, then the
lifecycle coordinator canonicalizes/saves it. Empty title plus empty document
deletes the draft. Nonempty work is retained and, when destination and token
configuration are available, enqueued for delivery. Delivery itself belongs to
Lecture 10.

App termination also snapshots and persists. If an optimistic revision became
stale, termination reloads the latest row and retries once against its current
revision, unless content is already equal. Failure prevents termination and
publishes safe guidance rather than pretending the latest edit is durable.

### Source files versus generated `editor.js`

The maintainable source of truth is `Web/QuickCaptureEditor/*.ts` plus pinned
dependencies in `package.json`. [`build.ts`](../../Web/QuickCaptureEditor/build.ts)
uses esbuild to bundle `editor.ts` as a minified browser IIFE targeting Safari
17, with no sourcemap or legal comments. The output is the checked-in, usually
single-line [`editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js)
that SwiftPM copies into the app.

This creates two valid workflows:

- A fresh clone can build and run the macOS app from committed assets without
  Node.
- When editing `Web/QuickCaptureEditor`, install pinned dependencies, run
  `npm test`, `npm run typecheck`, then `npm run build:editor`, and review both
  source and generated output.

The macOS build script rebuilds the asset only when `node_modules` already
exists. Therefore an unexpected npm failure during app build can be caused by
that optional local directory, not by a runtime Node dependency.

### Security and manual boundaries

| Boundary | Enforced here | Still manual or external |
|---|---|---|
| Loaded content | bundled file URL, restricted read root, CSP, nonpersistent website store | package integrity/signing and OS WebKit behavior |
| Bridge caller | main frame, exact file origin and symlink-resolved document URL | hostile code already substituted into the signed bundle is outside this check |
| Protocol | v1, exact envelopes, typed actions/results/errors, size/ID/title/revision/document checks | semantic validation of every possible ProseMirror node and mark |
| Navigation | local files under resource root allowed; all HTTP(S) links opened outside the capture web view; unsupported schemes cancelled | destination safety after the user's external browser opens it |
| Credentials | protocol has no token/method/eval field; unknown fields rejected | document text is user content and can itself contain sensitive information |
| Editor UX | unit and real-WebKit tests for keyboard, overlays, focus, contrast, retry, and recovery | VoiceOver quality, IME matrix, visual clipping, reduced-motion feel, real keyboard layouts |

The `captureBridge` is intentionally not installed in the separate Notion web
view. The Quick Capture web view uses `.nonPersistent()` website data, while
the Notion session uses its normal persistent data store. This keeps local
editor code and Notion authentication state from sharing a bridge or cookie
store.

## Common misconceptions and failure modes

| Misconception | Correction | Failure prevented |
|---|---|---|
| “The DOM is the durable draft.” | Only an acknowledged repository save is durable. | Losing debounce-window edits after renderer failure |
| “Debouncing means requests cannot overlap.” | Delivery tails serialize acknowledgements; the timer only coalesces pending changes. | Reusing an old expected revision |
| “A resolved Promise means native saved.” | The reply must be valid, correlated, `ok`, and kind-correct. | Accepting malformed or mismatched acknowledgements |
| “Retry should create a fresh request.” | Ambiguous autosaves/transitions retain the exact request and ID. | Duplicate state transitions or copies |
| “Stash is one assignment.” | It may persist content, change disposition, and create/recover a successor. | Half-applied New note transitions |
| “Revision 5 is newer than revision 2 for every draft.” | Revisions are compared only within the same draft ID. | Rejecting a valid draft switch |
| “CSP alone authenticates a bridge message.” | Native validates main frame, origin, and exact source document independently. | Trusting another local file frame |
| “Weak handler means nobody owns it.” | The session and WebKit configuration retain the handler; only its delegate is weak. | Either a leak or premature handler loss |
| “`editor.js` is the source to hand-edit.” | TypeScript is source; `editor.js` is reviewed generated output. | Losing changes on rebuild and producing an untestable bundle |
| “All links may navigate inside capture.” | HTTP(S) destinations open externally; unsupported schemes are cancelled. | Replacing the trusted local editor document |

## Presenter notes

### Suggested pacing

- **0–10 minutes:** draw the five ownership domains and define snapshot versus
  durable draft.
- **10–25 minutes:** open `index.html`, `editor.ts`, and the controller; show
  local bootstrap, Tiptap configuration, and locked ready state.
- **25–40 minutes:** compare TypeScript `protocol.ts` with native
  `CaptureBridgeProtocol.swift`; ask the room to find validation duplicated on
  purpose.
- **40–52 minutes:** walk one edit through the sequence diagram and pause at
  the exact moment durability becomes true.
- **52–67 minutes:** trace lost stash acknowledgement and stale revision through
  the two transition gates.
- **67–75 minutes:** run the knowledge check.
- **75–90 minutes:** complete and debrief the reconciliation exercise, then
  compare Node, native protocol, and real-WebKit evidence.

### Live teaching cues

1. Disable the native reply in a test double and ask why “Saving…” must not
   become “Saved.”
2. Put two quick edits on the board. Delay acknowledgement 1, then ask which
   revision edit 2 must read.
3. Compare a transition request before and after retry; every field should be
   identical.
4. Show `WeakScriptMessageHandler.delegate` beside WebKit's retained handler
   registration and sketch the avoided cycle.
5. Open the one-line generated `editor.js`, then immediately return to
   `quick-capture-editor-controller.ts` to reinforce source ownership.

Avoid claiming that a local-file origin, CSP, or a file URL makes content trusted by
itself. Trust comes from the combined packaging, load-root, navigation,
main-frame, origin, exact-document, and protocol checks.

## Knowledge check

1. Which object owns the Tiptap editor, and which object owns the SwiftData
   repository call?
2. When does a title keystroke become durable?
3. Why is the expected revision supplied through a closure to a queued change?
4. What three checks does `BridgeClient` add after WebKit resolves the message?
5. Why does New note flush pending changes before creating its stash request?
6. Why does conflict resolution discard a queued autosave instead?
7. What is the difference between a stale-revision rejection and an ambiguous
   persistence/acknowledgement failure?
8. How does the native handler reject another local HTML file?
9. Why can draft revision 1 replace revision 8 in the editor?
10. Which file is generated, and what must be run when its TypeScript source
    changes?

### Answers

1. `QuickCaptureEditorController` owns Tiptap; the main-actor
   `CaptureEditorSession` validates the request and calls `CaptureRepository`.
2. After native `saveDraft` succeeds and a valid correlated success reply is
   received. The DOM change and debounce timer are not durable milestones.
3. Earlier delivery may advance the authoritative revision while this change
   waits in the serialized tail; reading at request creation avoids a stale
   captured number.
4. It enforces a five-second timeout, validates the exact typed reply shape,
   and requires reply ID to match request ID.
5. The old visible draft must be saved and acknowledged first; only then can
   stash capture the updated expected revision and switch active drafts.
6. Conflict recovery explicitly captures the live conflicting work. Sending an
   older queued autosave first would compete with or duplicate that decision.
7. Stale revision definitively says the proposed precondition is false and
   opens recovery. An ambiguous failure may have happened after commit, so the
   exact request must be retried/reconciled.
8. It resolves symlinks and compares the message frame's source URL with the
   one allowed bundled `index.html`, in addition to checking `file:` and main
   frame.
9. A different draft ID is a draft switch; revisions are monotonic only within
   one draft.
10. `Sources/NotionPiP/Resources/QuickCapture/editor.js` is generated. Run web
    tests, typecheck, and `npm run build:editor`, then review the regenerated
    asset.

## Hands-on exercise

### Diagnose a lost New note acknowledgement

Assume draft `A` is active at revision 4. The user types “final line,” clicks
New note immediately, and the network-like bridge acknowledgement is lost
after native code has persisted and stashed `A` and created active draft `B`.
The user clicks Retry.

Produce four things:

1. the ordered request/revision trace;
2. the state that must remain locked after the lost acknowledgement;
3. the native reconciliation decision; and
4. one pure web test, one native repository/session test, and one manual check.

### Worked answer

1. The pending edit flushes first as `changed(expectedRevision: 4)`. Its success
   acknowledges revision 5. Only then does the gate create one `stash` request
   containing the final snapshot and `expectedRevision: 5`. Native persistence
   may leave `A` stashed at a revision greater than 5 and `B` active. Retry
   sends the exact same stash request ID and payload.
2. Title, Tiptap, New note, and formatting remain mutation-locked. The gate
   retains the pending transition and exposes Retry; it must not accept a new
   restore or conflict transition while the stash outcome is ambiguous.
3. Native code finds that stored `A` matches the captured title/document. If it
   is already stashed, it does not stash again; it obtains the current active
   successor and returns the original logical `stashed` success. If the old
   draft was only persisted and still active, it completes the remaining stash
   step first. The committed receipt prevents another successor on later exact
   replay.
4. Web: assert `transition.test.ts` locks before draining and retries the exact
   captured request. Native: assert `CaptureEditorFlowTests` post-commit stash
   reconciliation returns the same successor without another state change.
   Manual: type during the debounce window, click New note, inject/demonstrate
   a delayed acknowledgement in a debug build, verify controls remain locked,
   then Retry and confirm one stashed note plus one empty active successor.

### Review rubric

A complete answer names both acknowledgement gates, uses revision 5 for stash,
preserves the exact operation ID, avoids creating draft `C`, and distinguishes
what automated tests prove from the manual UI observation.

## Recap

- Quick Capture is a native-owned local WebKit surface with Tiptap-owned live
  ProseMirror state and model-actor-owned durable drafts.
- Packaged HTML/CSS/generated JavaScript load from a restricted local resource
  root into a nonpersistent web view; missing resources fail closed.
- Bridge v1 has six exact request shapes, typed result/error shapes, correlation
  IDs, byte limits, revision preconditions, and validation on both sides.
- The 300-millisecond debounce captures only the latest pending edit, while
  serialized acknowledgement—not the timer—orders revisions.
- Ready, stash, restore, and conflict recovery pass through a mutation lock;
  ambiguous operations retry and reconcile the exact captured request.
- Stale revisions preserve current and latest snapshots for reload, save-as-new,
  or open-in-Notion recovery.
- Formatting and slash commands mutate Tiptap and persist as ProseMirror JSON,
  not Markdown.
- TypeScript is the editable source; checked-in `editor.js` is the generated
  Safari 17 bundle that makes a fresh native build independent of Node.
- Pure TypeScript, native unit, real WebKit, persistence, and manual checks each
  protect a different part of the editor boundary.
