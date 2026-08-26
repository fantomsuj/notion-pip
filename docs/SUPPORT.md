# Perch Support

Use [GitHub Issues](https://github.com/fantomsuj/notion-pip/issues/new) for support and feedback. Include the Perch version and build shown in Settings → About, the macOS version, what you expected, and what happened. Never attach a Notion password, session cookie, integration token, private page content, signing credential, or notarization credential.

## Install a beta

Only install a Developer ID-signed, notarized Perch disk image supplied through the project's GitHub Releases page.

1. Download the Perch DMG and open it.
2. Drag Perch to Applications.
3. Eject the disk image, then open Perch from Applications.
4. Confirm macOS identifies the verified developer without asking for a Security Settings override.
5. Look for Perch in the menu bar; it intentionally does not appear in the Dock.

Do not distribute a local `dist/Perch.app` build to another Mac. Local builds may be ad-hoc signed and are not a substitute for a notarized beta.

## Common recovery steps

- **Perch launched but seems absent:** Look for the Perch menu-bar icon. If it is hidden, use the configured shortcut or the panel's edge handle.
- **Notion needs authentication:** Start sign-in from the embedded Notion interface. If Perch shows Continue in Browser, finish through the secure system-browser session and return to Perch. Perch support will never ask for your password or session cookie.
- **Launch at Login needs approval:** Open Settings → Launch at Login, follow the button to System Settings → General → Login Items & Extensions, approve Perch, then return to the app.
- **Accessibility permission appears:** Perch requests Accessibility access only after you enable Context Suggestions in Settings. Grant it under System Settings → Privacy & Security → Accessibility if you want saved-page suggestions and reveal-time exact-page connection. Leave the feature off if you do not want Perch to inspect this narrow app/window metadata.
- **A focused Notion page is not detected:** Confirm Context Suggestions is enabled and Settings reports permission as ready. Then focus the page in Safari, Chrome, Firefox, Edge, Brave, Arc, or the native Notion app before revealing Perch. The source app must expose a focused `AXDocument` or `AXURL`; private windows, browser builds with different bundle identifiers, inaccessible views, malformed links, slow Accessibility responses, and workspace/search URLs without a page ID quietly use Perch's ordinary reveal behavior.
- **Perch already shows another page:** Reveal remains immediate and never replaces that page automatically. Use the slim **Open Here** action inside Perch to switch, or dismiss it. Selecting a pinned or recent page explicitly always wins over an outstanding contextual result.

## Local agents

Local agent streaming is opt-in under Settings → Local Agents. Agents stream Markdown into an overlay; they do not write to Notion until you click a location and press **Accept**. Full protocol details live in [AGENT_STREAMING.md](AGENT_STREAMING.md).

- **Agent cannot find Perch:** Confirm Perch is running and **Allow local agents** is on. Status should read Ready and the discovery file should exist at `~/Library/Application Support/com.fantomsuj.Perch/agent-server.json`. If the setting was just enabled, wait for Ready or press Retry. A missing file usually means the listener is off or still starting.
- **`401 unauthorized` or stale discovery:** Quit and reopen Perch, or toggle Allow local agents off and on, so the token rotates and the discovery file is rewritten. Agents must reread the file; never paste bearer tokens into chat or issues.
- **`409 stream_active`:** Another local agent already occupies the single stream slot. Stop or cancel that stream from the overlay, or wait until it is dismissed, then retry.
- **Stream finished but Notion did not change:** Expected for `accept_to_paste`. Click in the Notion page where the note should go, then press **Accept** on the overlay or notification. Accept without a live editor cursor keeps the Markdown and asks you to click first.
- **Paste failed after Accept:** Stay on an editable Notion page, click the destination again, and Accept once more, or Copy and paste manually. Reloading the page or switching pages before Accept can invalidate the target.
- **Revoke access:** Turn off **Allow local agents**. The listener stops and the matching discovery file is removed. Installed skills under `~/.claude/skills/stream-to-perch/`, `~/.codex/skills/stream-to-perch/`, or `~/.cursor/skills/stream-to-perch/` can be deleted separately if you no longer want that instruction file.

## Local storage recovery

If Perch cannot open or migrate its local SwiftData store, it opens a normal recovery window before onboarding or Settings. Your Notion pages, account, sign-in, and embedded website data are unaffected. The failure concerns only Perch's device-local page history, pin roles, and restoration state.

- **Reveal Store in Finder** selects `Perch.store` when it exists, or the containing `~/Library/Application Support/com.fantomsuj.Perch` folder when it does not.
- **Continue Without Saving** keeps the current app process running with local page-history persistence disabled. Notion remains usable, but visits, pins, roles, and restoration changes from that session are not saved. Settings keeps a Service Health warning whose **Review Recovery Options** button reopens the recovery window.
- **Archive Store and Quit…** asks for confirmation, moves the existing store artifacts into a new collision-free folder under `~/Library/Application Support/com.fantomsuj.Perch/Recovery/Perch-store-<UTC timestamp>/`, and then quits normally. Reopening Perch creates an empty local store through its ordinary startup path.

Only these artifacts are eligible for an archive:

- `Perch.store`
- `Perch.store-wal`
- `Perch.store-shm`
- `Perch.store-journal`
- `Perch.store_SUPPORT`

Perch never archives `instance.lock`, Preferences, WebKit website data, Notion cookies, or other files. It never deletes or overwrites a store artifact. If a move fails, Perch attempts to return every artifact already moved and reports any artifact that could not be returned. Leave both the original and Recovery locations unchanged if that happens, use **Reveal Store in Finder**, and include only filenames and the displayed error when filing a support issue. Store archives can contain private Notion page URLs and titles, so do not attach them publicly.

Archived stores remain on the Mac until the user deliberately moves or deletes them. They are preserved for a future recovery tool; Perch 0.1 does not import or export individual records from an archived store.

### Safe developer corruption simulation

Never corrupt, rename, move, or replace the real `~/Library/Application Support/com.fantomsuj.Perch` directory for a test. The focused simulation creates an invalid store path only inside a unique temporary directory and removes that fixture afterward:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter PersistenceBootstrapTests.testTemporaryDirectoryStoreOpenFailureEntersRecoveryWithoutTouchingRealStore
```

Run the archive transaction suite separately to exercise successful moves, collisions, rollback at the first/middle/final move, and incomplete rollback without touching user data:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter PersistentStoreArchiveServiceTests
```

## Uninstall Perch and remove local data

1. In Perch Settings, turn off Launch at Login.
2. Quit Perch from its menu-bar or application menu.
3. Move `/Applications/Perch.app` to the Trash.
4. In System Settings → Privacy & Security → Accessibility, remove Perch if you previously enabled Context Suggestions.
5. To remove local page history, restoration state, preferences, and embedded website data, delete Perch's containers from the current user's `~/Library/Application Support`, `~/Library/Preferences`, and `~/Library/WebKit` folders. Search for `Perch` or `com.fantomsuj.Perch` and verify each exact target before deleting it.
6. In System Settings → General → Login Items & Extensions, remove a stale Perch entry if macOS still shows one.

Deleting local data signs the embedded browser out and removes Perch's device-local history and layout. It does not delete pages or account data stored by Notion.
