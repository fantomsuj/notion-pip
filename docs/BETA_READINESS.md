# External Beta Readiness

This checklist defines the minimum bar for giving Perch 0.1 to people outside the development team. It intentionally separates repository readiness from Developer ID signing and notarization, which belong in the distribution PR.

## Release gate

- [ ] CI passes for the Swift test suite.
- [ ] `Support/Version.env` contains the intended user-facing version and a new build number.
- [ ] The ten critical manual tests below pass on a clean macOS 14+ user account.
- [ ] The app has a final icon, support URL, privacy policy, and installation instructions.
- [ ] A Developer ID-signed, hardened-runtime, notarized DMG installs on a Mac that did not build the app.
- [ ] Launch at Login is enabled, approved when required, exercised across a
  real login, disabled again, and checked after relaunch using that distributed
  archive.
- [ ] No test account, Notion token, session cookie, signing credential, or notarization credential is committed.
- [ ] Upgrading deletes the retired personal-token Keychain item without reading it and leaves the embedded Notion session intact.
- [ ] Five to ten testers have an owner, contact method, and feedback deadline.
- [ ] Known limitations and recovery steps are included with the beta.
- [ ] Context Suggestions remains off by default; its permission copy, privacy
  policy, reveal-time exact-page behavior, and supported-source limitations are
  verified against the exact release candidate.

## Ten critical manual tests

Record full observations in [the complete manual test matrix](MANUAL_TEST_MATRIX.md). These ten tests are the release-blocking subset.

### Release-candidate run record

- Release commit/tag:
- Perch version and build:
- DMG SHA-256:
- Signing/notarization evidence:
- Test Mac model and macOS version:
- Clean user/account:
- Release owner:
- Run started:
- Run completed:

Do not reuse evidence from a different commit, locally staged app, user account,
or unsigned archive. Enter a named owner, ISO-8601 date, and a durable evidence
link or concise observation for every row. Any blank or failed row is stop-ship.

| # | Critical journey | Pass criteria | Owner | Date | Evidence |
|---:|---|---|---|---|---|
| 1 | Fresh launch and first pin | The app launches as an accessory, the menu-bar item is discoverable, and a valid Notion page can be pinned without confusion. | | | |
| 2 | Notion authentication | A tester can begin sign-in in the embedded Notion view, complete the secure browser handoff when required, and remain signed in after relaunch without exposing credentials to native app UI or logs. | | | |
| 3 | Stash and restore | Repeatedly stashing and restoring preserves the same page, unsaved edits, selection, and live WebView. | | | |
| 4 | Recovery paths | With the menu-bar icon hidden, the edge handle and global shortcut remain usable; shortcut-registration failure temporarily restores a discoverable control. With Context Suggestions enabled, global shortcut, menu-bar Show, status-item peek, edge restore, and Restore Current each run one reveal-time check without delaying an occupied PiP. | | | |
| 5 | Page switching | Switching among pinned and recent pages, including adding, editing, clearing, and searching local pin roles, preserves the active session and does not create extra live WebViews. | | | |
| 6 | Relaunch restoration | After quitting and reopening, pins, local roles, recents, the last validated URL, panel geometry, best-effort scroll position, and the actual macOS Launch at Login registration are reflected safely. | | | |
| 7 | Full-screen Spaces | The PiP appears above a full-screen app, accepts keyboard input, and stays out of Mission Control and normal window cycling. | | | |
| 8 | Display changes | On a two-display setup, moving, stashing, unplugging, and reconnecting a display never loses the panel, creates a duplicate, or reloads the page. | | | |
| 9 | Native page creation | The `+` button and Command-N open Notion's native new-page flow without changing or reloading the retained PiP page. | | | |
| 10 | Keyboard and VoiceOver | Pinning, switching, editing pin roles, stashing, restoring, choosing panel sizes, native page creation, and the dismissible Open Here action remain reachable and clearly announced without a pointer. | | | |

## Regression suite layers

- **Every release candidate:** run the ten-test smoke suite above on the exact notarized archive.
- **Feature changes:** run the relevant sections of `MANUAL_TEST_MATRIX.md`, recording build, owner, date, and observations there.
- **Periodic platform coverage:** run the complete matrix before a public milestone and after changes to WebKit, window/Space behavior, display topology, permissions, persistence, signing, or login items.

## Tester handoff

Ask each beta tester to use Perch during a normal workday and complete three jobs:

1. Pin the Notion page they use most.
2. Stash and restore the panel at least five times while editing.
3. Create five pages through the native Notion handoff.

Collect whether they could install and sign in unaided, understood pin/stash/new-page handoff, encountered lost state or text, and chose to keep the app running the next day.

## Launch at Login development limitation

The repository build can validate the public ServiceManagement flow only from
`dist/Perch.app`; a bare SwiftPM executable has no app-bundle registration
identity. The staged app is deleted, recreated, and ad-hoc signed on each build,
which can cause macOS to request approval again or leave a stale Login Items
entry. Treat that as development feedback, not release evidence. The beta gate
requires the Developer ID-signed, notarized DMG installed at a stable path
on a clean account, including a real logout/login cycle.

## Stop-ship conditions

Do not distribute a build that loses edits, exposes private Notion data, cannot be reopened after stashing, fails to recover after display changes, crashes during the three tester jobs, or is not signed and notarized for external installation.
