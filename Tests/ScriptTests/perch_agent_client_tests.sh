#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT="$ROOT_DIR/script/perch_agent_client.swift"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/perch-agent-client-tests.XXXXXX")"
MOCK_LOG="$FIXTURE_DIR/mock.log"
MOCK_PID=""
# Deterministic fake token — must never appear in client stdout/stderr.
FAKE_TOKEN="fixture-token-do-not-leak-0123456789abcdef"

cleanup() {
  if [[ -n "${MOCK_PID}" ]] && kill -0 "$MOCK_PID" 2>/dev/null; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_no_token() {
  local blob="$1"
  if grep -F -q "$FAKE_TOKEN" <<<"$blob"; then
    fail "output leaked the discovery token"
  fi
}

write_discovery() {
  local path="$1"
  local port="$2"
  cat >"$path" <<EOF
{
  "schemaVersion": 1,
  "baseURL": "http://127.0.0.1:${port}/v1",
  "token": "${FAKE_TOKEN}",
  "pid": 4242,
  "startedAt": "2026-08-24T12:00:00Z"
}
EOF
  chmod 600 "$path"
}

start_mock_server() {
  local port="$1"
  local mode="$2"
  python3 - "$port" "$mode" "$MOCK_LOG" "$FAKE_TOKEN" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])
mode = sys.argv[2]
log_path = sys.argv[3]
expected_token = sys.argv[4]
stream_id = "11111111-2222-3333-4444-555555555555"
seen = {"cancelled": False, "chunks": []}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write("%s - %s\n" % (self.command, self.path))

    def _auth_ok(self):
        auth = self.headers.get("Authorization", "")
        return auth == f"Bearer {expected_token}"

    def _read_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(length) if length else b""

    def _send(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status, code, message, expected_sequence=None):
        err = {"code": code, "message": message}
        if expected_sequence is not None:
            err["expectedSequence"] = expected_sequence
        self._send(status, {"error": err})

    def do_GET(self):
        if not self._auth_ok():
            self._error(401, "unauthorized", "Authorization required.")
            return
        if self.path == "/v1/status":
            if mode == "status":
                self._send(200, {
                    "ready": True,
                    "targetAvailable": True,
                    "limits": {"maxChunkUTF8Bytes": 32768},
                    "activeStreamID": None,
                    "activeStreamPhase": None,
                })
                return
        self._error(404, "invalid_request", "Unknown route.")

    def do_POST(self):
        body = self._read_body()
        if not self._auth_ok():
            # Echo a red-herring token field that clients must still redact if
            # they dump bodies; our fixture responses never include the real token.
            self._error(401, "unauthorized", "Authorization required.")
            return

        if mode == "http_error" and self.path == "/v1/streams":
            self._error(409, "stream_active", "Another local agent stream is already active.")
            return

        if self.path == "/v1/streams":
            self._send(201, {
                "id": stream_id,
                "label": "Fixture",
                "client": "fixture",
                "contentType": "text/markdown",
                "phase": "receiving",
                "assembledText": "",
                "nextSequence": 0,
                "opaquePageID": None,
                "errorMessage": None,
                "canAccept": False,
            })
            return

        if self.path == f"/v1/streams/{stream_id}/chunks":
            payload = json.loads(body.decode("utf-8"))
            seen["chunks"].append(payload)
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write("CHUNK %s\n" % json.dumps(payload, ensure_ascii=False))
            self._send(200, {
                "id": stream_id,
                "label": "Fixture",
                "client": "fixture",
                "contentType": "text/markdown",
                "phase": "receiving",
                "assembledText": payload.get("text", ""),
                "nextSequence": int(payload.get("sequence", 0)) + 1,
                "opaquePageID": None,
                "errorMessage": None,
                "canAccept": False,
            })
            return

        if self.path == f"/v1/streams/{stream_id}/complete":
            self._send(200, {
                "id": stream_id,
                "label": "Fixture",
                "client": "fixture",
                "contentType": "text/markdown",
                "phase": "ready",
                "assembledText": "",
                "nextSequence": 1,
                "opaquePageID": None,
                "errorMessage": None,
                "canAccept": True,
            })
            return

        if self.path == f"/v1/streams/{stream_id}/cancel":
            seen["cancelled"] = True
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write("CANCELLED\n")
            self._send(200, {
                "id": stream_id,
                "label": "Fixture",
                "client": "fixture",
                "contentType": "text/markdown",
                "phase": "cancelled",
                "assembledText": "",
                "nextSequence": 0,
                "opaquePageID": None,
                "errorMessage": None,
                "canAccept": False,
            })
            return

        self._error(404, "invalid_request", "Unknown route.")

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
  MOCK_PID=$!
  for _ in $(seq 1 50); do
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then
      return 0
    fi
    sleep 0.05
  done
  fail "mock server did not start on port $port"
}

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

