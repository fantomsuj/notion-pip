#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Perch"
BUNDLE_ID="com.fantomsuj.Perch"
MIN_SYSTEM_VERSION="14.0"
RELEASE_ARCHITECTURES=(arm64 x86_64)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${PERCH_RELEASE_OUTPUT_DIR:-$ROOT_DIR/dist}"
ENTITLEMENTS="$ROOT_DIR/Support/Perch.entitlements"
APP_ICON_SOURCE="$ROOT_DIR/Support/Perch.icns"
DMG_BACKGROUND_SOURCE="$ROOT_DIR/Support/DMGBackground.svg"
VERSION_CONFIG="$ROOT_DIR/Support/Version.env"
SPARKLE_CONFIG="$ROOT_DIR/Support/Sparkle.env"
SIGN_SPARKLE_SCRIPT="$ROOT_DIR/script/sign_sparkle.sh"

SWIFT_TOOL="${SWIFT_TOOL:-swift}"
SECURITY_TOOL="${SECURITY_TOOL:-/usr/bin/security}"
LIPO_TOOL="${LIPO_TOOL:-/usr/bin/lipo}"
CODESIGN_TOOL="${CODESIGN_TOOL:-/usr/bin/codesign}"
DITTO_TOOL="${DITTO_TOOL:-/usr/bin/ditto}"
HDIUTIL_TOOL="${HDIUTIL_TOOL:-/usr/bin/hdiutil}"
SIPS_TOOL="${SIPS_TOOL:-/usr/bin/sips}"
TIFFUTIL_TOOL="${TIFFUTIL_TOOL:-/usr/bin/tiffutil}"
OSASCRIPT_TOOL="${OSASCRIPT_TOOL:-/usr/bin/osascript}"
XCRUN_TOOL="${XCRUN_TOOL:-xcrun}"
SPCTL_TOOL="${SPCTL_TOOL:-/usr/sbin/spctl}"
SHASUM_TOOL="${SHASUM_TOOL:-/usr/bin/shasum}"

usage() {
    cat <<'USAGE'
usage: script/package_release.sh

Builds, Developer ID signs, notarizes, staples, and validates a Universal 2
Perch DMG. The following environment variables are required:

  PERCH_DISTRIBUTION_SIGNING_IDENTITY   Optional when exactly one Developer ID
                                        Application identity is installed.

And either a local notarytool profile:

  PERCH_NOTARY_KEYCHAIN_PROFILE

Or App Store Connect API credentials:

  PERCH_NOTARY_KEY_PATH
  PERCH_NOTARY_KEY_ID
  PERCH_NOTARY_ISSUER_ID
USAGE
}

if [[ "$#" -ne 0 ]]; then
    usage >&2
    exit 2
fi

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool not found: $tool" >&2
        exit 1
    fi
}

for tool in \
    "$SWIFT_TOOL" \
    "$SECURITY_TOOL" \
    "$LIPO_TOOL" \
    "$CODESIGN_TOOL" \
    "$DITTO_TOOL" \
    "$HDIUTIL_TOOL" \
    "$SIPS_TOOL" \
    "$TIFFUTIL_TOOL" \
    "$OSASCRIPT_TOOL" \
    "$XCRUN_TOOL" \
    "$SPCTL_TOOL" \
    "$SHASUM_TOOL"; do
    require_tool "$tool"
done

if [[ ! -f "$VERSION_CONFIG" ]]; then
    echo "error: missing release version configuration at $VERSION_CONFIG" >&2
    exit 1
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "error: missing entitlements at $ENTITLEMENTS" >&2
    exit 1
fi
if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "error: missing app icon at $APP_ICON_SOURCE" >&2
    exit 1
fi
if [[ ! -f "$DMG_BACKGROUND_SOURCE" ]]; then
    echo "error: missing DMG background at $DMG_BACKGROUND_SOURCE" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$VERSION_CONFIG"
# shellcheck disable=SC1090
source "$SPARKLE_CONFIG"

