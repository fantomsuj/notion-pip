# Native Notion Navigation and Legacy Feature Removal Design

> **Superseded scope:** The approved implementation removes Quick Capture's UI,
> runtime, and delivery machinery while retaining the existing page-management
> features and personal-token search. Legacy capture data remains inert in the
> migrated store so upgrading cannot silently destroy user-authored drafts.

## Goal

Make Notion PiP a focused shell around Notion's native information architecture. Remove the personal-token connection, Quick Capture, delivery, and app-owned page-management systems. Users organize and find pages with Notion Home, Favorites, Recents, Search, Teamspaces, and the native new-page flow. Quick Copy remains as the sole capture helper.

## Decisions

- Remove personal integration tokens and all Notion REST API access.
- Remove Quick Capture, including its local editor, shortcut, drafts, destinations, delivery history, retries, recovery UI, generated web assets, and JavaScript toolchain.
- Remove app-owned pinned, recent, active-page, page-switcher, and durable page-restoration concepts.
- Delete all legacy Quick Capture and page-management data during upgrade. Do not export or retain it.
- Preserve Quick Copy and its saved-cursor insertion behavior.
- Open Notion Home on every cold launch and after unrecoverable WebView state loss.
- Use native Notion navigation for Favorites, Recents, Search, Teamspaces, and page selection.
- Add Home and New Page commands to the PiP toolbar. Map `Command-N` to New Page.
- Keep external Notion URL handoffs as transient navigation commands without persisting them.
- Retain stable local code signing because it also stabilizes macOS Accessibility and login-item identity across development rebuilds.

## Research and Experiments

Official Notion documentation establishes that its Home/sidebar already provides Favorites, Recents, Search, Teamspaces, shared/private pages, and new-page entry points. Users can customize section visibility and order, and the desktop app supports `Command-N` for page creation. Notion also documents a preference for opening links in its desktop app.

Primary references:

- <https://www.notion.com/help/navigate-with-the-sidebar>
- <https://www.notion.com/help/manage-your-library>
- <https://www.notion.com/help/notion-for-desktop>
- <https://www.notion.com/help/create-your-first-page>

The following local experiments informed this design:

- Thirty-one focused token, lifecycle, and delivery tests passed. They confirmed that the current token is a prerequisite for workspace search, destination search, enqueueing, and delivery.
- Seventy-five focused WebKit session tests passed, confirming that live navigation, SPA URL observation, renderer recovery, cursor insertion, and persistent website data are independently healthy.
- Twenty navigation-policy tests passed, confirming that exact trusted Notion HTTPS hosts can carry non-page routes such as Home and page-creation intermediates while external and unsupported URLs remain isolated.
- A SwiftData lightweight-migration experiment removed one model while preserving an unrelated model's data.
- A second SwiftData experiment migrated a populated versioned schema to an empty schema successfully.
- A metadata-only Keychain lookup confirmed that a legacy personal-token item currently exists and therefore needs explicit cleanup.

## Product Principles

- Notion owns Notion organization. The PiP must not maintain a parallel page hierarchy or activity history.
- The PiP remains focused. Native navigation is available on demand through Home rather than through an always-visible custom or native sidebar.
- Account state stays in Notion. The app does not infer, mirror, or modify Favorites, Recents, workspace structure, or account preferences.
- Navigation is transient unless Notion itself persists it in website data. A fresh app launch begins at Home.
- Quick Copy is an explicit, user-controlled assistive action. It does not become a generalized automation layer.
- Legacy deletion is exact and idempotent. It must not remove WebKit cookies, website storage, Accessibility permission, menu-bar state, panel sizing, or Launch at Login registration.
- Components have narrow responsibilities and communicate through small interfaces.

## User Experience

### Cold launch and navigation

On cold launch, the app creates its persistent Notion WebView and loads Notion Home. If the user is signed out, Notion's own sign-in experience appears. Once signed in, the user can use native Home sections, Search, and workspace navigation to select a page.

