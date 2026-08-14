#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_release.sh"
TEST_DIR="$(mktemp -d /tmp/perch-package-release-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

FAKE_BIN="$TEST_DIR/bin"
CALL_LOG="$TEST_DIR/calls.log"
PLIST_LOG="$TEST_DIR/plist.log"
APPLESCRIPT_LOG="$TEST_DIR/applescript.log"
OUTPUT_DIR="$TEST_DIR/output"
NOTARY_KEY="$TEST_DIR/AuthKey_TEST.p8"

mkdir -p "$FAKE_BIN" "$OUTPUT_DIR"
touch "$CALL_LOG" "$NOTARY_KEY"

cat >"$FAKE_BIN/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'swift' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"

scratch_path=""
show_bin_path=false
for ((index = 1; index <= $#; index++)); do
    argument="${!index}"
    if [[ "$argument" == "--scratch-path" ]]; then
        next=$((index + 1))
        scratch_path="${!next}"
    elif [[ "$argument" == "--show-bin-path" ]]; then
        show_bin_path=true
    fi
done

bin_directory="$scratch_path/release"
if [[ "$show_bin_path" == true ]]; then
    echo "$bin_directory"
    exit 0
fi

mkdir -p "$bin_directory/Perch_Perch.bundle"
printf 'fake executable\n' >"$bin_directory/Perch"
printf 'fake resource\n' >"$bin_directory/Perch_Perch.bundle/resource.txt"
chmod +x "$bin_directory/Perch"
SCRIPT

cat >"$FAKE_BIN/security" <<'SCRIPT'
#!/usr/bin/env bash
printf 'security' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
printf '%s\n' "${FAKE_SECURITY_OUTPUT:-}"
SCRIPT

cat >"$FAKE_BIN/lipo" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'lipo' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"

if [[ "$1" == "-archs" ]]; then
    echo 'x86_64 arm64'
    exit 0
fi

output=""
for ((index = 1; index <= $#; index++)); do
    if [[ "${!index}" == "-output" ]]; then
        next=$((index + 1))
        output="${!next}"
    fi
done
printf 'universal fake executable\n' >"$output"
chmod +x "$output"
SCRIPT

cat >"$FAKE_BIN/codesign" <<'SCRIPT'
#!/usr/bin/env bash
printf 'codesign' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
last_argument="${!#}"
if [[ "$last_argument" == *.app ]]; then
    /usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' \
        "$last_argument/Contents/Info.plist" >>"$FAKE_PLIST_LOG" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Print :NSHumanReadableCopyright' \
        "$last_argument/Contents/Info.plist" >>"$FAKE_PLIST_LOG" 2>/dev/null || true
fi
SCRIPT

cat >"$FAKE_BIN/ditto" <<'SCRIPT'
#!/usr/bin/env bash
printf 'ditto' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
/usr/bin/ditto "$@"
SCRIPT

cat >"$FAKE_BIN/hdiutil" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"

if [[ "$1" == "create" || "$1" == "convert" ]]; then
    output="${!#}"
    printf 'fake disk image\n' >"$output"
elif [[ "$1" == "attach" || "$1" == "detach" ]]; then
    exit 0
elif [[ "$1" == "verify" ]]; then
    [[ -f "$2" ]]
else
    echo "unexpected hdiutil invocation: $*" >&2
    exit 1
fi
SCRIPT

cat >"$FAKE_BIN/osascript" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'osascript' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
/bin/cp /dev/stdin "$FAKE_APPLESCRIPT_LOG"
SCRIPT

cat >"$FAKE_BIN/tiffutil" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'tiffutil' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
output="${!#}"
/bin/cp "$2" "$output"
SCRIPT

cat >"$FAKE_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
printf 'xcrun' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
if [[ "$1" == "notarytool" && "${FAKE_NOTARY_FAILURE:-0}" == "1" ]]; then
    exit 1
fi
SCRIPT

cat >"$FAKE_BIN/spctl" <<'SCRIPT'
#!/usr/bin/env bash
printf 'spctl' >>"$FAKE_CALL_LOG"
printf ' %q' "$@" >>"$FAKE_CALL_LOG"
printf '\n' >>"$FAKE_CALL_LOG"
SCRIPT

chmod +x "$FAKE_BIN"/* "$PACKAGE_SCRIPT"

run_packager() {
    SWIFT_TOOL="$FAKE_BIN/swift" \
        SECURITY_TOOL="$FAKE_BIN/security" \
        LIPO_TOOL="$FAKE_BIN/lipo" \
        CODESIGN_TOOL="$FAKE_BIN/codesign" \
        DITTO_TOOL="$FAKE_BIN/ditto" \
        HDIUTIL_TOOL="$FAKE_BIN/hdiutil" \
        OSASCRIPT_TOOL="$FAKE_BIN/osascript" \
        TIFFUTIL_TOOL="$FAKE_BIN/tiffutil" \
        XCRUN_TOOL="$FAKE_BIN/xcrun" \
        SPCTL_TOOL="$FAKE_BIN/spctl" \
        PERCH_RELEASE_OUTPUT_DIR="$OUTPUT_DIR" \
        PERCH_NOTARY_KEY_PATH="$NOTARY_KEY" \
        PERCH_NOTARY_KEY_ID="TESTKEYID" \
        PERCH_NOTARY_ISSUER_ID="00000000-0000-0000-0000-000000000000" \
        FAKE_CALL_LOG="$CALL_LOG" \
        FAKE_PLIST_LOG="$PLIST_LOG" \
        FAKE_APPLESCRIPT_LOG="$APPLESCRIPT_LOG" \
        "$PACKAGE_SCRIPT"
}

export FAKE_SECURITY_OUTPUT='  1) DEVELOPERID123 "Developer ID Application: Perch Developer (TEAMID)"'
run_packager >/dev/null

DMG_PATH="$OUTPUT_DIR/Perch-0.1.0.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
if [[ ! -f "$DMG_PATH" || ! -f "$CHECKSUM_PATH" ]]; then
    echo "expected the DMG and checksum artifacts" >&2
    exit 1
fi
if [[ "$(head -n 1 "$PLIST_LOG")" != "true" ]]; then
    echo "expected the release bundle to prohibit multiple app instances" >&2
    exit 1
fi
if [[ "$(sed -n '2p' "$PLIST_LOG")" != "Copyright © 2026 Sujay Jayakar" ]]; then
    echo "expected the release bundle to include product ownership metadata" >&2
    exit 1
fi
if ! grep -Fq 'arm64-apple-macosx14.0' "$CALL_LOG" || \
    ! grep -Fq 'x86_64-apple-macosx14.0' "$CALL_LOG"; then
    echo "expected both release architecture builds" >&2
    exit 1
fi
if ! grep -Eq 'codesign .*--options runtime .*--timestamp .*Perch\.app$' "$CALL_LOG"; then
    echo "expected hardened-runtime app signing with a secure timestamp" >&2
    exit 1
fi
if grep -Eq 'codesign .*--force .*--deep' "$CALL_LOG"; then
    echo "release signing must not use codesign --deep" >&2
    exit 1
fi
if ! grep -Eq 'xcrun notarytool submit .*--key-id TESTKEYID .*--wait$' "$CALL_LOG"; then
    echo "expected notarytool submission with API credentials" >&2
    exit 1
fi
if ! grep -Fq 'xcrun stapler staple' "$CALL_LOG" || \
    ! grep -Fq 'xcrun stapler validate' "$CALL_LOG"; then
    echo "expected the notarization ticket to be stapled and validated" >&2
    exit 1
fi
if ! grep -Eq 'hdiutil create -size .* -fs HFS\+ -volname Perch -ov .*Perch-0\.1\.0-rw\.dmg$' "$CALL_LOG" || \
    ! grep -Eq 'hdiutil convert .*Perch-0\.1\.0-rw\.dmg -format UDZO -o .*Perch-0\.1\.0\.dmg$' "$CALL_LOG"; then
    echo "expected a writable DMG to be laid out before final compression" >&2
    exit 1
fi
if ! grep -Eq 'tiffutil -cathidpicheck .*DMGBackground\.png .*DMGBackground@2x\.png -out .*DMGBackground\.tiff$' "$CALL_LOG"; then
    echo "expected a multi-resolution Finder background" >&2
    exit 1
fi
if ! grep -Fq 'set background picture of theViewOptions to file ".background:DMGBackground.tiff" of dmgFolder' "$APPLESCRIPT_LOG" || \
    ! grep -Fq 'set position of item "Perch.app" of dmgFolder' "$APPLESCRIPT_LOG" || \
    ! grep -Fq 'set position of item "Applications" of dmgFolder' "$APPLESCRIPT_LOG"; then
    echo "expected the DMG Finder window to explain and present drag-to-install" >&2
    exit 1
fi

printf 'previous accepted release\n' >"$DMG_PATH"
: >"$CALL_LOG"
export FAKE_NOTARY_FAILURE=1
if run_packager >"$TEST_DIR/notary-failure.log" 2>&1; then
    echo "expected packaging to stop when notarization fails" >&2
    exit 1
fi
unset FAKE_NOTARY_FAILURE
if [[ "$(cat "$DMG_PATH")" != "previous accepted release" ]]; then
    echo "expected failed notarization to preserve the existing release artifact" >&2
    exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
: >"$CALL_LOG"
export FAKE_SECURITY_OUTPUT='     0 valid identities found'
if run_packager >"$TEST_DIR/missing-identity.log" 2>&1; then
    echo "expected packaging to reject a missing Developer ID identity" >&2
    exit 1
fi
if ! grep -Fq 'Developer ID Application signing identity is required' "$TEST_DIR/missing-identity.log"; then
    echo "expected an actionable missing-identity error" >&2
    exit 1
fi
if [[ -s "$CALL_LOG" ]] && grep -Fq 'swift build' "$CALL_LOG"; then
    echo "expected credential validation before starting a release build" >&2
    exit 1
fi

echo "package_release tests passed"
