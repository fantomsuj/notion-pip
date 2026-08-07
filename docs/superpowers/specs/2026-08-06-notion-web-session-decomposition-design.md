# Notion Web Session Decomposition Design

## Goal

Reduce `NotionWebSession` to the main-actor owner and WebKit delegate adapter for one live `WKWebView`, while extracting only responsibilities that gain a narrow compiler-visible contract and direct deterministic tests.

## Constraints

- Preserve Swift 6.2, macOS 14, signing, entitlements, and the existing internal/public API surface unless a test-only entry point moves to its collaborator.
- `NotionWebSession` remains the sole owner of the live `WKWebView` and remains its `WKNavigationDelegate` and `WKUIDelegate`.
- Preserve the default persistent `WKWebsiteDataStore`, signed-in Notion continuity, exact URL trust rules, external routing, one-WebView identity, retained selection, scroll fallback, reload and re-pin behavior, renderer recovery, and failure banners.
- Keep WebKit and UI work on `@MainActor`. Do not add detached tasks, unsafe isolation, or unchecked sendability.
- Preserve callback ordering and reject stale WebView callbacks by identity plus a monotonically increasing generation.

## Collaborators

### `NotionWebNavigationPolicy`

A Foundation-only value type classifies top-frame navigation, new-window requests, and navigation failures. It returns app-owned decisions instead of performing side effects or exposing WebKit delegate types. `NotionWebSession` adapts those decisions to `WKNavigationActionPolicy`, `loadRequest`, and `openURL` in the same callback where those effects occur today.

The policy preserves these rules:

- A missing target frame is allowed so the `WKUIDelegate` handles the new-window request exactly once.
- Exact trusted HTTPS Notion hosts stay in the existing view.
- Supported external HTTP(S) URLs open through the system and cancel internal navigation.
- Unsupported or credential-bearing URLs cancel or are ignored.
- Cancellation failures do not publish a banner; recognized network errors publish `.offline`; other failures publish the existing generic message.

### `NotionPageStateRestorationCoordinator`

An `@MainActor` coordinator owns only page continuity records: the bounded opaque interaction-state cache, validated durable restorations, latest strict scroll snapshots, saved URL provenance, the pending scroll fallback, and the one-shot durable-fallback flag. It never retains or calls a `WKWebView`.

Inputs are page IDs, validated page values, URLs, scroll snapshots, and opaque interaction-state values supplied by `NotionWebSession`. Outputs are explicit restoration plans: apply a one-shot interaction state or load a selected URL with a durable-attempt flag. Capture takes an injected timestamp so direct tests are deterministic. Reload, page replacement, renderer termination, successful finish, and failed durable navigation each have explicit mutation methods.

### `NotionWebScriptMessageCoordinator`

An `@MainActor` coordinator owns activity, scroll, and caret user scripts plus their weak WebKit message handlers. Installation returns a monotonically increasing generation captured by every handler and the URL observation. Removal clears weak forwarding, removes scripts and handlers through the existing injectable remover, and advances the generation so late messages are stale.

The coordinator forwards validated values, source WebView identity, and generation to `NotionWebSession`. The session remains responsible for deciding whether the message belongs to its current WebView and for publishing UI/lifecycle state.

## Session Responsibilities After Extraction

`NotionWebSession` continues to:

- create, configure, attach, detach, retire, and replace the single live `WKWebView`;
- adapt `WKNavigationDelegate` and `WKUIDelegate` callbacks in their existing order;
- coordinate `NotionWebLifecycleController` commands and performance signposts;
- own retained editor selection and Quick Copy insertion because those operations depend on current live DOM identity and attachment timing;
- call the restoration coordinator before and after WebKit operations without transferring WebView ownership;
- reject stale URL observations, delegate callbacks, and script messages using WebView identity and script-coordinator generation.

## Testing

- Add direct navigation-policy tests for trusted, external, unsupported, new-window, cancellation, offline, and generic-failure decisions.
- Add direct restoration-coordinator tests for bounded LRU behavior, interaction-state one-shot restoration, saved URL provenance, scroll fallback, canonical retry exactly once, and reset on renderer termination/re-pin.
- Add direct script-coordinator tests for monotonic installation/removal generations and installed bridge shape.
- Retain session integration tests for WebKit delegate ordering, one-WebView identity, URL observation, selection restoration, scroll application, external effects, failure banners, reload/re-pin, and renderer recovery.
- Run the timing-sensitive `NotionWebSessionTests`, `NotionEditorSelectionTests`, `NotionEditorCaretBridgeTests`, and `WebNavigationDestinationTests` repeatedly before the full Swift suite.
