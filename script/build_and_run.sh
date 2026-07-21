#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NotionPiP"
BUNDLE_ID="com.fantomsuj.NotionPiP"
MIN_SYSTEM_VERSION="14.0"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Support/NotionPiP.entitlements"

case "$MODE" in
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "error: full Xcode is required at $DEVELOPER_DIR" >&2
    exit 1
fi

cd "$ROOT_DIR"

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ -f "$ROOT_DIR/package.json" && -d "$ROOT_DIR/node_modules" ]]; then
    /usr/bin/env npm run build:editor --if-present
fi

swift build --product "$APP_NAME"
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
    echo "error: SwiftPM did not produce $BUILD_BINARY" >&2
    exit 1
fi

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_MACOS" "$APP_RESOURCES"
/bin/cp "$BUILD_BINARY" "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"

while IFS= read -r -d '' resource_bundle; do
    /usr/bin/ditto "$resource_bundle" "$APP_RESOURCES/$(basename "$resource_bundle")"
done < <(/usr/bin/find "$BUILD_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Notion PiP</string>
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
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>notion-pip</string>
            </array>
        </dict>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_SYSTEM_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
/usr/bin/codesign --force --deep --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

wait_for_process() {
    local attempt
    local process_id
    for attempt in {1..50}; do
        process_id="$(/usr/bin/pgrep -x "$APP_NAME" | /usr/bin/head -n 1 || true)"
        if [[ -n "$process_id" ]]; then
            echo "$process_id"
            return 0
        fi
        /bin/sleep 0.1
    done
    echo "error: $APP_NAME did not remain running after launch" >&2
    return 1
}

verify_bundle() {
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" == "$BUNDLE_ID" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")" == "$MIN_SYSTEM_VERSION" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST")" == "true" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$INFO_PLIST")" == "notion-pip" ]]
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        open_app
        PROCESS_ID="$(wait_for_process)"
        "$DEVELOPER_DIR/usr/bin/lldb" -p "$PROCESS_ID"
        ;;
    --logs|logs)
        open_app
        wait_for_process >/dev/null
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        wait_for_process >/dev/null
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        PROCESS_ID="$(wait_for_process)"
        verify_bundle
        echo "Verified $APP_BUNDLE (pid $PROCESS_ID)"
        ;;
esac