Selecting a Notion page uses normal WebView navigation. The PiP does not publish the page into an application runtime model, add it to a custom recent list, or persist it as an active page. During the current process lifetime, the live WebView naturally remains on the selected page. Hiding and showing the panel preserves the existing warm-WebView behavior.

When the warm WebView is evicted, its renderer terminates without a recoverable trusted URL, or the app starts a new process, the safe fallback is Notion Home.

### Toolbar and commands

The top controls contain:

- **Home:** Navigate the current WebView to Notion Home.
- **New Page:** Start Notion's native new-page flow. Disable or deduplicate repeated activation until navigation succeeds or fails.
- **Reload:** Reload the current WebView document.
- **Open in Notion:** Open the current trusted HTTPS URL through `NSWorkspace`; the operating system and the user's Notion preference decide whether it opens in the desktop app or a browser.
- **Application menu:** Retain Settings, Getting Started, and Quit.
- **Stash:** Retain the existing edge-stashing behavior.

Remove the custom page switcher and re-pin controls. Replace the existing Quick Capture plus action and `Command-N` command with New Page.

### Quick Copy

Retain the explicit Quick Copy control and cursor-adjacent paste control. Quick Copy may insert only into the current trusted Notion document after a user-visible selection/cursor capture.

The saved cursor is scoped to a transient document generation rather than a persisted page ID. Any navigation, reload, renderer replacement, popup handoff, or WebView replacement invalidates the saved cursor before late callbacks can act.

Remove Quick Capture clipboard-prefill and insert-at-cursor preferences. They belong to the removed Quick Capture shortcut and must not be confused with Quick Copy.

### External handoffs

Retain the existing URL handoff entry point for exact trusted Notion HTTPS URLs. A valid handoff navigates the current WebView and shows the panel. It does not create a pin, recent item, active-page record, or restoration record.

Reject credential-bearing URLs, lookalike hosts, unsupported schemes, malformed URLs, and untrusted web destinations using the existing navigation security boundary.

### Onboarding and Settings guidance

Replace pinning and Quick Capture onboarding with a reusable **Set up Notion for PiP** guidance component:

1. Favorite frequently used pages with Notion's page-level star.
2. Keep Favorites and Recents visible near the top of Notion Home.
3. Use native Search for everything else.
4. Optionally enable Notion's **Open links in desktop app** preference.

The component provides **Open Notion Home**, **Learn about Notion navigation**, and the enclosing flow's normal Continue action. It does not attempt to inspect whether the user followed the recommendations.

Settings reuse a compact version under **Notion Navigation**. Remove these sections and controls:

- Pinned Page and workspace API search
- Quick Capture Destination
- Trusted Quick Capture and its shortcut
- Personal Notion Access
- Capture outbox and delivery status

Retain panel sizes, the single panel shortcut, Quick Copy explanation, menu-bar visibility, Launch at Login, service health for remaining services, and About.

### Upgrade disclosure

After successful legacy cleanup, show one nonblocking, one-time notice:

> Quick Capture and custom page lists were removed. Use Notion Home, Favorites, Recents, Search, and New Page instead. Previous local Quick Capture data was deleted.

The notice must not imply that Notion-hosted pages or account data were deleted.

## Architecture

### `NotionRoute`

`NotionRoute` is a small value type representing a trusted navigation destination. It supports:

- Home
- Native new-page entry
- A validated exact Notion HTTPS URL supplied by a handoff or the current WebView

It contains URL construction and trust validation but no WebKit or application state. Route validation reuses the exact-host security policy rather than duplicating host lists.

### `NotionWebNavigator`

`NotionWebNavigator` owns navigation commands and transient document identity. Its public operations are conceptually:

- `goHome()`
- `createPage()`
- `navigate(to:)`
- `reload()`
- `openCurrentURL()`

It records only the current trusted URL and a monotonically advancing document generation. It receives request-loading and external-opening closures so route and command behavior can be tested without live network access.

The navigator does not own WebView lifecycle, persistence, popup presentation, or Quick Copy.

