#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT_DIR/script/verify_sparkle_key.swift"
TEST_PRIVATE_KEY="nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
TEST_PUBLIC_KEY="11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

printf '%s' "$TEST_PRIVATE_KEY" | "$VERIFIER" "$TEST_PUBLIC_KEY" >/dev/null

if printf '%s' "$TEST_PRIVATE_KEY" | \
    "$VERIFIER" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
    >/dev/null 2>&1; then
    echo "expected a mismatched Sparkle key pair to fail" >&2
    exit 1
fi

if printf 'not-base64' | "$VERIFIER" "$TEST_PUBLIC_KEY" >/dev/null 2>&1; then
    echo "expected malformed Sparkle private key input to fail" >&2
    exit 1
fi

echo "sparkle_key tests passed"
