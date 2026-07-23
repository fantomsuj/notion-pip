# Codex instructions

## Helping someone run Notion PiP locally

When the user asks to set up or try the app, prioritize getting the existing app
running. Do not change product code, signing settings, entitlements, or the
user's system configuration unless a concrete setup failure requires it and the
user approves the change.

### Requirements

- The built app targets macOS 14 or newer. Building it from source requires
  macOS 15.6 or newer because that is the minimum host version for Xcode 26.2.
- Full Xcode 26.2 is required at `/Applications/Xcode.app`. Command Line Tools
  alone are not sufficient.
- The build produces a native executable for the current Mac, so either Apple
  silicon or Intel is acceptable when building from source.
- Node.js is not required merely to run the app. The generated Quick Capture
  editor assets are checked into the repository. Node and `npm ci` are needed
  only when modifying or validating the TypeScript editor.
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

3. If full Xcode is missing, stop and tell the user to install and open Xcode.
   Do not silently install large system software or accept Xcode's license with
   `sudo`. After installation, Xcode may ask the user to accept its license and
   install additional components.
4. From the repository root, build, stage, ad-hoc sign, launch, and verify the
   app:

   ```sh
   ./script/build_and_run.sh --verify
   ```

5. Report the result and the staged app location:
   `dist/NotionPiP.app`.

The build script intentionally quits any running process named `NotionPiP`
before rebuilding. It then launches the new build. A successful verification
prints `Verified .../dist/NotionPiP.app` with a process ID.

### What the user should expect

- Notion PiP is a menu-bar accessory, so it appears in the menu bar rather than
  the Dock.
- The user signs in to their own Notion account inside the app. Never ask them
  to paste a Notion password, session cookie, or integration token into chat or
  the terminal.
- A personal integration token is optional and should be entered only through
  the app's own settings UI.
- The locally built app is ad-hoc signed for development. This is expected and
  is different from a Developer ID-signed, notarized distribution build.

### Troubleshooting

- If the script says full Xcode is required, confirm that the app is installed
  exactly at `/Applications/Xcode.app`; the script deliberately selects that
  path.
- If Xcode reports an incomplete first launch, ask the user to open Xcode and
  finish its prompts, then rerun the script.
- If the app launched but seems absent, look for the Notion PiP icon in the menu
  bar; do not treat the missing Dock icon as a crash.
- If verification fails, rerun the failing command or the build script and
  inspect its actual output before editing code.
- For a clean source validation, run:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

- Only when working on `Web/QuickCaptureEditor`, install the pinned JavaScript
  dependencies and run its checks:

  ```sh
  npm ci
  npm test
  npm run typecheck
  npm run build:editor
  ```

Keep setup fixes minimal and explain any remaining manual action clearly.