if [[ ! "${PERCH_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
    echo "error: PERCH_VERSION must contain three numeric components" >&2
    exit 1
fi
if [[ ! "${PERCH_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: PERCH_BUILD_NUMBER must be a positive integer" >&2
    exit 1
fi

SIGNING_IDENTITY="${PERCH_DISTRIBUTION_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$($SECURITY_TOOL find-identity -p codesigning -v 2>/dev/null | /usr/bin/awk '
        /"Developer ID Application:/ {
            print $2
            exit
        }
    ')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "error: a Developer ID Application signing identity is required" >&2
    echo "error: set PERCH_DISTRIBUTION_SIGNING_IDENTITY or install the certificate" >&2
    exit 1
fi

NOTARY_ARGUMENTS=()
if [[ -n "${PERCH_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGUMENTS=(--keychain-profile "$PERCH_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${PERCH_NOTARY_KEY_PATH:-}" || -n "${PERCH_NOTARY_KEY_ID:-}" || -n "${PERCH_NOTARY_ISSUER_ID:-}" ]]; then
    if [[ -z "${PERCH_NOTARY_KEY_PATH:-}" || -z "${PERCH_NOTARY_KEY_ID:-}" || -z "${PERCH_NOTARY_ISSUER_ID:-}" ]]; then
        echo "error: all three App Store Connect notary credential variables are required" >&2
        exit 1
    fi
    if [[ ! -f "$PERCH_NOTARY_KEY_PATH" ]]; then
        echo "error: notarization API key not found at $PERCH_NOTARY_KEY_PATH" >&2
        exit 1
    fi
    NOTARY_ARGUMENTS=(
        --key "$PERCH_NOTARY_KEY_PATH"
        --key-id "$PERCH_NOTARY_KEY_ID"
        --issuer "$PERCH_NOTARY_ISSUER_ID"
    )
else
    echo "error: notarization credentials are required" >&2
    echo "error: configure PERCH_NOTARY_KEYCHAIN_PROFILE or App Store Connect API credentials" >&2
    exit 1
fi

DMG_PATH="$OUTPUT_DIR/$APP_NAME-$PERCH_VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/perch-release.XXXXXX")"
BUILD_ROOT="$TEMP_ROOT/build"
DMG_STAGE="$TEMP_ROOT/dmg"
APP_BUNDLE="$TEMP_ROOT/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
WORK_DMG_PATH="$TEMP_ROOT/$APP_NAME-$PERCH_VERSION.dmg"
RW_DMG_PATH="$TEMP_ROOT/$APP_NAME-$PERCH_VERSION-rw.dmg"
DMG_MOUNT_POINT="$TEMP_ROOT/mount"
DMG_ATTACHED=false

cleanup() {
    if [[ "$DMG_ATTACHED" == true ]]; then
        "$HDIUTIL_TOOL" detach "$DMG_MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

/bin/mkdir -p "$OUTPUT_DIR" "$BUILD_ROOT" "$DMG_STAGE"

declare -a ARCH_BINARIES=()
ARM64_BIN_DIRECTORY=""

for architecture in "${RELEASE_ARCHITECTURES[@]}"; do
    triple="$architecture-apple-macosx$MIN_SYSTEM_VERSION"
    scratch_path="$BUILD_ROOT/$architecture"

    echo "Building $APP_NAME $PERCH_VERSION ($PERCH_BUILD_NUMBER) for $architecture"
    "$SWIFT_TOOL" build \
        --package-path "$ROOT_DIR" \
        --configuration release \
        --product "$APP_NAME" \
        --triple "$triple" \
        --scratch-path "$scratch_path"

    bin_directory="$($SWIFT_TOOL build \
        --package-path "$ROOT_DIR" \
        --configuration release \
        --triple "$triple" \
        --scratch-path "$scratch_path" \
        --show-bin-path)"
    architecture_binary="$bin_directory/$APP_NAME"

    if [[ ! -x "$architecture_binary" ]]; then
        echo "error: SwiftPM did not produce $architecture_binary" >&2
        exit 1
    fi

    ARCH_BINARIES+=("$architecture_binary")
    if [[ "$architecture" == "arm64" ]]; then
        ARM64_BIN_DIRECTORY="$bin_directory"
    fi
done

/bin/mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
"$LIPO_TOOL" -create "${ARCH_BINARIES[@]}" -output "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"

binary_architectures="$($LIPO_TOOL -archs "$APP_BINARY")"
for architecture in "${RELEASE_ARCHITECTURES[@]}"; do
    if [[ " $binary_architectures " != *" $architecture "* ]]; then
        echo "error: release binary is missing the $architecture slice" >&2
        exit 1
    fi
done

/bin/cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Perch.icns"
while IFS= read -r -d '' resource_bundle; do
    "$DITTO_TOOL" "$resource_bundle" "$APP_RESOURCES/$(basename "$resource_bundle")"
done < <(/usr/bin/find "$ARM64_BIN_DIRECTORY" -maxdepth 1 -type d -name '*.bundle' -print0)
if [[ ! -d "$ARM64_BIN_DIRECTORY/Sparkle.framework" ]]; then
    echo "error: SwiftPM did not produce $ARM64_BIN_DIRECTORY/Sparkle.framework" >&2
    exit 1
fi
"$DITTO_TOOL" "$ARM64_BIN_DIRECTORY/Sparkle.framework" \
    "$APP_FRAMEWORKS/Sparkle.framework"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Perch</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>Perch.icns</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$PERCH_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$PERCH_BUILD_NUMBER</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>perch</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_SYSTEM_VERSION</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Sujay Jayakar</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

unexpected_nested_code="$({
    /usr/bin/find "$APP_CONTENTS" -mindepth 1 \
        \( -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' \) \
        -o -type f -name '*.dylib' \) \
        ! -path "$APP_FRAMEWORKS/Sparkle.framework" \
        ! -path "$APP_FRAMEWORKS/Sparkle.framework/*" \
        -print -quit
} 2>/dev/null || true)"
if [[ -n "$unexpected_nested_code" ]]; then
    echo "error: release bundle contains unsupported nested code:" >&2
    echo "error: $unexpected_nested_code" >&2
    exit 1
fi

echo "Signing $APP_BUNDLE with Developer ID identity $SIGNING_IDENTITY"
CODESIGN_TOOL="$CODESIGN_TOOL" \
    "$SIGN_SPARKLE_SCRIPT" \
    "$APP_FRAMEWORKS/Sparkle.framework" \
    "$SIGNING_IDENTITY" \
    "--timestamp"
"$CODESIGN_TOOL" \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
"$CODESIGN_TOOL" --verify --deep --strict --verbose=2 "$APP_BUNDLE"

"$DITTO_TOOL" "$APP_BUNDLE" "$DMG_STAGE/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_STAGE/Applications"
/bin/mkdir -p "$DMG_STAGE/.background" "$DMG_MOUNT_POINT"
"$SIPS_TOOL" -s format png "$DMG_BACKGROUND_SOURCE" \
    --out "$TEMP_ROOT/DMGBackground.png" >/dev/null
"$SIPS_TOOL" -s format png -z 800 1280 "$DMG_BACKGROUND_SOURCE" \
    --out "$TEMP_ROOT/DMGBackground@2x.png" >/dev/null
"$TIFFUTIL_TOOL" -cathidpicheck \
    "$TEMP_ROOT/DMGBackground.png" \
    "$TEMP_ROOT/DMGBackground@2x.png" \
    -out "$DMG_STAGE/.background/DMGBackground.tiff" >/dev/null

echo "Creating $APP_NAME-$PERCH_VERSION.dmg"
stage_size_kb="$(/usr/bin/du -sk "$DMG_STAGE" | /usr/bin/awk '{ print $1 }')"
dmg_size_kb="$((stage_size_kb + 16384))"
"$HDIUTIL_TOOL" create \
    -size "${dmg_size_kb}k" \
    -fs HFS+ \
    -volname "$APP_NAME" \
    -ov \
    "$RW_DMG_PATH"
"$HDIUTIL_TOOL" attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$DMG_MOUNT_POINT" \
    "$RW_DMG_PATH" >/dev/null
DMG_ATTACHED=true
"$DITTO_TOOL" "$DMG_STAGE" "$DMG_MOUNT_POINT"

"$OSASCRIPT_TOOL" <<APPLESCRIPT
set dmgFolder to POSIX file "$DMG_MOUNT_POINT" as alias
tell application "Finder"
    open dmgFolder
    delay 1
    set dmgWindow to front Finder window
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set pathbar visible of dmgWindow to false
    set bounds of dmgWindow to {100, 100, 740, 500}
    set theViewOptions to icon view options of dmgWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 112
    set text size of theViewOptions to 14
    set background picture of theViewOptions to file ".background:DMGBackground.tiff" of dmgFolder
    set position of item "$APP_NAME.app" of dmgFolder to {180, 215}
    set position of item "Applications" of dmgFolder to {460, 215}
    update dmgFolder without registering applications
    delay 2
    close dmgWindow
end tell
APPLESCRIPT

/bin/sync
"$HDIUTIL_TOOL" detach "$DMG_MOUNT_POINT"
DMG_ATTACHED=false
"$HDIUTIL_TOOL" convert "$RW_DMG_PATH" \
    -format UDZO \
    -o "$WORK_DMG_PATH"

"$CODESIGN_TOOL" \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$WORK_DMG_PATH"
"$CODESIGN_TOOL" --verify --strict --verbose=2 "$WORK_DMG_PATH"

echo "Submitting $APP_NAME-$PERCH_VERSION.dmg for notarization"
"$XCRUN_TOOL" notarytool submit "$WORK_DMG_PATH" \
    "${NOTARY_ARGUMENTS[@]}" \
    --wait
"$XCRUN_TOOL" stapler staple "$WORK_DMG_PATH"
"$XCRUN_TOOL" stapler validate "$WORK_DMG_PATH"

"$HDIUTIL_TOOL" verify "$WORK_DMG_PATH"
"$SPCTL_TOOL" --assess --verbose=2 --type open \
    --context context:primary-signature "$WORK_DMG_PATH"
"$SPCTL_TOOL" --assess --verbose=2 --type execute "$APP_BUNDLE"

/bin/mv -f "$WORK_DMG_PATH" "$DMG_PATH"

(
    cd "$OUTPUT_DIR"
    "$SHASUM_TOOL" -a 256 "$(basename "$DMG_PATH")" >"$(basename "$CHECKSUM_PATH")"
)

echo "Packaged and notarized $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
