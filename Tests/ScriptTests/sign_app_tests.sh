#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIGN_SCRIPT="$ROOT_DIR/script/sign_app.sh"
SETUP_SCRIPT="$ROOT_DIR/script/setup_local_signing.sh"
TEST_DIR="$(mktemp -d /tmp/perch-sign-app-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

FAKE_SECURITY="$TEST_DIR/security"
FAKE_CODESIGN="$TEST_DIR/codesign"
APP_BUNDLE="$TEST_DIR/Perch.app"
ENTITLEMENTS="$TEST_DIR/Perch.entitlements"
CALL_LOG="$TEST_DIR/codesign-call"

mkdir -p "$APP_BUNDLE"
touch "$ENTITLEMENTS"

cat >"$FAKE_SECURITY" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_SECURITY_OUTPUT:-}"
SCRIPT
chmod +x "$FAKE_SECURITY"

cat >"$FAKE_CODESIGN" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_CODESIGN_CALL_LOG"
SCRIPT
chmod +x "$FAKE_CODESIGN"

run_signer() {
    SECURITY_TOOL="$FAKE_SECURITY" \
        CODESIGN_TOOL="$FAKE_CODESIGN" \
        FAKE_CODESIGN_CALL_LOG="$CALL_LOG" \
        "$SIGN_SCRIPT" "$APP_BUNDLE" "$ENTITLEMENTS"
}

assert_signing_identity() {
    local expected="$1"
    local actual
    actual="$(awk 'previous == "--sign" { print; exit } { previous = $0 }' "$CALL_LOG")"
    if [[ "$actual" != "$expected" ]]; then
        echo "expected signing identity '$expected', got '$actual'" >&2
        exit 1
    fi
}

export PERCH_SIGNING_IDENTITY="EXPLICIT-IDENTITY"
export FAKE_SECURITY_OUTPUT=""
run_signer >/dev/null
assert_signing_identity "EXPLICIT-IDENTITY"

unset PERCH_SIGNING_IDENTITY
export FAKE_SECURITY_OUTPUT='  1) ABCDEF1234567890 "Apple Development: Developer (TEAMID)"'
run_signer >/dev/null
assert_signing_identity "ABCDEF1234567890"

export FAKE_SECURITY_OUTPUT='     0 valid identities found'
output="$(run_signer 2>&1)"
assert_signing_identity "-"
if [[ "$output" != *"ad-hoc signing"* ]]; then
    echo "expected an ad-hoc signing diagnostic" >&2
    exit 1
fi

echo "sign_app tests passed"

FAKE_OPENSSL="$TEST_DIR/openssl"
SETUP_LOG="$TEST_DIR/setup-log"
IDENTITY_MARKER="$TEST_DIR/identity-installed"

cat >"$FAKE_SECURITY" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "find-identity" ]]; then
    if [[ -f "$FAKE_IDENTITY_MARKER" ]]; then
        echo '  1) LOCALIDENTITY "Perch Local Development"'
    else
        echo '     0 valid identities found'
    fi
elif [[ "$1" == "import" ]]; then
    printf 'import\n' >>"$FAKE_SETUP_LOG"
    touch "$FAKE_IDENTITY_MARKER"
elif [[ "$1" == "add-trusted-cert" ]]; then
    printf 'trust\n' >>"$FAKE_SETUP_LOG"
    if [[ "${FAKE_SECURITY_FAIL_TRUST:-0}" == "1" ]]; then
        exit 1
    fi
elif [[ "$1" == "delete-identity" ]]; then
    printf 'delete\n' >>"$FAKE_SETUP_LOG"
    rm -f "$FAKE_IDENTITY_MARKER"
else
    echo "unexpected security invocation: $*" >&2
    exit 1
fi
SCRIPT
chmod +x "$FAKE_SECURITY"

cat >"$FAKE_OPENSSL" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "rand" ]]; then
    echo 'temporary-password'
    exit 0
fi
if [[ "$1" == "x509" ]]; then
    echo 'sha256 Fingerprint=AA:BB:CC:DD'
    exit 0
fi
for ((index = 1; index <= $#; index++)); do
    argument="${!index}"
    if [[ "$argument" == "-out" || "$argument" == "-keyout" ]]; then
        next=$((index + 1))
        touch "${!next}"
    fi
done
SCRIPT
chmod +x "$FAKE_OPENSSL"

run_setup() {
    SECURITY_TOOL="$FAKE_SECURITY" \
        OPENSSL_TOOL="$FAKE_OPENSSL" \
        LOGIN_KEYCHAIN="$TEST_DIR/login.keychain-db" \
        FAKE_SETUP_LOG="$SETUP_LOG" \
        FAKE_IDENTITY_MARKER="$IDENTITY_MARKER" \
        "$SETUP_SCRIPT"
}

run_setup >/dev/null
if [[ "$(cat "$SETUP_LOG")" != $'import\ntrust' ]]; then
    echo "expected the local identity to be imported and trusted" >&2
    exit 1
fi

first_run_calls="$(wc -l <"$SETUP_LOG")"
run_setup >/dev/null
second_run_calls="$(wc -l <"$SETUP_LOG")"
if [[ "$first_run_calls" != "$second_run_calls" ]]; then
    echo "expected local signing setup to be idempotent" >&2
    exit 1
fi

rm -f "$IDENTITY_MARKER" "$SETUP_LOG"
export FAKE_SECURITY_FAIL_TRUST=1
if run_setup >/dev/null 2>&1; then
    echo "expected local signing setup to fail when trust is denied" >&2
    exit 1
fi
unset FAKE_SECURITY_FAIL_TRUST
if [[ -f "$IDENTITY_MARKER" ]]; then
    echo "expected failed setup to remove the partially imported identity" >&2
    exit 1
fi
if [[ "$(cat "$SETUP_LOG")" != $'import\ntrust\ndelete' ]]; then
    echo "expected failed setup to roll back the imported identity" >&2
    exit 1
fi

echo "setup_local_signing tests passed"
