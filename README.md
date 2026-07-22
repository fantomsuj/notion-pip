# Notion PiP

Notion PiP is a native macOS 14+ menu-bar app for keeping one Notion page in a durable floating panel and capturing notes without losing work. This first slice provides the accessory app shell, canonical Notion page validation, external handoff parsing, and deterministic grouped history assembly.

The app is intentionally an `LSUIElement` accessory. It appears in the menu bar rather than the Dock.

## Stash the PiP

Use the compact-arrow button in the PiP toolbar to tuck the panel onto the nearest left or right screen edge. A slim edge tab remains available across Spaces; click it to restore the same live Notion page, including its current WebView session and navigation state. `Command-Shift-P` stashes a visible PiP and restores it on the next press. The menu-bar icon also restores a stashed panel while retaining its regular show/hide behavior.

## Build and run

Full Xcode 26.2 is required. The project-local script selects it explicitly, builds the SwiftPM executable, stages `dist/NotionPiP.app`, copies SwiftPM resource bundles, ad-hoc signs the app, and launches it through Launch Services:

```sh
./script/build_and_run.sh
```

Optional modes are `--debug`, `--logs`, `--telemetry`, and `--verify`.

Run the tests directly with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Security boundary

Only HTTPS pages on `notion.so` and `www.notion.so` with a 32-hex-character page ID are accepted. Canonical URLs never retain credentials, query strings, or fragments. The `notion-pip` handoff contract is documented in `docs/HANDOFF_PROTOCOL.md`.

The development app is sandboxed with outbound network access and user-selected file read/write access for future recovery exports. Ad-hoc signing is for local development only; it is not Developer ID distribution or notarization.

## Upstream reuse

Behavioral reference provenance and exclusions are documented in `docs/UPSTREAM_REUSE.md`. The upstream project is not a runtime dependency, and its NotionInter fonts and assets are not included.
