#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 <app-bundle> <entitlements>" >&2
    exit 2
fi

APP_BUNDLE="$1"
ENTITLEMENTS="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECURITY_TOOL="${SECURITY_TOOL:-/usr/bin/security}"
CODESIGN_TOOL="${CODESIGN_TOOL:-/usr/bin/codesign}"
SIGNING_IDENTITY="${PERCH_SIGNING_IDENTITY:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$($SECURITY_TOOL find-identity -p codesigning -v 2>/dev/null | /usr/bin/awk '
        /"Perch Local Development"|"Apple Development:|"Developer ID Application:|"Mac Developer:/ {
            print $2
            exit
        }
    ')"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="-"
    echo "warning: no stable code-signing identity found; using ad-hoc signing" >&2
    echo "warning: macOS permissions and login-item approval can reset after a rebuild" >&2
else
    echo "Signing with stable identity $SIGNING_IDENTITY"
fi

SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    CODESIGN_TOOL="$CODESIGN_TOOL" \
        "$SCRIPT_DIR/sign_sparkle.sh" \
        "$SPARKLE_FRAMEWORK" \
        "$SIGNING_IDENTITY" \
        "--timestamp=none"
fi

"$CODESIGN_TOOL" \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