### `NotionWebSession`

`NotionWebSession` owns:

- Persistent `WKWebsiteDataStore` and WebView construction
- Visible, hidden, suspended, offline, failed, and renderer-recovery lifecycle
- Navigation policy and trusted popup coordination
- Native editor activity and caret bridges
- Quick Copy selection capture and insertion
- Warm retention and memory-pressure eviction

It composes a `NotionWebNavigator`. It no longer depends on `NotionPageReference`, `NotionPageStateRestorationCoordinator`, page IDs, app repositories, or runtime callbacks that publish resolved pages.

Renderer recovery reloads the current trusted URL once. If the URL is unavailable or recovery fails, the session navigates Home. Scroll and DOM-selection restoration across eviction are removed; Notion owns durable navigation and the live WebView owns in-process interaction state.

### Quick Copy boundary

`QuickCopyController` retains its insertion-target protocol. The target operates on a document-generation token rather than a page ID. The WebSession invalidates the token synchronously before starting any navigation or WebView replacement.

This keeps Quick Copy independently testable and prevents page-management concepts from leaking back into the runtime.

### `AppRuntime`

`AppRuntime` coordinates:

- One global panel shortcut
- Panel show/hide/stash behavior
- Menu-bar state
- Panel sizing and hold-to-peek
- Settings presentation
- Navigation commands forwarded to the WebSession
- Remaining service-health state

It does not own page references, search results, capture records, connection state, delivery state, or persistent repositories.

Composition no longer constructs `PageRepository`, `CaptureRepository`, `QuickCaptureDestinationRepository`, `DeliveryEngine`, `DeliveryScheduler`, `NotionAPIClient`, `PersonalTokenCredentialVault`, a Quick Capture presenter, or editor termination participants.

### `NotionSetupGuidance`

The guidance component separates content from presentation. A small immutable content model owns the recommendation text and official help URLs. Onboarding and Settings views render the model at their appropriate density and receive Home/help actions through closures.

This prevents duplicate copy and keeps account recommendations independent of WebKit internals.

### `LegacyStateRemoval`

Legacy cleanup is isolated behind an idempotent `LegacyStateRemoving` interface. The concrete implementation owns three collaborators:

- A SwiftData legacy-store migrator
- A Keychain item deleter
- A preference-key remover

Normal runtime components never reference historical models, token service names, or removed preference keys.

## Data and State Removal

### SwiftData

Introduce `NotionPiPSchemaV5` with an empty model list and a lightweight V4-to-V5 migration stage. V1 through V4 schemas remain frozen in a migration-only source file so users can upgrade directly from any supported historical store.

Opening the V5 container performs structural deletion of:

- Capture drafts
- Capture delivery records and journals
- Quick Capture destination settings
- Pinned pages and roles
- Recent pages
- Active-page state
- Per-page durable restoration state

After successful migration, the normal app does not retain or use the container. A completion preference prevents unnecessary migration setup on later launches.

If migration fails, do not delete broad Application Support directories or reset WebKit. Report a generic cleanup issue, keep retrying the exact migration on later launches, and allow the live Notion shell to run.

### Keychain

Delete the exact service/account pair used for the personal token from both the data-protection and legacy Keychains. Never read or log the token. Treat item-not-found as success.

Unexpected deletion errors keep cleanup incomplete, produce a non-secret status-code diagnostic, and expose the same generic cleanup retry action.

### Preferences

Delete only explicitly enumerated removed keys, including:

- Quick Capture shortcut
- Quick Capture clipboard prefill
- Quick Capture cursor insertion
- Legacy cleanup/cache flags tied only to capture or custom page state
- Any custom page-selection preferences outside SwiftData

Preserve panel shortcut, panel sizes, hold-to-peek, menu-bar visibility, Launch at Login, onboarding completion unless the revised onboarding version intentionally advances, and every Quick Copy-specific preference.

### WebKit and system state

Do not delete or recreate:

- `WKWebsiteDataStore.default()` contents
- Notion cookies, local storage, IndexedDB, or service-worker data
- Accessibility permission
- Login-item registration
- Window/panel geometry
- Code-signing identities

## Removed Subsystems

The implementation removes the following product subsystems rather than leaving dormant adapters:

- Personal-token domain validation and Keychain vault
- Notion REST API request/response client and DTOs
- Workspace and destination search controllers/views
- Capture page API adapter and block delivery service
- Delivery engine, scheduler, retry policy, journals, and retention
- Capture repositories, models, ports, exports, and outbox UI
- Quick Capture lifecycle, window, editor session, bridge, conflict resolution, and generated web resources
- Quick Capture JavaScript package, tests, build steps, and CI job
- Quick Capture shortcut registration and preferences
- Pin coordinator and page URL input
- Page working-set policy, roles, matcher, switcher controller/view, and repositories
- Per-page WebKit restoration coordinator and persistence callbacks
- Runtime page activation, pin persistence, and page search facades

Shared utilities may remain only when another retained feature has a direct call site. The implementation must verify each candidate with repository-wide reference searches before deletion.

## Data Flow

### Startup

1. Start idempotent legacy cleanup without reading user content.
2. Construct the WebSession and navigator independently of cleanup success.
3. Register the single panel shortcut and remaining lifecycle observers.
4. Load Notion Home.
5. If cleanup completes for the first time, publish the one-time removal notice.

### Native page selection

1. The user chooses a Favorite, Recent, Search result, teamspace page, or other native Notion link.
2. Navigation policy validates the destination.
3. The WebSession invalidates the prior document generation and Quick Copy cursor.
4. The navigator loads the trusted request.
5. The current trusted URL updates after navigation without leaving the WebSession.

### New Page

1. The user clicks New Page or presses `Command-N`.
2. The navigator ignores duplicate starts while creation navigation is pending.
3. The WebSession loads Notion's native new-page entry route.
4. Notion chooses the workspace location and presents its normal editor.
5. The resulting URL becomes the current transient trusted URL.

### Quick Copy

1. The user explicitly enables the visible Quick Copy control and selects text in another application.
2. The WebSession captures a cursor snapshot associated with the current document generation.
3. The controller submits selected text through the insertion-target protocol.
4. The WebSession inserts only if the WebView, document generation, trusted URL, and cursor snapshot still match.
5. Navigation or replacement invalidates pending work before it can insert into another document.

## Failure Handling

- **Offline:** Show that Notion requires a connection and offer Retry. Do not offer an offline local note.
- **Initial Home failure:** Offer Retry; repeated failure remains generic and does not expose WebKit error text.
- **Page failure:** Offer Retry and Home.
- **New Page failure:** Clear the deduplication guard and offer Retry or Home.
- **Renderer termination:** Attempt one current-URL reload, then fall back to Home.
- **Invalid handoff:** Reject it without changing the current document.
- **External main-frame URL:** Open it externally and preserve the current Notion document.
- **Cleanup failure:** Keep the shell usable, log only operation and status category, show a generic cleanup issue, and retry only on explicit Retry or the next launch.
- **Quick Copy invalidation:** Fail closed without changing the clipboard or inserting text into a new document.

## Testing Strategy

### Route and navigator tests

- Home and native new-page routes use exact trusted HTTPS hosts.
- Handoff routes reject credentials, lookalikes, unsupported schemes, fragments or fields disallowed by the handoff contract, and malformed values.
- Home, New Page, reload, and external open invoke exactly one injected operation.
- Repeated New Page activation is deduplicated until success or failure.
- Every document-changing operation advances the generation before loading.

### WebSession tests

- Cold start creates one WebView and loads Home.
- Native non-page and page routes remain in the same session.
- Hide/show retains a warm WebView without app-owned restoration.
- Eviction and unrecoverable renderer termination fall back to Home.
- External and popup routing retain the existing trust boundary.
- The current trusted URL drives Reload and Open in Notion.
- Navigation invalidates current and pending Quick Copy cursor state.
- Late callbacks from an old generation cannot insert or replace current state.

