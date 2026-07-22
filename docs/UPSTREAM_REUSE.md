# Upstream reuse record

## Behavioral reference

- Project: `fantomsuj/notion-quick-note`
- Pinned commit: `72cd9d194bb4478adbf072188e6388bd9a8f8ab6`
- License: MIT

The upstream extension is a behavioral reference for Notion page URL handling and later OAuth/capture workflows. It is not a source package, binary, submodule, or runtime dependency of Notion PiP.

## Reused in this slice

This native slice carries forward only high-level behavior: accept real Notion page URLs, derive stable lowercase page identity, discard navigation-only query and fragment data, and make cross-app handoff explicit.

The implementation and tests in this repository were written for the native Swift architecture. No upstream production source was copied.

## Explicit exclusions

- No NotionInter font files or other upstream font assets.
- No Notion editor HTML, CSS, JavaScript, icons, or brand assets.
- No extension manifest, Chrome runtime code, OAuth credentials, or bundled output.
- No dependency on the upstream repository at build or runtime.

The app uses system fonts, SF Symbols, and semantic AppKit/SwiftUI colors.
