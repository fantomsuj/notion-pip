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
SIGN_SCRIPT="$ROOT_DIR/script/sign_app.sh"
APP_ICON_SOURCE="$ROOT_DIR/Support/NotionPiP.icns"

VERSION_CONFIG="$ROOT_DIR/Support/Version.env"

if [[ ! -f "$VERSION_CONFIG" ]]; then
    echo "error: missing release version configuration at $VERSION_CONFIG" >&2
    exit 1
fi
if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "error: missing app icon at $APP_ICON_SOURCE" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$VERSION_CONFIG"

if [[ ! "${NOTION_PIP_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "error: NOTION_PIP_VERSION must contain two or three numeric components" >&2
    exit 1
fi
if [[ ! "${NOTION_PIP_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: NOTION_PIP_BUILD_NUMBER must be a positive integer" >&2
    exit 1
fi

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
/bin/cp "$APP_ICON_SOURCE" "$APP_RESOURCES/NotionPiP.icns"

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
    <key>CFBundleIconFile</key>
    <string>NotionPiP.icns</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$NOTION_PIP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$NOTION_PIP_BUILD_NUMBER</string>
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
"$SIGN_SCRIPT" "$APP_BUNDLE" "$ENTITLEMENTS"
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
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" == "$BUNDLE_ID" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")" == "NotionPiP.icns" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")" == "$MIN_SYSTEM_VERSION" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST")" == "true" ]] || return 1
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$INFO_PLIST")" == "notion-pip" ]] || return 1
    [[ -f "$APP_RESOURCES/NotionPiP_NotionPiP.bundle/QuickCapture/index.html" ]] || return 1
    [[ -f "$APP_RESOURCES/NotionPiP.icns" ]] || return 1
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" || return 1
}

verify_process_stability() {
    local process_id="$1"
    /bin/sleep 2
    if ! /bin/kill -0 "$process_id" >/dev/null 2>&1; then
        echo "error: $APP_NAME exited during the startup stability interval" >&2
        return 1
    fi
}

VERIFICATION_LOG_FILE=""
VERIFICATION_LOG_PID=""

stop_verification_log() {
    local log_pid

    if [[ -n "$VERIFICATION_LOG_PID" ]]; then
        log_pid="$VERIFICATION_LOG_PID"
        VERIFICATION_LOG_PID=""
        if /bin/kill "$log_pid" >/dev/null 2>&1; then
            wait "$log_pid" 2>/dev/null || true
            return 0
        fi

        wait "$log_pid" 2>/dev/null || true
        echo "error: unified log capture exited before startup verification completed" >&2
        return 1
    fi
}

cleanup_verification_log() {
    if ! stop_verification_log; then
        :
    fi
    if [[ -n "$VERIFICATION_LOG_FILE" ]]; then
        /bin/rm -f "$VERIFICATION_LOG_FILE"
        VERIFICATION_LOG_FILE=""
    fi
}

start_verification_log() {
    local attempt

    VERIFICATION_LOG_FILE="$(/usr/bin/mktemp /tmp/notion-pip-verify.XXXXXX)"
    /usr/bin/log stream --style compact --predicate "process == \"$APP_NAME\"" \
        >"$VERIFICATION_LOG_FILE" 2>&1 &
    VERIFICATION_LOG_PID=$!

    for attempt in {1..50}; do
        if ! /bin/kill -0 "$VERIFICATION_LOG_PID" >/dev/null 2>&1; then
            wait "$VERIFICATION_LOG_PID" 2>/dev/null || true
            VERIFICATION_LOG_PID=""
            echo "error: failed to start unified log capture" >&2
            return 1
        fi
        if [[ -s "$VERIFICATION_LOG_FILE" ]]; then
            return 0
        fi
        /bin/sleep 0.02
    done

    echo "error: unified log capture was not ready before launch" >&2
    return 1
}

verify_no_concurrency_diagnostics() {
    local grep_status

    if /usr/bin/grep -F \
        -e "ModelContext passed across actor boundary" \
        -e "NSManagedObjectContext concurrency debugging" \
        "$VERIFICATION_LOG_FILE" >&2; then
        echo "error: SwiftData concurrency diagnostic detected during startup" >&2
        return 1
    else
        grep_status=$?
    fi

    if [[ "$grep_status" -ne 1 ]]; then
        echo "error: could not inspect unified startup logs" >&2
        return 1
    fi
}

run_verification() {
    local diagnostic_status=0
    local phase_status
    local verification_status=0

    PROCESS_ID=""

    if open_app; then
        :
    else
        verification_status=$?
    fi

    if [[ "$verification_status" -eq 0 ]]; then
        if PROCESS_ID="$(wait_for_process)"; then
            :
        else
            verification_status=$?
        fi
    fi

    if [[ "$verification_status" -eq 0 ]]; then
        if verify_bundle; then
            :
        else
            verification_status=$?
        fi
    fi

    if [[ "$verification_status" -eq 0 ]]; then
        if verify_process_stability "$PROCESS_ID"; then
            :
        else
            verification_status=$?
        fi
    fi

    if stop_verification_log; then
        :
    else
        phase_status=$?
        if [[ "$verification_status" -eq 0 ]]; then
            verification_status="$phase_status"
        fi
    fi

    if verify_no_concurrency_diagnostics; then
        :
    else
        diagnostic_status=$?
    fi

    cleanup_verification_log

    if [[ "$verification_status" -ne 0 ]]; then
        return "$verification_status"
    fi
    if [[ "$diagnostic_status" -ne 0 ]]; then
        return "$diagnostic_status"
    fi
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
        trap cleanup_verification_log EXIT
        trap 'exit 1' HUP INT TERM
        start_verification_log
        if run_verification; then
            trap - EXIT HUP INT TERM
            echo "Verified $APP_BUNDLE (pid $PROCESS_ID)"
        else
            VERIFICATION_STATUS=$?
            trap - EXIT HUP INT TERM
            exit "$VERIFICATION_STATUS"
        fi
        ;;
esac