### Cleanup and migration tests

- A populated V1, V2, V3, and V4 store migrates to empty V5.
- Migration leaves no legacy entities and does not touch an independently created WebKit data directory.
- Keychain cleanup deletes both query variants without performing a copy/read.
- Item-not-found is idempotent success; unexpected statuses remain retryable failures.
- Preference cleanup removes only the enumerated keys.
- Cleanup completion is recorded only after all collaborators succeed.
- A partial failure retries safely without recreating deleted state.

### Composition and view tests

- App composition constructs no persistence repository, API client, credential vault, delivery scheduler, or Quick Capture presenter.
- The command model contains Home, New Page, Settings, Getting Started, and Quit with stable keyboard behavior.
- PiP chrome exposes accessible Home, New Page, Reload, Open in Notion, menu, and stash actions.
- Page switcher, re-pin, Quick Capture, offline-note, token, destination, and outbox controls are absent.
- Onboarding and Settings render the shared setup guidance with working Home and official-help actions.
- Remaining panel, menu-bar, Launch at Login, shortcut recovery, popup login, and Quick Copy tests stay green.

### Manual authenticated validation

- Sign in through the embedded Notion UI without entering a token.
- Open Home and navigate through Favorites, Recents, Search, Teamspaces, Shared, and Private pages.
- Create and edit a page through New Page and `Command-N`.
- Hide, show, stash, reload, and open the current page externally.
- Confirm native Notion account organization changes made in the desktop app appear in the embedded Home experience.
- Confirm a fresh launch starts at Home while preserving Notion authentication.
- Confirm Quick Copy inserts at the intended cursor and fails closed after navigation.
- Confirm the upgrade removes old local models, preferences, and Keychain entries while leaving Notion authentication intact.
- Exercise offline, failed navigation, renderer termination, popup login, VoiceOver, keyboard access, and reduced motion.

### Required commands

Run focused tests throughout implementation, followed by:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./script/build_and_run.sh --verify
```

Only run the build-and-launch script after confirming that no active NotionPiP process contains unsaved work, because the script terminates the running process.

## Documentation Changes

Update README, AGENTS, onboarding copy, handoff documentation, architecture maps, course material, file atlas, glossary, manual test matrix, and open-source research where they describe removed features.

Historical specifications and plans remain historical records. Add a short supersession note when an older document otherwise appears to describe the current product. Do not rewrite committed history to pretend the removed architecture never existed.

Remove instructions that ask users to create or paste personal tokens. Replace custom page-organization guidance with the native Notion recommendations and official documentation links above.

## Success Criteria

- The application never asks for, stores, reads, validates, or sends a personal integration token.
- No Notion REST API request path remains in the shipping target.
- No Quick Capture UI, shortcut, editor asset, model, queue, delivery, recovery, or status surface remains.
- No app-owned pinned, recent, active-page, page-switcher, or durable page-restoration feature remains.
- Cold launch and unrecoverable navigation state lead to Notion Home.
- Home, New Page, Search, Favorites, Recents, and workspace navigation are provided by Notion's live UI.
- Quick Copy remains explicit, functional, and scoped to the current document generation.
- V1 through V4 users can upgrade without retaining legacy app data or losing Notion website authentication.
- The app preserves its always-on-screen panel, stashing, shortcut, menu-bar, sizing, popup login, and Launch at Login behavior.
- Automated and manual validation pass without requiring Node.js, a Notion API token, or a signing certificate.

## Scope Boundaries

This removal does not:

- Build OAuth or any replacement API integration.
- Recreate Favorites, Recents, Search, templates, databases, or teamspaces outside Notion.
- Automate Notion account settings or inspect whether recommendations were followed.
- Add local/offline note editing or delivery.
- Add a custom persistent last-page preference.
- Delete Notion-hosted pages, account data, WebKit website data, system permissions, or login-item registration.
- Change the intentional always-on-screen, all-Spaces panel behavior.
