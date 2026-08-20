#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "usage: $0 <Sparkle.framework> <signing-identity> <timestamp-argument>" >&2
    exit 2
fi

SPARKLE_FRAMEWORK="$1"
SIGNING_IDENTITY="$2"
TIMESTAMP_ARGUMENT="$3"
CODESIGN_TOOL="${CODESIGN_TOOL:-/usr/bin/codesign}"
SPARKLE_VERSION_ROOT="$SPARKLE_FRAMEWORK/Versions/B"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle framework not found at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

sign_component() {
    "$CODESIGN_TOOL" \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        "$TIMESTAMP_ARGUMENT" \
        "$@"
}

# Sparkle's nested code must be signed inside-out. Downloader keeps the
# network-client entitlement shipped by Sparkle.
sign_component "$SPARKLE_VERSION_ROOT/XPCServices/Installer.xpc"
sign_component \
    --preserve-metadata=entitlements \
    "$SPARKLE_VERSION_ROOT/XPCServices/Downloader.xpc"
sign_component "$SPARKLE_VERSION_ROOT/Autoupdate"
sign_component "$SPARKLE_VERSION_ROOT/Updater.app"
sign_component "$SPARKLE_FRAMEWORK"

"$CODESIGN_TOOL" --verify --deep --strict --verbose=2 "$SPARKLE_FRAMEWORK"
