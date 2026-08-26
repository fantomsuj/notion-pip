# Local agent streaming

Perch can accept Markdown from local coding agents over a loopback-only HTTP
listener. Agents stream into a native overlay. They never write to Notion by
themselves. When a stream finishes, Perch notifies you and waits for **Accept**.
You click the destination in the live Notion editor, then Accept to paste.

This is a local ingress API, not an embedded LLM client and not a Notion REST
integration. Perch does not ask for, store, or send a personal Notion
integration token.

## Opt-in

1. Open Settings → Local Agents.
2. Enable **Allow local agents**.
3. Optionally choose **Install Agent Skill for Cursor** to write the skill at
   `~/.cursor/skills/stream-to-perch/SKILL.md`.

While disabled, Perch opens no agent listener and publishes no discovery
credential. Disable the setting to revoke access immediately: the listener
stops and the matching discovery file is removed.

## Discovery

When the listener is ready, Perch atomically publishes an owner-only (`0600`)
file:

```text
~/Library/Application Support/com.fantomsuj.Perch/agent-server.json
```

Example (fake values only):

```json
{
  "baseURL" : "http://127.0.0.1:49152/v1",
  "pid" : 12345,
  "schemaVersion" : 1,
  "startedAt" : "2026-08-24T12:00:00Z",
  "token" : "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

| Field | Meaning |
|---|---|
| `schemaVersion` | Discovery schema. Version 1 is current. |
| `baseURL` | Loopback base including `/v1`. |
| `token` | Per-launch bearer secret. Rotate whenever the listener starts. |
| `pid` | Publishing Perch process ID. |
| `startedAt` | ISO-8601 start time. |

A stale file is harmless: its token and port no longer authenticate. Never print
the token to chat, logs, commits, crash reports, or screenshots. Prefer reading
the discovery file over copying the token by hand. Settings → Copy Connection
Details intentionally omits the bearer token.

## Authentication and transport

Every `/v1` request, including status, requires:

```http
Authorization: Bearer <token>
```

Rules:

- Bind address is loopback only (`127.0.0.1` / `::1`). Never expose this
  listener on `0.0.0.0`, through port forwarding, or an unauthenticated tunnel.
- HTTP/1.1 with `Content-Length`. Chunked request bodies are rejected.
- POST bodies use `Content-Type: application/json`.
- Browser `Origin` headers are rejected.
- `Host` must be a loopback host for the published port.
- Connections are not reused (`Connection: close`).
- Token comparison is constant-time. Missing or wrong credentials return `401`.

## Commit mode and content type

Version 1 supports exactly:

| Field | Required value |
|---|---|
| `commitMode` | `accept_to_paste` |
| `contentType` | `text/markdown` |

`complete` marks the stream **ready**. It does **not** insert into Notion.
Paste happens only after the user Accepts with a live editor cursor.

Create does **not** require a Notion cursor. The user places the cursor after
the agent finishes, then Accepts.

## Routes

All paths are relative to `baseURL` (already ends with `/v1`).

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/status` | Readiness, optional target hint, limits, active stream id/phase. No token or page body. |
| `POST` | `/streams` | Create the single active stream. Requires `Idempotency-Key`. |
| `POST` | `/streams/{id}/chunks` | Append `{ "sequence": n, "text": "..." }`. |
| `POST` | `/streams/{id}/complete` | Finish input; transition to `ready` and notify the user. |
| `POST` | `/streams/{id}/cancel` | Cancel without pasting; dismiss the overlay. |
| `GET` | `/streams/{id}` | Recover stream state after a timeout. |

### Stream phases

| Phase | Meaning |
|---|---|
| `receiving` | Agent still sending chunks. Overlay shows live Markdown. |
| `ready` | Agent finished. Notification + Accept affordance. Waiting for the user. |
| `inserting` | User accepted; Perch is capturing the cursor and pasting once. |
| `inserted` | Paste succeeded. Short receipt, then overlay dismisses. |
| `failed` | Paste failed closed. Overlay keeps Markdown for Copy / Accept retry / Dismiss. |
| `cancelled` | Stopped without paste. |
| `expired` | Timed out while inactive or while waiting for Accept. |

One stream occupies the active slot while `receiving`, `ready`, `inserting`, or
`failed`. A second create returns `409 stream_active`.

### Create

```http
POST /v1/streams
Authorization: Bearer <token>
Content-Type: application/json
Idempotency-Key: <unique-key>
```

```json
{
  "client": "cursor",
  "label": "Cursor",
  "commitMode": "accept_to_paste",
  "contentType": "text/markdown"
}
```

