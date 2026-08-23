#!/usr/bin/env bash
# Cloud Agent environment bootstrap for Perch.
#
# Perch is a native macOS (AppKit/WebKit/SwiftUI/Sparkle) accessory that can
# only be built and run with Xcode 26.2 on macOS. Cursor Cloud Agents run on
# Linux, so the app itself cannot be compiled, tested, or launched here. What we
# CAN provide is a matching Swift 6.2 toolchain plus resolved SwiftPM
# dependencies so an agent can read, navigate, resolve, and reason about the
# package on Linux. Building/testing/running the product still requires macOS.
#
# This script is idempotent: it is safe to run repeatedly and reuses an existing
# toolchain instead of downloading it again.
set -euo pipefail

SWIFT_VERSION="6.2"
SWIFT_RELEASE="swift-${SWIFT_VERSION}-RELEASE"
UBUNTU_TAG="ubuntu24.04"
SWIFT_PREFIX="/opt/swift"
SWIFT_BIN="${SWIFT_PREFIX}/usr/bin/swift"
DOWNLOAD_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/${SWIFT_RELEASE}/${SWIFT_RELEASE}-${UBUNTU_TAG}.tar.gz"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '==> %s\n' "$*"; }

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi
fi

install_runtime_dependencies() {
    log "Installing Swift runtime dependencies via apt"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq --no-install-recommends \
        binutils \
        libc6-dev \
        libcurl4-openssl-dev \
        libedit2 \
        libgcc-13-dev \
        libncurses-dev \
        libpython3-dev \
        libsqlite3-dev \
        libstdc++-13-dev \
        libxml2-dev \
        libz3-dev \
        pkg-config \
        tzdata \
        zlib1g-dev
}

install_swift_toolchain() {
    if [[ -x "${SWIFT_BIN}" ]] && "${SWIFT_BIN}" --version 2>/dev/null | grep -q "swift-${SWIFT_VERSION}"; then
        log "Swift ${SWIFT_VERSION} already installed at ${SWIFT_PREFIX}; skipping download"
    else
        log "Downloading Swift ${SWIFT_VERSION} for ${UBUNTU_TAG}"
        local archive
        archive="$(mktemp /tmp/swift-toolchain.XXXXXX.tar.gz)"
        curl -fsSL -o "${archive}" "${DOWNLOAD_URL}"
        log "Extracting toolchain to ${SWIFT_PREFIX}"
        $SUDO mkdir -p "${SWIFT_PREFIX}"
        $SUDO tar -xzf "${archive}" -C "${SWIFT_PREFIX}" --strip-components=1
        rm -f "${archive}"
    fi

    log "Linking swift and swiftc into /usr/local/bin"
    $SUDO ln -sf "${SWIFT_PREFIX}/usr/bin/swift" /usr/local/bin/swift
    $SUDO ln -sf "${SWIFT_PREFIX}/usr/bin/swiftc" /usr/local/bin/swiftc

    swift --version
}

resolve_package() {
    log "Resolving SwiftPM dependencies"
    (cd "${ROOT_DIR}" && swift package resolve)
}

install_runtime_dependencies
install_swift_toolchain
resolve_package

log "Cloud Agent bootstrap complete."
log "NOTE: 'swift build', 'swift test', ./script/build_and_run.sh, and the"
log "ScriptTests require macOS + Xcode 26.2 and cannot run on Linux."
