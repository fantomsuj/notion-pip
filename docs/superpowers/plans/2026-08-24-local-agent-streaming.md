# Local Agent Streaming Implementation Plan

**Goal:** Let any local coding agent that can make HTTP requests stream plain-text
output into Perch, show that output live over the existing Notion panel, and insert
the completed response once at the user's saved Notion cursor.

**Architecture:** Perch owns an opt-in, loopback-only HTTP server. A versioned
discovery file tells same-user agent processes which random port and bearer token
to use. Requests drive a single `@MainActor` stream controller; the controller
publishes bounded state to a native SwiftUI overlay and uses the existing
`NotionWebSession.rememberCurrentEditorCursor` /
`insertAtSavedEditorCursor` bridge for completion-only write-back. The Notion REST
API, an LLM-specific SDK, and token-by-token DOM mutation are not part of this
feature.

**Tech Stack:** Swift 6.2, macOS 14, SwiftUI, WebKit, Network.framework,
structured concurrency, XCTest, URLSession, OSLog

## Product Decisions

- This is a local agent ingress API, not an embedded LLM client. Claude Code,
  Codex, Cursor, OpenCode, a shell script, or another tool can all use the same
  protocol.
- "Any agent" means any **local** process that is configured to call the API or
  whose stdout is forwarded by an adapter. Perch cannot silently intercept prose
  rendered inside another vendor's UI. Conductor cloud agents also cannot reach
  Mac loopback directly; remote bridging is a separate, security-sensitive
  follow-up.
- Live deltas render in a native overlay above `PiPChromeView`. They are not
  repeatedly inserted into Notion's DOM.
- `complete` inserts the assembled text once through the live Notion session at
  the cursor captured when the stream began. This keeps the existing no-personal-
  integration-token policy.
- Version 1 permits one active stream. A second agent receives a deterministic
  `409 stream_active` response instead of interleaving output or stealing the
  target cursor.
- Starting a stream never navigates Notion, changes the active page, activates
  Perch, or changes Spaces. If Perch is stashed, the stream remains available and
  appears when the user reveals it.
- The server is disabled by default. Enabling "Allow local agents" is the user's
  trust decision for same-user local processes that can read the discovery file.

## Version 1 Wire Contract