Successful response: `201` with stream id, `phase: "receiving"`,
`nextSequence: 0`, limits, and optional opaque page id for diagnostics only.
Identical create retries with the same `Idempotency-Key` return the same stream.

### Chunks

```json
{ "sequence": 0, "text": "## Notes\n\n- first item\n" }
```

- `sequence` starts at `0`. The next exact value is accepted.
- Retrying the exact previous sequence is idempotent.
- Conflicting duplicates or out-of-order values return `409 sequence_mismatch`
  with `expectedSequence`.
- Prefer Markdown (headings, lists, fenced code). Perch renders it live and
  pastes so Notion can convert structure.

### Complete and Accept

1. Agent calls `POST .../complete`.
2. Perch sets `phase` to `ready`, shows the overlay Accept control, and posts a
   notification with Accept / Dismiss actions.
3. The user clicks in Notion where the note should go.
4. The user presses **Accept** (overlay or notification).
5. Perch captures the live cursor and pastes the Markdown once.

If there is no usable cursor, Accept fails closed, keeps the Markdown, and asks
the user to click first. Navigation, reload, or a changed editable target also
fails closed with Copy / Accept-again / Dismiss.

### Cancel

`POST .../cancel` or Stop in the overlay cancels without writing. Later chunks
receive `410 stream_gone`; cooperative adapters should stop forwarding.

## Errors

Errors use:

```json
{
  "error": {
    "code": "stream_active",
    "message": "Another local agent stream is already active.",
    "expectedSequence": null
  }
}
```

| Code | Typical status | When |
|---|---|---|
| `unauthorized` | 401 | Missing/invalid bearer token |
| `invalid_request` | 400 / 403 / 404 / 405 / 415 / 505 | Malformed HTTP/JSON, Origin, Host, method, media type |
| `stream_active` | 409 | Another stream occupies the slot |
| `sequence_mismatch` | 409 | Wrong chunk sequence (`expectedSequence` set) |
| `cursor_unavailable` | 409 | Stable code for “no pasteable cursor”; Accept UX asks the user to click first |
| `target_changed` | 409 | Page/editor target changed before paste finished |
| `payload_too_large` | 413 / 431 | Header, body, chunk, or assembled buffer too large |
| `rate_limited` | 429 | More than 30 requests/second |
| `stream_gone` | 410 | Unknown, cancelled, expired, or no longer receiving |
| `unsupported` | 400 | Reserved for unsupported protocol features |

Error messages must not include tokens, page bodies, cookies, or full URLs.

## Limits

| Limit | Default |
|---|---|
| Chunk UTF-8 bytes | 32 KiB |
| Assembled response | 512 KiB |
| Request headers | 16 KiB |
| Request body | 64 KiB |
| Request rate | 30 / second |
| Inactive receiving expiration | 10 minutes |
| Terminal metadata retention | 10 minutes |
| Ready (awaiting Accept) retention | 30 minutes |

Nothing is persisted to disk for stream payloads. Assembled Markdown stays in
memory until successful paste, dismiss, cancel, expiration, or app quit.

## Accept-to-paste UX

- Live deltas appear in a material overlay above the Notion panel. They are not
  repeatedly inserted into the DOM.
- Starting a stream never navigates Notion, changes Spaces, or forces the panel
  visible. A stashed Perch still receives the stream; the overlay appears when
  the panel is revealed.
- Notifications summarize readiness only. They do not include the Markdown body
  or the bearer token.
- VoiceOver exposes agent label, state, output, Stop, Copy, Accept, and Dismiss
  as separate elements. Streams do not steal keyboard focus on start.

## Privacy notes

- Opt-in only. Same-user local processes that can read the discovery file can
  authenticate.
- Discovery file permissions are `0600`.
- Stream Markdown is memory-only until Accept, dismiss, cancel, expire, or quit.
- Status responses never include the bearer token or Notion page content.
- Tokens and streamed text must not enter logs, analytics, crash messages, or
  support reports.
- Remote or cloud agents cannot reach Mac loopback directly. Bridging them is a
  separate, security-sensitive follow-up and is out of scope for version 1.

See also [PRIVACY.md](PRIVACY.md).

## Agent skill

Repository skill: [`agent-skills/stream-to-perch/SKILL.md`](../agent-skills/stream-to-perch/SKILL.md).

The same Markdown is embedded as `AgentStreamSkillDocument.markdown` in
`Sources/Perch/Services/AgentStreamingService.swift` and is what Settings
installs for Cursor. Keep those copies aligned.

