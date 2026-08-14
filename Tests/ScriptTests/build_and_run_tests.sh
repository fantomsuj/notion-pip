#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
TEST_DIR="$(mktemp -d /tmp/perch-build-and-run-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

FIXTURE_ROOT="$TEST_DIR/project"
FAKE_BIN="$TEST_DIR/bin"
CALL_LOG="$TEST_DIR/calls.log"
PROCESS_STATE="$TEST_DIR/processes"
TERMINATING_STATE="$TEST_DIR/terminating"
LOCK_DIR="$TEST_DIR/shared/perch-build-and-run.lock"
mkdir -p "$FIXTURE_ROOT/script" "$FIXTURE_ROOT/Support" "$FAKE_BIN" "$(dirname "$LOCK_DIR")"
cp "$BUILD_SCRIPT" "$FIXTURE_ROOT/script/build_and_run.sh"
cp "$ROOT_DIR/Support/Version.env" "$FIXTURE_ROOT/Support/Version.env"
cp "$ROOT_DIR/Support/Perch.icns" "$FIXTURE_ROOT/Support/Perch.icns"
cp "$ROOT_DIR/Support/Perch.entitlements" "$FIXTURE_ROOT/Support/Perch.entitlements"
touch "$CALL_LOG" "$PROCESS_STATE" "$TERMINATING_STATE"

cat >"$FIXTURE_ROOT/script/sign_app.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

cat >"$FAKE_BIN/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'swift %s\n' "$*" >>"$FAKE_CALL_LOG"
if [[ "$*" == *"--show-bin-path"* ]]; then
    echo "$FAKE_BUILD_DIR"
    exit 0
fi
mkdir -p "$FAKE_BUILD_DIR"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKE_BUILD_DIR/Perch"
chmod +x "$FAKE_BUILD_DIR/Perch"
SCRIPT

cat >"$FAKE_BIN/codesign" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

cat >"$FAKE_BIN/pkill" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
name="$2"
printf 'pkill %s\n' "$name" >>"$FAKE_CALL_LOG"
if /usr/bin/grep -q "^$name " "$FAKE_PROCESS_STATE"; then
    printf '%s\n' "$name" >>"$FAKE_TERMINATING_STATE"
    exit 0
fi
exit 1
SCRIPT

cat >"$FAKE_BIN/pgrep" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
name="$2"
printf 'pgrep %s\n' "$name" >>"$FAKE_CALL_LOG"
matches="$(/usr/bin/awk -v name="$name" '$1 == name { print $2 }' "$FAKE_PROCESS_STATE")"
if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches"
fi
if /usr/bin/grep -qx "$name" "$FAKE_TERMINATING_STATE"; then
    /usr/bin/awk -v name="$name" '$1 != name' "$FAKE_PROCESS_STATE" >"$FAKE_PROCESS_STATE.next"
    /bin/mv "$FAKE_PROCESS_STATE.next" "$FAKE_PROCESS_STATE"
    /usr/bin/awk -v name="$name" '$0 != name' "$FAKE_TERMINATING_STATE" >"$FAKE_TERMINATING_STATE.next"
    /bin/mv "$FAKE_TERMINATING_STATE.next" "$FAKE_TERMINATING_STATE"
fi
[[ -n "$matches" ]]
SCRIPT

cat >"$FAKE_BIN/open" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'open %s\n' "$*" >>"$FAKE_CALL_LOG"
if [[ -s "$FAKE_PROCESS_STATE" ]]; then
    echo "open called while old processes were still running" >&2
    exit 1
fi
for process_id in ${FAKE_LAUNCHED_PIDS:-4242}; do
    printf 'Perch %s\n' "$process_id" >>"$FAKE_PROCESS_STATE"
done
SCRIPT

cat >"$FAKE_BIN/ps" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_PROCESS_EXECUTABLE:-$FAKE_EXPECTED_EXECUTABLE}"
SCRIPT

cat >"$FAKE_BIN/sleep" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

cat >"$FAKE_BIN/process-alive" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

cat >"$FAKE_BIN/log" <<'SCRIPT'
#!/usr/bin/env bash
echo "Filtering the log data"
while :; do /bin/sleep 1; done
SCRIPT

chmod +x "$FIXTURE_ROOT/script/"*.sh "$FAKE_BIN/"*

