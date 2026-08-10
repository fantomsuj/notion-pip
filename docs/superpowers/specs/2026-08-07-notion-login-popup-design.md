# Notion Login Popup Design

## Goal

Keep Notion's embedded page in place while allowing interactive Google, Apple, and SAML sign-in popups inside Perch. Prevent page-controlled HTTPS subframes such as `aif.notion.so` from opening blank tabs in the user's default browser.

## Observed Failure

The live failure has two independent frame-routing causes:

- The navigation delegate classifies an HTTPS analytics subframe at `aif.notion.so` as external and opens it through `NSWorkspace`, even though it belongs inside Notion's document.
- Notion's Google sign-in calls `window.open` with a trusted `app.notion.com` popup-check URL. The UI delegate returns no child WebView and loads that request into the main WebView, replacing the login page with a blank popup-check document.

Frame-level diagnostics confirmed the sequence: main-frame Notion load, external `aif.notion.so` subframe, then a trusted new-window request loaded as a new main document.

## Constraints

- Preserve Swift 6.2, macOS 14, the public API, signing, and entitlements.
- Keep the persistent default `WKWebsiteDataStore` so existing Notion sessions continue to work.
- Do not broaden which top-level links remain inside Perch.
- Do not hard-code Google as the only identity provider; Apple and arbitrary HTTPS SAML providers must be able to complete in the same popup.
- Use WebKit's supplied popup configuration so JavaScript opener relationships, cookies, process state, and callback behavior remain intact.
- Keep WebKit and AppKit ownership on `@MainActor` without unsafe concurrency escapes.
- Do not persist popup state. A popup is temporary and must be released when it closes or when the main session is torn down.

## Approaches Considered

### 1. Temporary in-app WebKit popup (selected)

Return a child `WKWebView` from `createWebViewWith` and host it in a temporary titled, closable window. This preserves WebKit's expected `window.open` and `window.opener` semantics and shares the main session's website data. The popup may follow HTTPS identity-provider redirects and closes when WebKit calls `webViewDidClose`.

### 2. Default-browser authentication

Open the popup request in the user's browser. This avoids another app window, but browser cookies are separate from the embedded WebView and the current app has no secure callback exchange that can transfer the resulting session.

### 3. Reuse the main WebView

Continue loading the popup request into the embedded page. This is the current behavior and is rejected because it destroys the opener page and leaves Notion's popup-check flow blank.

## Navigation Policy

Navigation decisions include frame context instead of only whether a target frame exists:

| Context | Trusted Notion HTTPS | Other HTTP(S) | Unsupported or credential-bearing URL |
|---|---|---|---|
| Main frame | Allow internally | Open externally and cancel | Cancel |
| Existing subframe | Allow internally | Allow internally | Cancel |
| New window | Create popup | Open externally | Ignore |

The existing main-frame trust boundary remains exact. Allowing ordinary HTTP(S) in an existing subframe does not grant it app privileges; it leaves page-owned iframe behavior to WebKit instead of promoting the navigation into a system-browser action.

## Components and Data Flow

`NotionWebNavigationPolicy` accepts an app-owned frame-context value and returns side-effect-free decisions. A trusted new-window request yields a popup decision rather than a request to replace the existing view.

`NotionWebPopupCoordinator` owns at most one temporary popup window and child WebView. It:

- creates the child with the exact `WKWebViewConfiguration` supplied by WebKit;
- presents a normal titled and closable AppKit window without changing the app's accessory activation policy;
- permits HTTP(S) redirects needed by identity providers while rejecting unsupported schemes;
- handles nested external new-window requests through the system browser rather than recursively creating windows;
- closes and releases the popup on `webViewDidClose`, window close, main-session teardown, or replacement by a newer trusted login popup.

`NotionWebSession` remains the owner and delegate of only the main embedded WebView. Its UI-delegate callback validates the initial new-window request through the navigation policy, then delegates popup construction to the coordinator. The main WebView is never loaded with the popup request.

## Error Handling and Lifecycle

- A popup navigation failure remains visible in the popup through WebKit's normal page behavior and does not change the main session state.
- Closing the popup manually cancels only the login attempt.
- Losing the main WebView closes any popup so it cannot outlive its opener session.
- A popup request with an unsupported initial URL is ignored; an external initial URL keeps the existing open-in-browser behavior.
- No URL paths, query strings, cookies, or credentials are logged.

## Testing

Add regression coverage that proves:

- an external HTTPS subframe is allowed without calling `openURL`;
- an external top-level navigation still opens exactly once in the system browser;
- a trusted new-window request returns a popup decision and never invokes the main WebView loader;
- an external or unsupported new-window request retains existing behavior;
- the popup coordinator uses the supplied configuration and hosts a distinct WebView;
- the popup permits HTTPS identity-provider redirects and rejects unsupported schemes;
- WebKit close and AppKit window close both release the popup;
- replacing or tearing down the main session closes the popup;
- the original embedded WebView identity and URL are preserved while the popup is active.

Run focused navigation and popup tests through the red-green cycle, then run the complete suite with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Finally stage and launch the app with `./script/build_and_run.sh --verify`, reproduce the saved Notion URL flow, verify that no `aif.notion.so` browser tab opens, and confirm that Google sign-in presents an interactive temporary in-app window. Credential entry remains with the user.
