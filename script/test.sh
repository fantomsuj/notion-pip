#!/usr/bin/env bash
# Runs the same test sequence as CI. Use this instead of plain `swift test`:
# the WebKit and AppKit suites below are flaky when they share one process,
# so they run one at a time after the main pass.
#
#   script/test.sh            # script tests, then all Swift tests
#   script/test.sh --scripts  # only the shell script tests
#   script/test.sh --swift    # only the Swift tests
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run_scripts=true
run_swift=true
case "${1:-}" in
  "") ;;
  --scripts) run_swift=false ;;
  --swift) run_scripts=false ;;
  *)
    echo "usage: script/test.sh [--scripts | --swift]" >&2
    exit 64
    ;;
esac

# Suites that need their own process because they touch WebKit or AppKit
# window state.
ISOLATED_SUITES=(
  ExternalDropActivatingWebViewTests
  NotionEditorSelectionTests
  NotionWebSessionTests
  PiPChromeViewTests
  PiPPanelGeometryTests
  WebNavigationDestinationTests
)

group_start() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::$1"; else echo "==> $1"; fi
}

group_end() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::"; fi
}

if [[ "$run_scripts" == true ]]; then
  for test_script in Tests/ScriptTests/*_tests.sh; do
    group_start "$test_script"
    bash "$test_script"
    group_end
  done
fi

if [[ "$run_swift" == true ]]; then
  skip_pattern="($(IFS='|'; echo "${ISOLATED_SUITES[*]}"))"
  group_start "swift test (shared process)"
  swift test --skip "$skip_pattern"
  group_end

  for suite in "${ISOLATED_SUITES[@]}"; do
    group_start "swift test --filter $suite"
    swift test --skip-build --filter "$suite"
    group_end
  done
fi