run_launcher() {
    env \
        SWIFT_TOOL="$FAKE_BIN/swift" \
        PKILL_TOOL="$FAKE_BIN/pkill" \
        PGREP_TOOL="$FAKE_BIN/pgrep" \
        OPEN_TOOL="$FAKE_BIN/open" \
        PS_TOOL="$FAKE_BIN/ps" \
        SLEEP_TOOL="$FAKE_BIN/sleep" \
        PROCESS_ALIVE_TOOL="$FAKE_BIN/process-alive" \
        CODESIGN_TOOL="$FAKE_BIN/codesign" \
        LOG_TOOL="$FAKE_BIN/log" \
        PERCH_BUILD_AND_RUN_LOCK_DIR="$LOCK_DIR" \
        FAKE_BUILD_DIR="$TEST_DIR/build" \
        FAKE_CALL_LOG="$CALL_LOG" \
        FAKE_PROCESS_STATE="$PROCESS_STATE" \
        FAKE_TERMINATING_STATE="$TERMINATING_STATE" \
        FAKE_EXPECTED_EXECUTABLE="$FIXTURE_ROOT/dist/Perch.app/Contents/MacOS/Perch" \
        "$FIXTURE_ROOT/script/build_and_run.sh" "$@"
}

# A lock held by another worktree must fail before any build starts.
mkdir "$LOCK_DIR"
if run_launcher run >"$TEST_DIR/lock.log" 2>&1; then
    echo "expected a concurrent build-and-run invocation to fail" >&2
    exit 1
fi
if ! grep -Fq 'another Perch build-and-run is already active' "$TEST_DIR/lock.log"; then
    echo "expected an actionable shared-lock contention error" >&2
    exit 1
fi
if [[ -s "$CALL_LOG" ]]; then
    echo "expected lock contention to fail before building or managing processes" >&2
    exit 1
fi
rmdir "$LOCK_DIR"

# Both current and legacy process names must be gone before launch.
printf 'Perch 101\nPerch 102\nNotionPiP 103\n' >"$PROCESS_STATE"
run_launcher run >/dev/null
if [[ "$(cat "$PROCESS_STATE")" != "Perch 4242" ]]; then
    echo "expected launch to leave exactly the newly launched Perch process" >&2
    exit 1
fi
if ! grep -Fq 'pkill Perch' "$CALL_LOG" || ! grep -Fq 'pkill NotionPiP' "$CALL_LOG"; then
    echo "expected both Perch and legacy NotionPiP processes to be terminated" >&2
    exit 1
fi
if [[ "$(grep -c '^pgrep Perch$' "$CALL_LOG")" -lt 2 ]] || \
    [[ "$(grep -c '^pgrep NotionPiP$' "$CALL_LOG")" -lt 2 ]]; then
    echo "expected launcher to wait until both process names disappeared" >&2
    exit 1
fi
if grep -Fq 'open -n ' "$CALL_LOG"; then
    echo "launcher must not explicitly request a new app instance" >&2
    exit 1
fi
if [[ -d "$LOCK_DIR" ]]; then
    echo "expected the shared launch lock to be released on exit" >&2
    exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' \
    "$FIXTURE_ROOT/dist/Perch.app/Contents/Info.plist" 2>/dev/null || true)" != "true" ]]; then
    echo "expected the development bundle to prohibit multiple app instances" >&2
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSHumanReadableCopyright' \
    "$FIXTURE_ROOT/dist/Perch.app/Contents/Info.plist" 2>/dev/null || true)" \
    != "Copyright © 2026 Sujay Jayakar" ]]; then
    echo "expected the development bundle to include product ownership metadata" >&2
    exit 1
fi

# Verification succeeds only for one process whose executable is the staged app.
: >"$CALL_LOG"
: >"$PROCESS_STATE"
run_launcher --verify >/dev/null

: >"$PROCESS_STATE"
if FAKE_LAUNCHED_PIDS='4242 4243' run_launcher --verify >"$TEST_DIR/multiple.log" 2>&1; then
    echo "expected verification to reject multiple Perch processes" >&2
    exit 1
fi
if ! grep -Fq 'expected exactly one Perch process' "$TEST_DIR/multiple.log"; then
    echo "expected a clear multiple-process verification error" >&2
    exit 1
fi

: >"$PROCESS_STATE"
if FAKE_PROCESS_EXECUTABLE='/tmp/Other.app/Contents/MacOS/Perch' \
    run_launcher --verify >"$TEST_DIR/wrong-executable.log" 2>&1; then
    echo "expected verification to reject a Perch process from another bundle" >&2
    exit 1
fi
if ! grep -Fq 'does not use the staged executable' "$TEST_DIR/wrong-executable.log"; then
    echo "expected a clear wrong-executable verification error" >&2
    exit 1
fi

echo "build_and_run tests passed"
