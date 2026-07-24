# Notion PiP

Notion PiP is a native macOS 14+ menu-bar app for keeping one Notion page in a durable floating panel and capturing notes without losing work. This first slice provides the accessory app shell, canonical Notion page validation, external handoff parsing, and deterministic grouped history assembly.

The app is intentionally an `LSUIElement` accessory. It appears in the menu bar rather than the Dock.

## Create a page from the PiP

Click the `+` button in the PiP toolbar to open a fresh page in the embedded Notion session. The new page becomes the pinned PiP page automatically; no Notion integration token is required.

## Stash the PiP

Use the compact-arrow button in the PiP toolbar to tuck the panel onto the nearest left or right screen edge. A slim edge tab remains available across Spaces; click it to restore the same live Notion page, including its current WebView session and navigation state. Drag the tab to move it to either side or a different height; it snaps to the nearest horizontal screen edge when released. `Command-Shift-P` stashes a visible PiP and restores it on the next press. The menu-bar icon also restores a stashed panel while retaining its regular show/hide behavior.

## Live-only page display

The PiP displays the live embedded Notion page. It does not generate or show a native cached page preview. Choosing **Disconnect** for a personal Notion token also removes legacy derived preview files from `Application Support/NotionPiP/NativePageCache`; the app never performs that cleanup automatically at launch or during an upgrade.

## Build and run

Full Xcode 26.2 or newer is required. The project-local script selects it explicitly, builds the SwiftPM executable, stages `dist/NotionPiP.app`, copies SwiftPM resource bundles, ad-hoc signs the app, and launches it through Launch Services:

```sh
./script/build_and_run.sh
```

Optional modes are `--debug`, `--logs`, `--telemetry`, and `--verify`.

Run the tests directly with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Set up with Codex

After cloning the repository, open it in Codex and ask:

> Set up and run this app locally. Follow the repository's AGENTS.md instructions.

Codex will check the Mac and Xcode prerequisites, build and verify the app, and
explain any manual setup that remains. The detailed setup and troubleshooting
guidance lives in [`AGENTS.md`](AGENTS.md).

## Security boundary

Only HTTPS pages on `app.notion.com`, `notion.so`, and `www.notion.so` with a 32-hex-character page ID are accepted. `notion.so` inputs canonicalize to `www.notion.so`, while `app.notion.com` inputs retain that host. Canonical URLs never retain credentials, query strings, or fragments. The `notion-pip` handoff contract is documented in `docs/HANDOFF_PROTOCOL.md`.

The development app is sandboxed with outbound network access. Ad-hoc signing is for local development only; it is not Developer ID distribution or notarization.

## Upstream reuse

Behavioral reference provenance and exclusions are documented in `docs/UPSTREAM_REUSE.md`. The upstream project is not a runtime dependency, and its NotionInter fonts and assets are not included.
