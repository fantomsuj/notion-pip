# One-Click New Notion Page Design

## Goal

Add a toolbar button to the Notion picture-in-picture panel that starts a new Notion page with one click. The flow must use the user's existing embedded Notion session, require no personal integration token, and leave the newly created page as the PiP's active pinned page.

## User Experience

- Add a plain `plus` symbol button immediately before Reload in the PiP toolbar.
- Give the control the accessibility label `Create New Notion Page` and help text `Create a new page in Notion`.
- Clicking the button navigates the existing embedded web view to Notion's new-page route.
- Reuse the existing loading indicator while Notion creates and opens the page.
- Ignore repeat clicks while the creation navigation is starting.
- When Notion resolves to the new page's canonical URL, adopt that page throughout the app. Reload, Open in Browser, panel restore, and future launches then refer to the new page.
- If creation navigation fails, keep the last valid pinned page as the app-level fallback and show the PiP's existing generic load failure with Retry.

No title or destination prompt is added in this slice. Notion owns the new page's default workspace location and its native editing experience.

## Architecture

### Creation route

`NotionWebSession` owns new-page navigation because it already owns the `WKWebView` and navigation state. It exposes a creation action that loads a fixed HTTPS Notion new-page URL and guards against duplicate starts.

### Page adoption

After navigation finishes, `NotionWebSession` validates the final web-view URL as a `NotionPageReference`. A callback reports newly resolved page references to the application layer. The callback does not fire for the page that was explicitly activated, avoiding feedback loops.

`AppRuntime` receives the resolved page and activates it through the existing pinning path. This keeps `PinCoordinator`, the panel coordinator, native preview loading, and durable pinned-page persistence consistent. Re-activating the page in the web session is harmless because `NotionWebSession.activate` already deduplicates the same page ID.

The creation button uses an application command rather than reaching around the runtime. `AppCommandModel` gains a new-page command alongside Quick Capture, and `PiPChromeView` renders that command as the dedicated toolbar button. The command remains available without a Notion API connection because it relies on the embedded login session.

## State and Failure Handling

- Creation sets the web session to loading immediately.
- A small internal flag suppresses repeated creation requests until navigation succeeds or fails.
- A final URL that is not yet a canonical Notion page is not adopted; Notion may use intermediate redirects.
- Successful parsing clears the creation flag and reports the page.
- Navigation failure clears the flag and uses the existing failure state. The previous app-level pinned page is retained so hiding and reopening the PiP can recover it.
- If the embedded web session is signed out, Notion's own sign-in UI appears. The app does not misrepresent that as an API-token problem.

## Testing

- Verify the command model exposes and performs the new-page action.
- Verify the PiP chrome publishes stable accessibility copy for the button.
- Verify one creation request loads the fixed new-page route and repeated starts are deduplicated.
- Verify a completed canonical page navigation reports the new page once.
- Verify intermediate or invalid Notion URLs are not adopted.
- Verify navigation failure clears the creation guard and retains the existing generic failure behavior.
- Run the focused Swift tests, then the full package test suite.

## Scope Boundaries

This change does not add title entry, template selection, parent-page selection, API-based page creation, or a setting for the default destination. Those can be layered on later if users need more control than Notion's native new-page behavior.
