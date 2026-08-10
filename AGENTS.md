# Codex instructions

## Product intent

Notion PiP is an always-on-screen overlay. Its persistent, all-Spaces panel
behavior is intentional and should not be reported as an `NSPanel` defect.

## Writing Swift code

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement
  contracts unless the task explicitly changes them.
- Before editing, inspect relevant call sites and nearby tests. Follow existing
  patterns, keep the diff focused, and avoid speculative abstractions.
- Prefer clear APIs at the call site, value semantics where appropriate, and
  documentation for public declarations. Avoid force unwraps and casts unless
  the invariant is explicit.
- Use structured concurrency, actors, `@MainActor`, and `Sendable` types as
  appropriate. Do not silence concurrency errors with `@unchecked Sendable`,
  `nonisolated(unsafe)`, or detached tasks without a documented reason.
- Add regression tests for behavior changes. Keep tests independent because
  Swift tests may run in parallel.
- Validate Swift changes with:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

  Report the command result and anything not verified.

## Helping someone run Notion PiP locally

When the user asks to set up or try the app, prioritize getting the existing app
running. Do not change product code, signing settings, entitlements, or the
user's system configuration unless a concrete setup failure requires it and the
user approves the change.

### Requirements

- The built app targets macOS 14 or newer. Building it from source requires
  macOS 15.6 or newer because that is the minimum host version for Xcode 26.2.
- Full Xcode 26.2 or newer is required at `/Applications/Xcode.app`. Command
  Line Tools alone are not sufficient.
- The build produces a native executable for the current Mac, so either Apple
  silicon or Intel is acceptable when building from source.
- Node.js is not required to build or run the app.
- No `.env` file, Notion token, signing certificate, or other secret is required
  to build and launch the app.

### Setup workflow

1. Preserve the user's existing work. Check `git status --short` before making
   any changes and do not discard unrelated changes.
2. Confirm the machine and toolchain with read-only checks:

   ```sh
   sw_vers -productVersion
   test -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version
   ```

3. If the host is older than macOS 15.6, full Xcode is missing, or the detected
   Xcode is older than 26.2, stop and explain the unmet requirement. Do not
   silently install large system software or accept Xcode's license with
   `sudo`. After installation, Xcode may ask the user to accept its license and
   install additional components.
4. Check `pgrep -x NotionPiP`. If the app is running, stop and ask the user to
   finish or save active work and quit it before continuing. The build script
   terminates running `NotionPiP` processes, which can discard unsaved edits.
5. From the repository root, build, stage, ad-hoc sign, launch, and verify the
   app:

   ```sh
   ./script/build_and_run.sh --verify
   ```

6. Report the result and the staged app location:
   `dist/NotionPiP.app`.

The build script intentionally quits any running process named `NotionPiP`
before rebuilding. It then launches the new build. A successful verification
prints `Verified .../dist/NotionPiP.app` with a process ID.

### What the user should expect

- Notion PiP is an accessory, so it does not appear in the Dock. Its menu-bar
  icon is shown by default but can be hidden in Settings; the PiP remains
  reachable through its edge handle or global shortcut.
- The user signs in to their own Notion account inside the app. Never ask them
  to paste a Notion password, session cookie, or integration token into chat or
  the terminal.
- A personal integration token is optional, enables workspace page search, and
  should be entered only through the app's own settings UI.
- The locally built app is ad-hoc signed for development. This is expected and
  is different from a Developer ID-signed, notarized distribution build.
- Launch at Login works only from the staged `dist/NotionPiP.app`, not by
  running the SwiftPM executable directly. Its toggle reflects the current
  macOS ServiceManagement registration and may direct the user to System
  Settings when approval is required.
- Rebuilding replaces and ad-hoc signs the staged bundle again. macOS may ask
  for login-item approval again or retain a stale entry after a rebuild, so
  local results do not replace testing a stable Developer ID-signed beta.

### Troubleshooting

- If the script says full Xcode is required, confirm that the app is installed
  exactly at `/Applications/Xcode.app`; the script deliberately selects that
  path.
- If Xcode reports an incomplete first launch, ask the user to open Xcode and
  finish its prompts, then rerun the script.
- If the app launched but seems absent, first look for the Notion PiP icon in
  the menu bar. If the icon preference is off, use the configured global
  shortcut; a shortcut registration failure temporarily forces the icon back
  on. Do not treat the missing Dock icon as a crash.
- If verification fails, rerun the failing command or the build script and
  inspect its actual output before editing code.
- If Launch at Login is unavailable, confirm the process was launched through
  `dist/NotionPiP.app`. If it requires approval, use the button in Settings and
  allow Notion PiP under General → Login Items & Extensions; returning to the
  app refreshes the displayed state.
- For a clean source validation, run:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

Keep setup fixes minimal and explain any remaining manual action clearly.
