# Durable Pinned Page Design

## Goal

Persist the active Notion page across application termination. When Perch launches and a valid page was previously pinned, it automatically restores that page into the existing floating panel and shows the panel.

Durability applies to the canonical pinned page reference. The app does not attempt to serialize transient WebView state such as scroll position, history, or an in-progress navigation. The existing default WebKit data store continues to manage browser cookies and website data independently.

## Product Behavior

- Activating a page from URL entry, workspace search, the page picker, or an external URL route makes that page the durable selection.
- Replacing the active page replaces the durable selection.
- Quitting while the PiP is visible or hidden does not clear the durable selection.
- On the next launch, the app loads the durable selection and automatically shows the PiP panel.
- If no durable page exists, launch remains quiet and the menu-bar icon opens the setup/options surface as it does today.
- Hiding or closing the panel changes only its in-memory visibility. It does not clear persisted state.

## Persistence Model

Use the existing SwiftData `PinnedPageModel` and `PageRepository`. The stored value contains the stable page ID, canonical URL, display title, and the timestamp at which it became active.

The app has one current pinned page. `PageRepository` will expose focused operations for replacing and reading that current selection rather than requiring `AppRuntime` to interpret the full pinned-page collection. Replacing the selection inserts or updates the requested page and removes other `PinnedPageModel` rows in the same save. This gives the existing plural storage API explicit single-current-page semantics and prevents obsolete selections from accumulating or being restored unexpectedly.

The application composition root creates the persistent SwiftData container and injects a page repository into the runtime. Tests may inject an in-memory repository or a narrow test double. Persistence ownership remains outside the panel and WebView layers.

## Runtime Architecture

`AppRuntime` coordinates persistence because it already owns every page activation path and launch startup:

- `activate(page:source:)` continues to update the panel and observable runtime state immediately.
- It enqueues an asynchronous persistence write for the newly active page. Writes are serialized in activation order so an older page can never overwrite a newer selection on disk.
- A monotonically increasing activation generation prevents a late restore or preview completion from affecting current runtime state.
- `start()` launches a one-time pinned-page restore task alongside the existing personal-token bootstrap.
- Restore reconstructs a `NotionPageReference` from the stored canonical URL and routes it through a dedicated restore path that updates runtime state, loads the WebView, restores any cached native preview, and shows the panel without writing the same value back as a new activation.

`PinCoordinator` and `PiPPanelCoordinator` remain responsible only for current panel behavior. They receive a restored page through the same `pin(page:)` operation used for normal activation, so launch presentation uses the established show/replace path.

## Data Flow

```text
Page activation
      |
      +--> show or replace PiP immediately
      +--> update AppRuntime active state
      +--> PageRepository saves canonical page

Application launch
      |
      +--> PageRepository reads current saved page
             |
          found? ---- no ----> remain menu-bar-only
             |
            yes
             |
      validate Notion page reference
             |
      restore runtime state and show PiP
```

Persistence is deliberately not placed on the critical UI path. Showing or replacing the PiP does not wait for disk I/O.

## Startup Ordering and Races

Restore is asynchronous because `PageRepository` is actor-isolated. A page received through URL entry, the custom URL scheme, or another activation path while restore is pending must win over the stored page. The runtime records the activation generation before starting restore and applies the restored page only if no newer activation has occurred.

Persistence writes form a task chain: each activation's write waits for the prior write attempt to finish before saving. A failed write does not break the chain. This keeps disk state in the same order as user-visible activations without blocking the main actor or delaying panel presentation.

`start()` remains idempotent. It creates at most one restore task, and repeated calls do not reopen or retoggle the panel.

The restored page uses a distinct `.restored` activation source for observability and tests. Restore shows the panel exactly once; it must not pass through menu-bar toggle behavior, which could hide an already visible panel.

## Error Handling

- A persistence write failure is logged without removing or hiding the active in-memory PiP. The last successfully saved page remains the relaunch fallback.
- A store-open failure does not prevent the app, status item, or in-memory PiP from working. Durable restore and writes are unavailable for that run, and the failure is logged without exposing URLs.
- A missing saved page is normal and produces no error UI.
- An invalid or corrupt current-page URL is ignored safely. The app does not fall back to an older selection; it stays menu-bar-only and opens setup on the next regular status-icon click.
- A valid URL that fails WebView navigation is still the durable selection. Existing WebView retry and error behavior remains responsible for navigation failures.
- Persistence logs may include a stable page ID or error category, but not a full URL or Notion token.

## Testing

### Repository tests

- Saving a current page survives reopening the on-disk SwiftData store.
- Saving a replacement makes it the sole page returned for restoration and removes the prior selection.
- A failed save rolls back and leaves the previous durable page intact.
- Invalid stored URL data is rejected without returning an unusable page.

### Runtime tests

- Launch with a saved page restores runtime state, activates that page in the panel, and automatically shows the PiP.
- Launch without a saved page does not show an empty panel.
- A restored page is immediately available to the menu-bar and global-shortcut toggle paths.
- A direct activation that arrives while restore is pending wins and is not replaced by stale restored state.
- Normal activation persists the canonical page from every existing activation source.
- Persistence failure does not break or hide the active in-memory panel.
- Calling `start()` repeatedly performs restoration only once.
- Corrupt saved data leaves runtime state empty and setup remains reachable.

### Integration verification

1. Pin a Notion page and quit the app from both visible and hidden PiP states.
2. Relaunch and confirm the same canonical page appears automatically.
3. Change the pinned page, quit, and confirm only the replacement is restored.
4. Confirm Notion authentication continues to use the persistent default WebKit data store.
5. Confirm the menu-bar icon still toggles the restored panel without reloading it.

## Out of Scope

- Restoring exact WebView history, scroll position, form state, or unsaved edits after process termination.
- Persisting whether the PiP was visible or hidden at quit; a saved page always auto-shows at launch.
- Multiple simultaneous PiP panels.
- A page-history or recent-pages interface.
- Changing Notion authentication, cookies, cache policy, or token storage.
