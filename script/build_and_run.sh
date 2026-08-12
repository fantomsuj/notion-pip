#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Perch"
BUNDLE_ID="com.fantomsuj.Perch"
MIN_SYSTEM_VERSION="14.0"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR

SWIFT_TOOL="${SWIFT_TOOL:-swift}"
PKILL_TOOL="${PKILL_TOOL:-/usr/bin/pkill}"
PGREP_TOOL="${PGREP_TOOL:-/usr/bin/pgrep}"
OPEN_TOOL="${OPEN_TOOL:-/usr/bin/open}"
PS_TOOL="${PS_TOOL:-/bin/ps}"
SLEEP_TOOL="${SLEEP_TOOL:-/bin/sleep}"
PROCESS_ALIVE_TOOL="${PROCESS_ALIVE_TOOL:-/bin/kill}"
CODESIGN_TOOL="${CODESIGN_TOOL:-/usr/bin/codesign}"
PLISTBUDDY_TOOL="${PLISTBUDDY_TOOL:-/usr/libexec/PlistBuddy}"
LOG_TOOL="${LOG_TOOL:-/usr/bin/log}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Support/Perch.entitlements"
SIGN_SCRIPT="$ROOT_DIR/script/sign_app.sh"
APP_ICON_SOURCE="$ROOT_DIR/Support/Perch.icns"

VERSION_CONFIG="$ROOT_DIR/Support/Version.env"
BUILD_AND_RUN_LOCK_DIR="${PERCH_BUILD_AND_RUN_LOCK_DIR:-${TMPDIR:-/tmp}/com.fantomsuj.Perch-build-and-run.lock}"
BUILD_AND_RUN_LOCK_HELD=false

release_build_and_run_lock() {
    if [[ "$BUILD_AND_RUN_LOCK_HELD" == true ]]; then
        /bin/rmdir "$BUILD_AND_RUN_LOCK_DIR" >/dev/null 2>&1 || true
        BUILD_AND_RUN_LOCK_HELD=false
    fi
}

cleanup_on_exit() {
    if [[ "$(type -t cleanup_verification_log || true)" == "function" ]]; then
        cleanup_verification_log
    fi
    release_build_and_run_lock
}

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

if [[ ! "${PERCH_VERSION:-}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "error: PERCH_VERSION must contain two or three numeric components" >&2
    exit 1
fi
if [[ ! "${PERCH_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: PERCH_BUILD_NUMBER must be a positive integer" >&2
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

if ! /bin/mkdir "$BUILD_AND_RUN_LOCK_DIR" 2>/dev/null; then
    echo "error: another Perch build-and-run is already active" >&2
    echo "error: shared lock: $BUILD_AND_RUN_LOCK_DIR" >&2
    exit 1
fi
BUILD_AND_RUN_LOCK_HELD=true
trap cleanup_on_exit EXIT
trap 'exit 1' HUP INT TERM

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
/bin/cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Perch.icns"

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
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_SYSTEM_VERSION</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
"$SIGN_SCRIPT" "$APP_BUNDLE" "$ENTITLEMENTS"
"$CODESIGN_TOOL" --verify --deep --strict "$APP_BUNDLE"

open_app() {
    terminate_existing_instances
    "$OPEN_TOOL" "$APP_BUNDLE"
}

terminate_existing_instances() {
    local attempt
    local process_name
    local processes_remain

    for process_name in "$APP_NAME" NotionPiP; do
        "$PKILL_TOOL" -x "$process_name" >/dev/null 2>&1 || true
    done

    for attempt in {1..50}; do
        processes_remain=false
        for process_name in "$APP_NAME" NotionPiP; do
            if "$PGREP_TOOL" -x "$process_name" >/dev/null 2>&1; then
                processes_remain=true
            fi
        done
        if [[ "$processes_remain" == false ]]; then
            return 0
        fi
        "$SLEEP_TOOL" 0.1
    done

    echo "error: existing Perch or NotionPiP processes did not exit before launch" >&2
    return 1
}

wait_for_process() {
    local attempt
    local process_id
    for attempt in {1..50}; do
        process_id="$("$PGREP_TOOL" -x "$APP_NAME" | /usr/bin/head -n 1 || true)"
        if [[ -n "$process_id" ]]; then
            echo "$process_id"
            return 0
        fi
        "$SLEEP_TOOL" 0.1
    done
    echo "error: $APP_NAME did not remain running after launch" >&2
    return 1
}

verify_bundle() {
    [[ "$("$PLISTBUDDY_TOOL" -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" == "$BUNDLE_ID" ]] || return 1
    [[ "$("$PLISTBUDDY_TOOL" -c 'Print :CFBundleIconFile' "$INFO_PLIST")" == "Perch.icns" ]] || return 1
    [[ "$("$PLISTBUDDY_TOOL" -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")" == "$MIN_SYSTEM_VERSION" ]] || return 1
    [[ "$("$PLISTBUDDY_TOOL" -c 'Print :LSMultipleInstancesProhibited' "$INFO_PLIST")" == "true" ]] || return 1
    [[ "$("$PLISTBUDDY_TOOL" -c 'Print :LSUIElement' "$INFO_PLIST")" == "true" ]] || return 1
    [[ "$("$PLISTBUDDY_TOOL" -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$INFO_PLIST")" == "perch" ]] || return 1
    [[ -f "$APP_RESOURCES/Perch.icns" ]] || return 1
    "$CODESIGN_TOOL" --verify --deep --strict "$APP_BUNDLE" || return 1
}

verify_process_identity() {
    local expected_process_id="$1"
    local process_count
    local process_executable
    local process_ids

    process_ids="$("$PGREP_TOOL" -x "$APP_NAME" || true)"
    process_count="$(printf '%s\n' "$process_ids" | /usr/bin/awk 'NF { count++ } END { print count + 0 }')"
    if [[ "$process_count" -ne 1 ]]; then
        echo "error: expected exactly one $APP_NAME process, found $process_count" >&2
        return 1
    fi
    if [[ "$process_ids" != "$expected_process_id" ]]; then
        echo "error: the verified $APP_NAME process changed during startup" >&2
        return 1
    fi

    process_executable="$("$PS_TOOL" -p "$expected_process_id" -o comm=)"
    process_executable="${process_executable#"${process_executable%%[![:space:]]*}"}"
    process_executable="${process_executable%"${process_executable##*[![:space:]]}"}"
    if [[ "$process_executable" != "$APP_BINARY" ]]; then
        echo "error: $APP_NAME process $expected_process_id does not use the staged executable" >&2
        echo "error: expected $APP_BINARY, found $process_executable" >&2
        return 1
    fi
}

verify_process_stability() {
    local process_id="$1"
    "$SLEEP_TOOL" 2
    if ! "$PROCESS_ALIVE_TOOL" -0 "$process_id" >/dev/null 2>&1; then
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

    VERIFICATION_LOG_FILE="$(/usr/bin/mktemp /tmp/perch-verify.XXXXXX)"
    "$LOG_TOOL" stream --style compact --predicate "process == \"$APP_NAME\"" \
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
        "$SLEEP_TOOL" 0.02
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
        if verify_process_identity "$PROCESS_ID"; then
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
        start_verification_log
        if run_verification; then
            echo "Verified $APP_BUNDLE (pid $PROCESS_ID)"
        else
            VERIFICATION_STATUS=$?
            exit "$VERIFICATION_STATUS"
        fi
        ;;
esac