# --- missing discovery ---
MISSING="$FIXTURE_DIR/missing-agent-server.json"
set +e
MISSING_OUT="$("$CLIENT" --discovery "$MISSING" status 2>&1)"
MISSING_STATUS=$?
set -e
[[ "$MISSING_STATUS" -ne 0 ]] || fail "missing discovery should fail"
grep -qi "missing\|Allow local agents" <<<"$MISSING_OUT" \
  || fail "missing discovery message unclear: $MISSING_OUT"
assert_no_token "$MISSING_OUT"

# --- discovery parsing + status ---
PORT="$(pick_port)"
DISCOVERY="$FIXTURE_DIR/agent-server.json"
write_discovery "$DISCOVERY" "$PORT"
: >"$MOCK_LOG"
start_mock_server "$PORT" "status"
STATUS_OUT="$("$CLIENT" --discovery "$DISCOVERY" status 2>&1)"
assert_no_token "$STATUS_OUT"
grep -q '"ready"' <<<"$STATUS_OUT" || fail "status JSON missing ready: $STATUS_OUT"
kill "$MOCK_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
MOCK_PID=""

# --- HTTP error (stream_active) ---
PORT="$(pick_port)"
write_discovery "$DISCOVERY" "$PORT"
: >"$MOCK_LOG"
start_mock_server "$PORT" "http_error"
set +e
ERROR_OUT="$("$CLIENT" --discovery "$DISCOVERY" start --label Fixture 2>&1)"
ERROR_STATUS=$?
set -e
[[ "$ERROR_STATUS" -ne 0 ]] || fail "stream_active should fail"
grep -q "stream_active" <<<"$ERROR_OUT" || fail "expected stream_active in output: $ERROR_OUT"
assert_no_token "$ERROR_OUT"
kill "$MOCK_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
MOCK_PID=""

# --- unicode chunks via pipe ---
PORT="$(pick_port)"
write_discovery "$DISCOVERY" "$PORT"
: >"$MOCK_LOG"
start_mock_server "$PORT" "pipe"
UNICODE_INPUT=$'Hello 👋 cafe\u0301 日本語\n'
printf '%s' "$UNICODE_INPUT" \
  | "$CLIENT" --discovery "$DISCOVERY" pipe --label Unicode \
  >"$FIXTURE_DIR/pipe.out" 2>"$FIXTURE_DIR/pipe.err"
assert_no_token "$(cat "$FIXTURE_DIR/pipe.out")"
assert_no_token "$(cat "$FIXTURE_DIR/pipe.err")"
printf '%s' "$UNICODE_INPUT" >"$FIXTURE_DIR/pipe.expected"
cmp -s "$FIXTURE_DIR/pipe.out" "$FIXTURE_DIR/pipe.expected" \
  || fail "pipe did not mirror stdin to stdout"
grep -q "CHUNK" "$MOCK_LOG" || fail "pipe did not forward chunks"
# Ensure multi-byte text reached the mock without corruption.
python3 - "$MOCK_LOG" <<'PY'
import json, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
chunks = []
for line in text.splitlines():
    if line.startswith("CHUNK "):
        chunks.append(json.loads(line[len("CHUNK "):])["text"])
joined = "".join(chunks)
assert "👋" in joined, joined
assert "日本語" in joined, joined
assert "cafe" in joined, joined
PY
kill "$MOCK_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
MOCK_PID=""

# --- cancellation ---
PORT="$(pick_port)"
write_discovery "$DISCOVERY" "$PORT"
: >"$MOCK_LOG"
start_mock_server "$PORT" "pipe"
START_OUT="$("$CLIENT" --discovery "$DISCOVERY" start --client fixture --label Cancel 2>&1)"
assert_no_token "$START_OUT"
STREAM_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$START_OUT")"
CANCEL_OUT="$("$CLIENT" --discovery "$DISCOVERY" cancel --stream-id "$STREAM_ID" 2>&1)"
assert_no_token "$CANCEL_OUT"
grep -q "CANCELLED" "$MOCK_LOG" || fail "cancel was not received by mock"
grep -q '"phase"' <<<"$CANCEL_OUT" || fail "cancel response missing phase"
kill "$MOCK_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
MOCK_PID=""

# --- connection refused / missing server with valid discovery ---
PORT="$(pick_port)"
write_discovery "$DISCOVERY" "$PORT"
set +e
REFUSED_OUT="$("$CLIENT" --discovery "$DISCOVERY" status 2>&1)"
REFUSED_STATUS=$?
set -e
[[ "$REFUSED_STATUS" -ne 0 ]] || fail "missing server should fail"
assert_no_token "$REFUSED_OUT"

# --- invalid discovery JSON ---
BAD="$FIXTURE_DIR/bad.json"
printf '%s\n' '{"schemaVersion":1,"baseURL":"http://127.0.0.1:9/v1"}' >"$BAD"
set +e
BAD_OUT="$("$CLIENT" --discovery "$BAD" status 2>&1)"
BAD_STATUS=$?
set -e
[[ "$BAD_STATUS" -ne 0 ]] || fail "invalid discovery should fail"
assert_no_token "$BAD_OUT"

echo "perch_agent_client tests passed"
