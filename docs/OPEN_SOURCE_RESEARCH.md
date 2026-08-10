# Open-source reference research

This is a curated set of implementation and product references for Notion PiP. These projects are references, not dependencies. Reuse must remain compatible with each project's license and preserve any required attribution.

## Recommended references

### Itsypin

- Repository: <https://github.com/nickustinov/itsypin-macos>
- License: MIT
- Commit reviewed: [`2ee7bad7d941eb0e168884a6a7c0857245e3cb73`](https://github.com/nickustinov/itsypin-macos/commit/2ee7bad7d941eb0e168884a6a7c0857245e3cb73) (`main` at review time).
- Why it matters: This is the closest product and architectural analogue: a native macOS menu-bar app that hosts pinned websites in persistent `WKWebView` popovers or floating panels.
- Study: `AppDelegate.swift`, `WebViewController.swift`, and `BubbleWindow.swift` for retained WebKit ownership and floating-panel behavior.
- Decision: Notion PiP has one active page and retains one default-data-store `WKWebView` session for the app lifetime. Hiding, closing, reopening, and activating the same page retain that session; activating another page reuses the same web view. App quit intentionally ends the in-memory session.
- Explicit exclusions: Do not adopt `BubbleManager`, multi-site bubbles, mobile user agents, triple-tap shortcuts, or any auto-unload policy. These are outside Notion PiP's single-page product boundary and would undermine its retained editing session.
- Do not adopt wholesale: Itsypin is intentionally compact and concentrates several responsibilities in its app delegate. Keep Notion PiP's existing `App`, `Platform`, `Domain`, `Persistence`, and `Services` boundaries.

### Maccy

- Repository: <https://github.com/p0deje/Maccy>
- License: MIT
- Why it matters: A mature macOS utility with excellent keyboard-first interaction, a focused floating-panel implementation, searchable history, pinned content, and clear privacy controls.
- Study: `FloatingPanel.swift`, history models, shortcut handling, and the preferences flow.
- Adopt: A fast global shortcut, compact searchable history, deterministic ordering, pinned entries, and visible status/error feedback for capture delivery.
- Do not adopt wholesale: Its clipboard-specific data model, polling, and paste automation do not fit Notion PiP.

### Pindrop

- Repository: <https://github.com/watzon/pindrop>
- License: MIT
- Why it matters: A current, native macOS menu-bar application with a pragmatic modern project layout and a real release/test workflow.
- Study: `AppCoordinator.swift`, `Services/`, `Models/`, the separate unit/UI test plans, and release scripts.
- Adopt: Service wiring at the application boundary; protocol-backed engines; isolation of persistence, settings, hotkeys, and platform-specific work; and independent UI tests for permission-sensitive flows.
- Do not adopt wholesale: Its coordinator owns a much larger audio/transcription product surface. Keep Notion PiP's coordinator small and feature-specific.

### Helium

- Repository: <https://github.com/JadenGeller/Helium>
- License: MIT
- Status: Archived and unmaintained.
- Why it matters: A concise reference for an always-on-top browser panel, including AppKit window-level and Spaces behavior.
- Study: `HeliumWindow.swift` and `HeliumWindowController.swift`.
- Adopt: Evaluate its panel behavior as a reference when refining frame persistence, multi-Space visibility, and keyboard focus.
- Do not adopt wholesale: The code predates modern macOS conventions and is not a maintenance dependency. Treat it as a behavioral/design reference only.

### Ice

- Repository: <https://github.com/jordanbaird/Ice>
- License: GPL-3.0
- Why it matters: An actively developed, sophisticated menu-bar utility that handles hotkeys, settings, multi-display behavior, and macOS-version edge cases.
- Study: Its approach to menu-bar state, settings panes, panel presentation, and regression handling.
- Adopt: Product and test ideas only, especially around menu-bar visibility, Spaces, notches, displays, and shortcut conflicts.
- Do not copy code: GPL-3.0 is incompatible with incorporating source into a closed-source or permissively licensed Notion PiP without relicensing the combined work under GPL-compatible terms.

### NotionSwift

- Repository: <https://github.com/chojnac/NotionSwift>
- License: MIT
- Why it matters: An unofficial Swift client for the public Notion API that demonstrates request/response modeling.
- Constraints: It is marked work in progress and supports only internal-integration authorization.
- Recommendation: Do not make it a dependency. Keep the optional workspace-search API surface behind `NotionAPIClient` and model only the endpoints, auth modes, and error cases Notion PiP actually uses.

## Product direction for Notion PiP

1. Use Itsypin as the principal reference for persistent WebKit session and floating-panel behavior.
2. Use Maccy as the principal reference for quick capture and history interaction: one shortcut, immediate feedback, searchable recent work, and a clear retry path.
3. Keep native editor/capture state independent of the embedded Notion web session, so the app can recover from reloads, failed delivery, or authentication changes.
4. Use Pindrop's service/test separation as the ceiling for architectural complexity, not a reason to introduce a large global coordinator.
5. Treat Helium and Ice as behavioral research only; do not introduce their code or their licensing constraints into the app.

## License note

MIT references can be adapted when their license and copyright notice are retained where required. GPL-3.0 code must not be copied into this project unless the project is deliberately relicensed under GPL-compatible terms. In all cases, prefer independently written implementations shaped by the observed behavior.
