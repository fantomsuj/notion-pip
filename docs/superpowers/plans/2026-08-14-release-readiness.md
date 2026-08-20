# Perch 0.1 Release-Readiness Implementation Plan

**Goal:** Reduce unvalidated interaction complexity and complete the repository-owned release obligations identified in the 2026-08-14 audit.

**Product decision:** Perch 0.1 centers on one live Notion page that is always nearby. Hold-to-peek remains an opt-in setting. Quick Copy is deferred from the 0.1 product composition and visible UI, while its isolated implementation and tests remain available for a later beta.

## Global constraints

- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Preserve the committed Notion popup fix that forms this branch's base.
- Use test-first changes for behavior and regressions.
- Do not mark manual, notarization, clean-Mac, or user-study gates complete without evidence.
- Keep privacy/support destinations repository-owned and usable from the production About UI.
- Do not broadly refactor the large WebKit or panel coordinators before 0.1.

## Task 1: Reduce experimental interaction surface

- Change a previously unset hold-to-peek preference to load as disabled; preserve explicit stored choices.
- Add/adjust regression tests that prove the default and persistence behavior.
- Remove Quick Copy from the production app composition and PiP chrome so no Accessibility monitor is created or armed in 0.1.
- Remove visible Quick Copy settings and production documentation claims; retain the isolated implementation and unit tests for future work.
- Keep ordinary shortcut Show/Hide behavior and existing explicit opt-in setting intact.

## Task 2: Simplify onboarding

- Replace the five-step machinery tour with a compact flow focused on: paste/open one Notion page, summon it with the shortcut, stash it when needed.
- Retain URL validation, Skip, completion, Settings access where needed, and keyboard/accessibility quality.
- Remove detailed corner, toolbar, role, size, menu, and shortcut-timing instruction from first run.
- Add focused tests for any extracted presentation/policy behavior.

## Task 3: Fix recovery accessibility and implementation identity

- Expose the failed-load message and retry button as distinct contained accessibility children.
- Add a semantic regression seam/test that would fail if the retry action were combined into the error label again.
- Replace raw Notion page IDs in ordinary page-switcher secondary text with recognition-oriented copy or no subtitle.
- Add regression coverage for titled, role-bearing, and title-less items.

## Task 4: Finish About and repository release obligations

- Remove production developer process metrics from Settings.
- Show bundle-derived version/build and minimum-system facts without hard-coded release values in the view.
- Add Support and Privacy actions to About using stable repository-owned destinations.
- Add a concise privacy policy covering embedded Notion session data, local history/restoration state, the deferred Quick Copy boundary, retention, permissions, and uninstall/data removal.
- Add support/feedback, install, uninstall, and permission-removal instructions.
- Update beta readiness into an operational 10-test smoke sheet with owner/build/date/evidence fields while keeping every unverified gate unchecked.
- Ensure generated development and release Info.plists carry standard copyright metadata; add script-test coverage.

## Task 5: Integration, review, and delivery

- Review every subagent diff for scope and conflicts.
- Run targeted tests, all script tests, and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- Obtain a whole-branch code review and address all critical/important findings.
- Commit intentionally, push, open a ready-for-review PR, watch CI/review state, and merge only when required checks are green.
