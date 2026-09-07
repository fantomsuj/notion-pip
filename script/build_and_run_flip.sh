#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Flip"
BUNDLE_ID="com.fantomsuj.Flip"
MIN_SYSTEM_VERSION="14.0"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR

SWIFT_TOOL="${SWIFT_TOOL:-swift}"
PKILL_TOOL="${PKILL_TOOL:-/usr/bin/pkill}"
PGREP_TOOL="${PGREP_TOOL:-/usr/bin/pgrep}"
OPEN_TOOL="${OPEN_TOOL:-/usr/bin/open}"
CODESIGN_TOOL="${CODESIGN_TOOL:-/usr/bin/codesign}"
SLEEP_TOOL="${SLEEP_TOOL:-/bin/sleep}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${FLIP_DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Support/Flip.entitlements"
LOCAL_ENTITLEMENTS="$ROOT_DIR/Support/Flip.entitlements"
SIGN_SCRIPT="$ROOT_DIR/script/sign_app.sh"
VERSION_CONFIG="$ROOT_DIR/Support/FlipVersion.env"

if [[ ! -f "$VERSION_CONFIG" ]]; then
    echo "error: missing Flip version configuration at $VERSION_CONFIG" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$VERSION_CONFIG"

if [[ ! "${FLIP_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "error: FLIP_VERSION must contain two or three numeric components" >&2
    exit 1
fi
if [[ ! "${FLIP_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: FLIP_BUILD_NUMBER must be a positive integer" >&2
    exit 1
fi

case "$MODE" in
    run|--debug|debug|--verify|verify)
        ;;
    *)
        echo "usage: $0 [run|--debug|--verify]" >&2
        exit 2
        ;;
esac

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "error: full Xcode is required at $DEVELOPER_DIR" >&2
    exit 1
fi

cd "$ROOT_DIR"

"$SWIFT_TOOL" build --product "$APP_NAME"
BUILD_DIR="$("$SWIFT_TOOL" build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
    echo "error: SwiftPM did not produce $BUILD_BINARY" >&2
    exit 1
fi

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_MACOS" "$APP_RESOURCES"
/bin/cp "$BUILD_BINARY" "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Flip</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$FLIP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$FLIP_BUILD_NUMBER</string>
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
    <key>NSScreenCaptureUsageDescription</key>
    <string>Flip takes a one-frame snapshot of the frontmost window so it can animate a card-flip to Notion. The snapshot stays in memory for the animation and is not saved.</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
if [[ -x "$SIGN_SCRIPT" ]]; then
    "$SIGN_SCRIPT" "$APP_BUNDLE" "$LOCAL_ENTITLEMENTS"
    "$CODESIGN_TOOL" --verify --deep --strict "$APP_BUNDLE"
fi

open_app() {
    "$PKILL_TOOL" -x "$APP_NAME" >/dev/null 2>&1 || true
    "$OPEN_TOOL" "$APP_BUNDLE"
}

case "$MODE" in
    --debug|debug)
        echo "Staged $APP_BUNDLE"
        echo "Build binary: $BUILD_BINARY"
        ;;
    --verify|verify)
        open_app
        "$SLEEP_TOOL" 1
        if ! "$PGREP_TOOL" -x "$APP_NAME" >/dev/null 2>&1; then
            echo "error: Flip did not stay running after launch" >&2
            exit 1
        fi
        echo "Verified $APP_BUNDLE pid=$("$PGREP_TOOL" -x "$APP_NAME" | /usr/bin/head -n 1)"
        ;;
    *)
        open_app
        echo "Launched $APP_BUNDLE"
        ;;
esac
