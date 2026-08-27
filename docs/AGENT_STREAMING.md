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
3. Optionally use **Install Agent Skill** to write the protocol skill for Claude
   Code, Codex, or Cursor under that tool’s `skills/stream-to-perch/` directory.

While disabled, Perch opens no agent listener and publishes no discovery
credential. Disable the setting to revoke access immediately: the listener
stops and the matching discovery file is removed.

## Behavior

- One active stream at a time (`receiving` → `ready` → Accept → paste).
- Ready and retryable failed streams show a compact overlay by default:
  status, agent label, **Accept**, and a chevron for transcript / Copy / Dismiss.
- Expansion is view-only; collapsing never cancels or pastes.
- Notification Accept/Dismiss actions apply only to the stream ID they carry.
- Inactive receiving streams expire after 10 minutes; ready/failed streams after
  30 minutes. Expiry is scheduled on phase entry and rescheduled on activity.

## Security model

When the listener is ready, Perch atomically publishes an owner-only (`0600`)
discovery file at:

```text
~/Library/Application Support/com.fantomsuj.Perch/agent-server.json
```

| Field | Meaning |
|---|---|
| `schemaVersion` | Discovery schema. Version 1 is current. |
| `baseURL` | Loopback base including `/v1`. |
| `token` | Per-launch bearer secret. Rotate whenever the listener starts. |
| `pid` | Publishing Perch process ID. |
| `startedAt` | ISO-8601 start time. |

Rules:

- Bind address is loopback only. Never expose this listener beyond the Mac.
- Every `/v1` request requires `Authorization: Bearer <token>`.
- POST bodies use HTTP header `Content-Type: application/json`. The create-body
  field `"contentType": "text/markdown"` describes payload format only.
- Browser `Origin` headers are rejected. Host must be loopback for the published
  port. Chunked request bodies are rejected. Connections are not reused.
- Stream acknowledgments return `id`, `phase`, `nextSequence`, and optional
  `error` (create may include `limits`). Assembled Markdown and page identity
  stay internal.
- Settings → Copy Connection Details omits the bearer token and states the
  correct HTTP `Content-Type: application/json`.
- Tokens and streamed text must not enter logs, analytics, crash messages, or
  support reports.

See also [PRIVACY.md](PRIVACY.md).

## Protocol (canonical)

The installable skill is the canonical protocol reference:

- Bundled resource: `Sources/Perch/Resources/stream-to-perch/SKILL.md`
- Repository path: [`agent-skills/stream-to-perch/SKILL.md`](../agent-skills/stream-to-perch/SKILL.md)
  (symlink to the bundled resource)

Settings → Install Agent Skill writes that document for the selected agent.
Keep protocol details there; this doc covers product behavior and security.

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

### curl sketch

```sh
DISCOVERY="$HOME/Library/Application Support/com.fantomsuj.Perch/agent-server.json"
BASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["baseURL"])' "$DISCOVERY")"
TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$DISCOVERY")"

curl -sS "$BASE/status" -H "Authorization: Bearer $TOKEN"
curl -sS -X POST "$BASE/streams" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: demo-create-1" \
  -d '{"client":"curl","label":"curl","commitMode":"accept_to_paste","contentType":"text/markdown"}'
```

After `complete`, click in Notion and press **Accept** in Perch. Never print the
token.

## Out of scope for version 1

- Notion REST API credentials or remote Notion writes from Perch
- Multiple simultaneous streams
- Cloud-agent relays or non-loopback exposure
- Image/file transfer, arbitrary DOM/JavaScript execution, or agent read access
  to Notion page content