## Reference client

```sh
swift script/perch_agent_client.swift status
swift script/perch_agent_client.swift start --label "Demo"
swift script/perch_agent_client.swift append --stream-id <id> --sequence 0 --text "# Hi\n"
swift script/perch_agent_client.swift complete --stream-id <id>
swift script/perch_agent_client.swift cancel --stream-id <id>
some-agent | swift script/perch_agent_client.swift pipe --label "Agent"
```

`pipe` mirrors stdin to stdout while chunking UTF-8 Markdown to Perch, completes
on clean EOF, and cancels on interruption. Override discovery with
`--discovery <path>` or `PERCH_AGENT_DISCOVERY`.

## Examples

All tokens below are fake. Replace them by reading the discovery file.

### curl

```sh
DISCOVERY="$HOME/Library/Application Support/com.fantomsuj.Perch/agent-server.json"
BASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["baseURL"])' "$DISCOVERY")"
TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$DISCOVERY")"

curl -sS "$BASE/status" \
  -H "Authorization: Bearer $TOKEN"

curl -sS -X POST "$BASE/streams" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: demo-create-1" \
  -d '{"client":"curl","label":"curl","commitMode":"accept_to_paste","contentType":"text/markdown"}'

# STREAM_ID from the create response; never echo $TOKEN to logs.
curl -sS -X POST "$BASE/streams/$STREAM_ID/chunks" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sequence":0,"text":"## Demo\n\nHello from curl.\n"}'

curl -sS -X POST "$BASE/streams/$STREAM_ID/complete" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

After `complete`, click in Notion and press **Accept** in Perch.

### JavaScript (local Node)

```js
import fs from "node:fs";
import { randomUUID } from "node:crypto";

const discoveryPath = `${process.env.HOME}/Library/Application Support/com.fantomsuj.Perch/agent-server.json`;
const { baseURL, token } = JSON.parse(fs.readFileSync(discoveryPath, "utf8"));

async function perch(method, path, body) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(method === "POST" && path === "/streams"
        ? { "Idempotency-Key": randomUUID() }
        : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await response.json();
  if (!response.ok) throw new Error(json?.error?.code ?? response.statusText);
  return json;
}

const created = await perch("POST", "/streams", {
  client: "node",
  label: "Node",
  commitMode: "accept_to_paste",
  contentType: "text/markdown",
});

await perch("POST", `/streams/${created.id}/chunks`, {
  sequence: 0,
  text: "### From Node\n\nAccept in Perch to paste.\n",
});

await perch("POST", `/streams/${created.id}/complete`, {});
console.log("Ready in Perch — click in Notion, then Accept.");
// Do not print `token`.
```

### Swift

```swift
import Foundation

struct Discovery: Decodable {
    let baseURL: String
    let token: String
}

let discoveryURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(
        "Library/Application Support/com.fantomsuj.Perch/agent-server.json"
    )
let discovery = try JSONDecoder().decode(
    Discovery.self,
    from: Data(contentsOf: discoveryURL)
)

func request(
    _ method: String,
    path: String,
    idempotencyKey: String? = nil,
    body: Data? = nil
) async throws -> Data {
    var request = URLRequest(url: URL(string: discovery.baseURL + path)!)
    request.httpMethod = method
    request.setValue(
        "Bearer \(discovery.token)",
        forHTTPHeaderField: "Authorization"
    )
    if let body {
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
    }
    if let idempotencyKey {
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
    else { throw URLError(.badServerResponse) }
    return data
}

_ = try await request("GET", path: "/status")
let createBody = Data("""
{"client":"swift","label":"Swift","commitMode":"accept_to_paste","contentType":"text/markdown"}
""".utf8)
let created = try await request(
    "POST",
    path: "/streams",
    idempotencyKey: UUID().uuidString,
    body: createBody
)
// Parse `id` from `created`, then append chunks and complete.
// Never print discovery.token.
```

## Adapter notes

Claude Code, Codex, Cursor, OpenCode, and shell pipelines can all use this
protocol. Perch cannot silently intercept prose rendered inside another product
UI. Each agent must be instructed (skill), hooked, or wrapped to call these
endpoints—or use `script/perch_agent_client.swift pipe` to forward stdout.

## Out of scope for version 1

- Notion REST API credentials or remote Notion writes from Perch
- Multiple simultaneous streams
- Cloud-agent relays or non-loopback exposure
- Image/file transfer, arbitrary DOM/JavaScript execution, or agent read access
  to Notion page content