The listener binds to an ephemeral port on loopback only. Every `/v1` request,
including status, requires `Authorization: Bearer <token>`, uses
`Content-Type: application/json`, and returns JSON except successful empty
responses. The server accepts HTTP/1.1 requests with `Content-Length`; it rejects
chunked request bodies, unsupported methods/content types, browser `Origin`
headers, invalid `Host` values, oversized headers/bodies, and keep-alive reuse.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/status` | Report server readiness, target availability, limits, and the active stream ID/state. Do not expose page content or the bearer token. |
| `POST` | `/v1/streams` | Capture the current Notion cursor and create the one active stream. Require `Idempotency-Key`; accept `client`, optional `label`, and `commitMode: "insert_on_complete"`. |
| `POST` | `/v1/streams/{id}/chunks` | Append `{ "sequence": n, "text": "..." }` to the bounded buffer and overlay. |
| `POST` | `/v1/streams/{id}/complete` | Mark input complete, insert the assembled text once, and return the resulting stream state. |
| `POST` | `/v1/streams/{id}/cancel` | Cancel without writing to Notion and dismiss the overlay. |
| `GET` | `/v1/streams/{id}` | Let a client recover after a timeout and observe `receiving`, `inserting`, `inserted`, `failed`, `cancelled`, or `expired`. |

Protocol rules:

- The create response returns a random stream UUID, `nextSequence: 0`, limits,
  and the captured target's opaque page ID only when needed to detect a later
  target change. It never returns a Notion URL, title, page body, cookies, or
  selection contents.
- Chunks are UTF-8 plain text. Version 1 does not interpret Markdown or create
  structured Notion blocks.
- Cap each chunk at 32 KiB, the assembled response at 512 KiB, headers at 16 KiB,
  request bodies at 64 KiB, and request rate at 30 requests/second. Coalesce UI
  publication to at most one main-actor update per display frame without delaying
  acknowledgement of accepted chunks.
- `sequence` starts at zero. The next exact number is accepted; an identical
  retry of the previous sequence is idempotent; a conflicting duplicate or an
  out-of-order value returns `409 sequence_mismatch` with `expectedSequence`.
- An inactive stream expires after ten minutes. Terminal stream metadata is kept
  for another ten minutes for retry/status recovery, but completed response text
  is discarded as soon as the success receipt ends. Nothing is persisted.
- Errors use `{ "error": { "code": "...", "message": "..." } }` with stable
  codes such as `unauthorized`, `stream_active`, `cursor_unavailable`,
  `target_changed`, `sequence_mismatch`, `payload_too_large`, `rate_limited`, and
  `stream_gone`.

The discovery file lives at:

```text
~/Library/Application Support/com.fantomsuj.Perch/agent-server.json
```

It is atomically replaced with owner-only (`0600`) permissions and contains only:

```json
{
  "schemaVersion": 1,
  "baseURL": "http://127.0.0.1:49152/v1",
  "token": "<per-launch random 256-bit token>",
  "pid": 12345,
  "startedAt": "2026-08-24T12:00:00Z"
}
```

The token rotates whenever the listener starts. The file is removed on clean
shutdown only when its PID/token still identify the current server. A stale file
is harmless because its token and port no longer authenticate to a listener.
Neither token nor streamed text may enter logs, analytics, crash messages, or
user-visible error details.

## Stream State and User Experience

1. The user enables local agents in Settings and clicks the intended location in
   the live Notion editor.
2. An agent creates a stream. Perch synchronously asks the existing web session to
   capture the cursor before returning `201`; failure returns
   `409 cursor_unavailable` and creates no stream.
3. Accepted chunks update a material-backed overlay inside `PiPChromeView`. The
   card shows the agent label, a streaming indicator, selectable text, Stop, and
   Copy controls. It scrolls only when the user is already at the bottom.
4. `complete` transitions to `inserting` and invokes
   `insertAtSavedEditorCursor` once with the complete buffer.
5. On success, the overlay shows a short "Added to Notion" receipt and fades out;
   the controller releases the text buffer.
6. If the user navigated, reloaded, replaced the editable DOM element, or changed
   the saved target, insertion fails closed. The overlay retains the response and
   offers Copy, Dismiss, and "Insert at Current Cursor". That retry action first
   captures a fresh cursor from an explicit user click and then inserts once.
7. Stopping from the overlay marks the stream cancelled. Later client chunks get
   `410 stream_gone`, which tells a cooperative adapter to stop forwarding.

Accessibility requirements:

- Expose the agent label, current state, output, Stop, Copy, retry, and dismiss as
  separate VoiceOver elements with stable labels.
- Do not steal keyboard focus when a stream starts. Selectable output receives
  focus only after explicit user interaction.
- Use a non-motion state change under Reduce Motion; otherwise use the project's
  existing short cross-blur/fade vocabulary.
- Keep the card usable at the minimum panel size and with large accessibility
  text. Bound its height and scroll internally rather than covering all controls.

## Implementation Tasks

### Task 1: Define the stream domain and state machine

**Files:**

- Create: `Sources/Perch/Domain/AgentStream.swift`
- Create: `Sources/Perch/Services/AgentStreamController.swift`
- Test: `Tests/PerchTests/AgentStreamControllerTests.swift`

**Interfaces:**

- Produce value types for request metadata, bounded chunks, terminal results,
  stable errors, and `AgentStreamState`.
- Produce an `@MainActor AgentStreamController: ObservableObject` and a narrow
  `AgentStreamTarget` protocol implemented by `NotionWebSession`.
- Keep HTTP types, sockets, and JSON out of the controller.

- [ ] Add state-transition tests for create, ordered append, idempotent retry,
  sequence conflict, size/rate limits, complete, cancel, timeout, and one-active-
  stream arbitration.
- [ ] Add target tests for unavailable capture, target invalidation, exactly-once
  completion insertion, failed insertion retention, explicit retry, and buffer
  disposal after success/dismissal.
- [ ] Implement the minimal actor-safe controller. Use injected clock/scheduler,
  ID/token generation, and target doubles so tests are deterministic and parallel.
- [ ] Verify `AgentStreamControllerTests` independently.

### Task 2: Build the authenticated loopback transport

**Files:**

- Create: `Sources/Perch/Platform/AgentStreamHTTPServer.swift`
- Create: `Sources/Perch/Platform/AgentStreamHTTPCodec.swift`
- Create: `Sources/Perch/Platform/AgentStreamDiscoveryStore.swift`
- Test: `Tests/PerchTests/AgentStreamHTTPCodecTests.swift`
- Test: `Tests/PerchTests/AgentStreamHTTPServerTests.swift`
- Test: `Tests/PerchTests/AgentStreamDiscoveryStoreTests.swift`

**Interfaces:**

- `AgentStreamHTTPServer` owns `NWListener` and per-connection tasks off the main
  actor, then calls the controller through an injected async gateway.
- `AgentStreamHTTPCodec` is a pure, deliberately small HTTP/1.1 decoder/encoder
  for the fixed routes above. Do not expose arbitrary command execution, file
  paths, URLs to fetch, JavaScript evaluation, or WebKit handles.
- `AgentStreamDiscoveryStore` atomically publishes/removes the connection record
  in the same Application Support directory as `instance.lock`.

- [ ] Test exact loopback binding, ephemeral-port publication, token rotation,
  owner-only permissions, atomic replacement, stale-file-safe removal, and clean
  stop.
- [ ] Test authentication with constant-time token comparison, Host/Origin
  rejection, route/method/content-type validation, malformed JSON/UTF-8, header
  and body bounds, deadlines/slow clients, rate limiting, connection closure, and
  error redaction.
- [ ] Exercise the real listener with `URLSession` for the full
  create → chunks → status → complete and create → cancel flows.
- [ ] Confirm the listener needs no signing or entitlement change. Current Perch
  builds are not App Sandbox builds; binding only to loopback must remain an
  explicit invariant rather than broadening network exposure.

### Task 3: Add the native streaming overlay

**Files:**

- Create: `Sources/Perch/Views/AgentStreamOverlayView.swift`
- Modify: `Sources/Perch/Views/PiPChromeView.swift`
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Test: `Tests/PerchTests/AgentStreamOverlayTests.swift`
- Modify: `Tests/PerchTests/PiPChromeViewTests.swift`

**Interfaces:**

- Inject the shared `AgentStreamController` through `PiPPanelCoordinator` into
  `PiPChromeView`; do not route streaming state through `AppRuntime`.
- Add one inline `.overlay` above the existing `NotionWebView`, arranged so the
  top controls remain reachable.

- [ ] Add pure presentation tests for receiving, inserting, success, failure,
  cancellation, long text, empty text, and retry availability.
- [ ] Implement the bounded selectable/scrollable overlay and wire Stop, Copy,
  Insert at Current Cursor, and Dismiss to controller intents.
- [ ] Preserve hover toolbar hit testing, WebView lifetime, typing behavior,
  minimum panel sizing, all-Spaces behavior, and panel stashing.
- [ ] Add accessibility and Reduce Motion assertions where they can be expressed
  as pure presentation policy; cover the final focus/scroll behavior manually.

### Task 4: Wire opt-in lifecycle and shutdown

**Files:**

- Create: `Sources/Perch/Persistence/AgentStreamingPreferenceStore.swift`
- Create: `Sources/Perch/Services/AgentStreamingService.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Sources/Perch/App/AppRuntime.swift`
- Modify: `Sources/Perch/App/AppRuntime+Persistence.swift`
- Modify: `Sources/Perch/Views/SettingsView.swift`
- Modify: `Sources/Perch/Platform/AppWindowFactory.swift`
- Test: `Tests/PerchTests/AgentStreamingServiceTests.swift`
- Modify: `Tests/PerchTests/RuntimeTerminationTests.swift`

**Interfaces:**

- `AgentStreamingService` owns preference, listener state, discovery publication,
  and user-facing failure text. It starts only after opt-in and stops immediately
  when disabled.
- App composition creates exactly one controller/service and shares the controller
  with the panel coordinator.

- [ ] Add Settings state for Disabled, Starting, Ready (including Copy Connection
  Details), and Failed/Retry. Explain that access is local, same-user, and grants
  insertion capability at a cursor the user selects.
- [ ] Test enable/disable/retry, failed bind, stale discovery cleanup, repeated
  start/stop, preference restoration, and no server before opt-in.
- [ ] Stop accepting connections first during termination, cancel connection
  tasks, remove the matching discovery file, cancel any receiving stream without
  insertion, and then allow existing persistence shutdown to finish.
- [ ] Update termination tests to prove shutdown waits for listener cleanup but
  cannot hang indefinitely on a slow client.

### Task 5: Provide agent-neutral integration surfaces

**Files:**

- Create: `docs/AGENT_STREAMING.md`
- Modify: `README.md`
- Create: `script/perch_agent_client.swift`
- Create: `Tests/ScriptTests/perch_agent_client_tests.sh`

**Interfaces:**

- Document discovery, authentication, every route/error, privacy behavior,
  limits, retries, and curl/Swift/JavaScript examples without real tokens.
- Provide a dependency-free reference client that reads the discovery record and
  supports `status`, `start`, `append`, `complete`, `cancel`, and `pipe`. `pipe`
  mirrors stdin to stdout, batches bytes into bounded UTF-8 chunks, forwards them
  with sequence numbers, completes on clean EOF, and cancels on interruption.
- Keep raw HTTP canonical. The reference client is convenience, not a required
  runtime component and not an agent-vendor integration.

- [ ] Add contract examples for Codex, Claude Code, Cursor, OpenCode, and generic
  subprocess/stdout forwarding. Be explicit that each agent must be instructed,
  hooked, or wrapped to emit stream calls.
- [ ] Add fixture-based client tests for discovery parsing, missing/stale server,
  Unicode chunk boundaries, HTTP errors, retry after a lost response, cancellation,
  and token redaction.
- [ ] Add a short reusable instruction snippet agents can consume, centered on
  protocol behavior rather than vendor-specific configuration.
- [ ] Keep a generic stdio MCP adapter as a follow-up after the HTTP contract is
  stable. It should translate tools to these endpoints rather than create a
  second Perch control protocol.

### Task 6: Regression and manual verification

**Files:**

- Modify: `docs/PRIVACY.md`
- Modify: `docs/SUPPORT.md`
- Modify: `docs/MANUAL_TEST_MATRIX.md`

- [ ] Document the opt-in local listener, discovery-file contents/permissions,
  in-memory response retention, shutdown behavior, and how to revoke access.
- [ ] Run focused tests for the controller, HTTP codec/server, discovery store,
  overlay, web-session insertion, settings service, and termination.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- [ ] Run every script under `Tests/ScriptTests`, then `git diff --check`.
- [ ] Before launching, check both `pgrep -x Perch` and `pgrep -x NotionPiP` and
  do not terminate a user-owned instance without confirmation. Then run
  `./script/build_and_run.sh --verify`.
- [ ] Inspect `lsof`/`netstat` evidence that the server listens only on loopback,
  inspect discovery permissions, and verify disabling removes the listener/file.
- [ ] Manually test two competing agents, agent crash/EOF, Perch quit/relaunch,
  stale cursor, page navigation, Notion reload, stashed panel, long/rapid Unicode
  output, VoiceOver, Full Keyboard Access, Reduce Motion, offline Notion, Copy,
  retry, cancel, and no accidental insertion after failure.

## Acceptance Criteria

- With local agents disabled, Perch opens no agent-ingress listener and publishes
  no usable discovery credential.
- After opt-in and a user-selected Notion cursor, a generic local client can
  discover Perch, authenticate, stream ordered chunks visibly, and complete one
  insertion without a Notion API token or page reload.
- Unauthorized, browser-origin, remote-interface, oversized, out-of-order,
  concurrent, stale-target, and post-cancellation requests fail deterministically
  without writing to Notion or leaking data.
- No successful stream inserts more than once, including client retries and
  response-loss recovery.
- Failed insertion never discards the assembled response and requires an explicit
  user-selected fresh cursor before retry.
- All listener/connection tasks and the matching discovery file are cleaned up on
  disable and termination; cleanup cannot block app exit indefinitely.
- Existing Swift tests, script tests, signing, entitlements, macOS 14 deployment,
  panel behavior, and Quick Copy insertion behavior continue to pass.

## Explicit Follow-ups, Not Version 1

- A stdio MCP adapter and packaged agent skills/configuration for individual
  products.
- A user-approved relay for Conductor cloud or other remote agents. Never expose
  the loopback server with `0.0.0.0`, port forwarding, or an unauthenticated tunnel.
- Multiple simultaneous streams, stream queues, or choosing among multiple Perch
  panels/pages.
- Markdown-to-Notion block conversion, partial durable commits, image/file
  transfer, arbitrary DOM/JavaScript execution, or Notion REST API credentials.
- Agent read access to Notion page content. Version 1 is write-only except for
  opaque readiness and stream state.
