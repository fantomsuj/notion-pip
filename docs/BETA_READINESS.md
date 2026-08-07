# External Beta Readiness

This checklist defines the minimum bar for giving Notion PiP 0.1 to people outside the development team. It intentionally separates repository readiness from Developer ID signing and notarization, which belong in the distribution PR.

## Release gate

- [ ] CI passes for Swift tests, web tests, TypeScript checks, and generated-editor verification.
- [ ] `Support/Version.env` contains the intended user-facing version and a new build number.
- [ ] The ten critical manual tests below pass on a clean macOS 14+ user account.
- [ ] The app has a final icon, support URL, privacy policy, and installation instructions.
- [ ] A Developer ID-signed and notarized archive installs on a Mac that did not build the app.
- [ ] Launch at Login is enabled, approved when required, exercised across a
  real login, disabled again, and checked after relaunch using that distributed
  archive.
- [ ] No test account, Notion token, session cookie, signing credential, or notarization credential is committed.
- [ ] Five to ten testers have an owner, contact method, and feedback deadline.
- [ ] Known limitations and recovery steps are included with the beta.

## Ten critical manual tests

Record full observations in [the complete manual test matrix](MANUAL_TEST_MATRIX.md). These ten tests are the release-blocking subset.

| # | Critical journey | Pass criteria | Evidence |
|---:|---|---|---|
| 1 | Fresh launch and first pin | The app launches as an accessory, the menu-bar item is discoverable, and a valid Notion page can be pinned without confusion. | |
| 2 | Notion authentication | A tester can sign in inside the embedded Notion view and remains signed in after relaunch without exposing credentials to the app UI or logs. | |
| 3 | Stash and restore | Repeatedly stashing and restoring preserves the same page, unsaved edits, selection, and live WebView. | |
| 4 | Recovery paths | With the menu-bar icon hidden, the edge handle and global shortcut remain usable; shortcut-registration failure temporarily restores a discoverable control. | |
| 5 | Page switching | Switching among pinned and recent pages, including adding, editing, clearing, and searching local pin roles, preserves the active session and does not create extra live WebViews. | |
| 6 | Relaunch restoration | After quitting and reopening, pins, local roles, recents, the last validated URL, panel geometry, best-effort scroll position, and the actual macOS Launch at Login registration are reflected safely. | |
| 7 | Full-screen Spaces | The PiP appears above a full-screen app, accepts keyboard input, and stays out of Mission Control and normal window cycling. | |
| 8 | Display changes | On a two-display setup, moving, stashing, unplugging, and reconnecting a display never loses the panel, creates a duplicate, or reloads the page. | |
| 9 | Quick Capture durability | Saving, retrying after failure, resolving a conflict, closing, and terminating the app do not silently lose a draft or create an unintended duplicate. | |
| 10 | Keyboard and VoiceOver | Pinning, switching, editing pin roles, stashing, restoring, choosing panel sizes, and Quick Capture remain reachable and clearly announced without a pointer. | |

## Tester handoff

Ask each beta tester to use Notion PiP during a normal workday and complete three jobs:

1. Pin the Notion page they use most.
2. Stash and restore the panel at least five times while editing.
3. Save five thoughts with Quick Capture.

Collect whether they could install and sign in unaided, understood pin/stash/Quick Capture, encountered lost state or text, and chose to keep the app running the next day.

## Launch at Login development limitation

The repository build can validate the public ServiceManagement flow only from
`dist/NotionPiP.app`; a bare SwiftPM executable has no app-bundle registration
identity. The staged app is deleted, recreated, and ad-hoc signed on each build,
which can cause macOS to request approval again or leave a stale Login Items
entry. Treat that as development feedback, not release evidence. The beta gate
requires the Developer ID-signed, notarized archive installed at a stable path
on a clean account, including a real logout/login cycle.

## Stop-ship conditions

Do not distribute a build that loses edits or drafts, exposes private Notion data, cannot be reopened after stashing, fails to recover after display changes, crashes during the three tester jobs, or is not signed and notarized for external installation.
