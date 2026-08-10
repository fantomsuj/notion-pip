# Shortcut Lifecycle Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revalidate and recover both global shortcuts after supported macOS wake and session lifecycle changes without polling or losing the panel's menu-bar fallback.

**Architecture:** A main-actor lifecycle coordinator observes public workspace notifications and uses an injected one-shot scheduler to coalesce bursts and reject stale callbacks. The Carbon registrar gains explicit revalidation and error classification, while `AppRuntime` owns atomic shortcut configuration, per-shortcut health, and one bounded retry for transient failures.

**Tech Stack:** Swift 6.2, AppKit `NSWorkspace`, Carbon HIToolbox, structured concurrency, Combine, XCTest, macOS 14 public APIs.

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Use only supported public AppKit, Workspace, and Carbon APIs.
- Do not add periodic polling.
- Never remove the menu-bar fallback while the panel shortcut is unavailable.
- Keep tests deterministic and independent because Swift tests may run in parallel.

---

### Task 1: Registrar revalidation and failure classification

**Files:**
- Modify: `Sources/Perch/Platform/GlobalShortcutRegistrar.swift`
- Test: `Tests/PerchTests/GlobalShortcutTests.swift`

**Interfaces:**
- Produces: `GlobalShortcutRegistrationFailure: Error, Equatable` with `.conflict` and `.transient`
- Produces: `GlobalShortcutRegistering.revalidate() throws`
- Produces: Carbon status mapping where `eventHotKeyExistsErr` is `.conflict` and all other installation failures are `.transient`

- [ ] **Step 1: Write failing registrar tests**

Add tests proving an unchanged chord is uninstalled and installed again, `eventHotKeyExistsErr` maps to conflict, another hot-key status maps to transient, and revalidation without a configured shortcut is a no-op.

- [ ] **Step 2: Verify the focused tests fail for missing behavior**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GlobalShortcutTests
```

Expected: compilation or assertion failures naming the missing `revalidate` and failure classification behavior.

- [ ] **Step 3: Implement minimal registrar behavior**

Store the installed shortcut and handler, add a force-install path used by `revalidate`, classify Carbon installation errors at the registrar boundary, and preserve the existing rollback behavior for replacement.

- [ ] **Step 4: Verify the focused tests pass**

Run the same filtered command and require exit code 0.

- [ ] **Step 5: Commit the registrar cycle**

```sh
git add Sources/Perch/Platform/GlobalShortcutRegistrar.swift Tests/PerchTests/GlobalShortcutTests.swift
git commit -m "feat: revalidate Carbon shortcuts"
```

### Task 2: Deterministic lifecycle coordinator

**Files:**
- Create: `Sources/Perch/Platform/ShortcutLifecycleCoordinator.swift`
- Create: `Tests/PerchTests/ShortcutLifecycleCoordinatorTests.swift`

**Interfaces:**
- Produces: `ShortcutRecoveryScheduling.schedule(after:operation:) -> ShortcutRecoveryCancellation`
- Produces: `ShortcutLifecycleCoordinator.start()`, `requestRetry()`, `invalidatePendingRecovery()`, and `stop()`
- Consumes: injected notification center, lifecycle notification names, coalescing delay, scheduler, and `onRecovery` callback

- [ ] **Step 1: Write failing coordinator tests**

Cover a sleep/wake/session notification burst producing one recovery, explicit retry coalescing, settings invalidation, stop removing observers, and an already-captured stale callback doing nothing.

- [ ] **Step 2: Verify the coordinator tests fail**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ShortcutLifecycleCoordinatorTests
```

Expected: compilation failure because the coordinator interfaces do not exist.

- [ ] **Step 3: Implement the coordinator**

Observe `NSWorkspace.didWakeNotification`, `NSWorkspace.screensDidWakeNotification`, and `NSWorkspace.sessionDidBecomeActiveNotification`. Cancel and replace pending one-shot work for each burst; carry a monotonically increasing generation into closures; make `stop()` idempotently remove observers, cancel work, and invalidate captured callbacks.

- [ ] **Step 4: Verify coordinator tests pass**

Run the filtered command and require exit code 0.

- [ ] **Step 5: Commit the coordinator cycle**

```sh
git add Sources/Perch/Platform/ShortcutLifecycleCoordinator.swift Tests/PerchTests/ShortcutLifecycleCoordinatorTests.swift
git commit -m "feat: coordinate shortcut lifecycle recovery"
```

### Task 3: Atomic runtime configuration and recovery health

**Files:**
- Modify: `Sources/Perch/App/AppRuntime.swift`
- Modify: `Sources/Perch/App/AppRuntime+Activation.swift`
- Modify: `Sources/Perch/App/AppRuntimeStateTypes.swift`
- Modify: `Sources/Perch/Views/ServiceHealthView.swift`
- Modify: `Sources/Perch/Views/GlobalShortcutRecorderView.swift`
- Test: `Tests/PerchTests/GlobalShortcutTests.swift`
- Test: `Tests/PerchTests/RuntimeActivationAndMenuBarTests.swift`
- Test: `Tests/PerchTests/AppRuntimeTestSupport.swift`

**Interfaces:**
- Produces: `ShortcutConfiguration(panel:quickCapture:)` as the runtime's single published shortcut value
- Produces: `ServiceHealthIssue.quickCaptureShortcutUnavailable`
- Consumes: `ShortcutLifecycleCoordinator` recovery callbacks and registrar `revalidate()` results

- [ ] **Step 1: Write failing runtime tests**

Cover duplicate-chord rejection, no persistence/publication on either settings registration failure, successful recovery of both shortcuts, persistent conflict without retry, one transient retry, one-shortcut failure health isolation, panel fallback persistence, settings changes during pending recovery, and stale recovery result rejection.

- [ ] **Step 2: Verify the focused runtime tests fail**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GlobalShortcutTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeActivationAndMenuBarTests
```

Expected: failures naming missing atomic configuration, Quick Capture health, and lifecycle recovery behavior.

- [ ] **Step 3: Implement atomic settings behavior**

Load and publish one configuration value, validate both chords before registration, register before publishing or saving, invalidate pending recovery after successful settings changes, and keep both saved/displayed values unchanged on failure.

- [ ] **Step 4: Implement runtime recovery policy**

Start the coordinator after initial registration. Revalidate both registrars independently, resolve or report their distinct health issues, schedule exactly one follow-up when either result is transient, and ignore results whose configuration generation no longer matches. Keep menu-bar forcing tied to `globalShortcutUnavailable` only.

- [ ] **Step 5: Update settings and health messaging**

Give both recorder surfaces conflict-aware failure feedback based on runtime behavior and add Quick Capture recovery guidance to `ServiceHealthView` without changing panel fallback copy.

- [ ] **Step 6: Verify focused tests pass**

Run both filtered commands and require exit code 0.

- [ ] **Step 7: Commit runtime integration**

```sh
git add Sources/Perch/App Sources/Perch/Views Tests/PerchTests
git commit -m "feat: self-heal shortcuts after lifecycle changes"
```

### Task 4: Full verification and manual evidence

**Files:**
- Modify if necessary: `docs/MANUAL_TEST_MATRIX.md`

**Interfaces:**
- Consumes: complete shortcut recovery implementation
- Produces: repeatable manual checks and a green Swift suite

- [ ] **Step 1: Review the diff against every design requirement**

Use `git diff origin/master... --check` and inspect the complete diff for unrelated changes, private API use, polling, unsafe concurrency, or menu fallback regressions.

- [ ] **Step 2: Run the full Swift suite**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: exit code 0 with zero failed tests.

- [ ] **Step 3: Build and run for manual verification when the app is not already running**

```sh
pgrep -x Perch
./script/build_and_run.sh --verify
```

If `Perch` is already running, do not invoke the build script because it terminates the app; record the manual run as not performed. Otherwise verify sleep/wake behavior and a conflicting registration to the extent supported by the non-interactive environment, documenting anything that still requires the user's physical session.

- [ ] **Step 4: Commit any manual test documentation**

```sh
git add docs/MANUAL_TEST_MATRIX.md
git commit -m "docs: cover shortcut recovery verification"
```

Skip this commit when the existing matrix already covers the behavior or no documentation change is needed.

### Task 5: Draft PR, CI, merge, and post-merge verification

**Files:**
- No source files unless sync or CI failures require fixes

**Interfaces:**
- Consumes: verified feature branch and `origin/master`
- Produces: merged pull request with passing pre-merge and post-merge checks

- [ ] **Step 1: Fetch and sync the target branch**

Fetch origin, merge `origin/master` into the feature branch without force-pushing, resolve all conflicts, and rerun the full Swift suite.

- [ ] **Step 2: Push and create a draft PR**

Push the current named branch and create a draft pull request targeting `master`, using the repository template when present.

- [ ] **Step 3: Watch all PR checks**

Use GitHub CLI checks with watch mode. Diagnose failures from their actual logs, add focused regression fixes, rerun local verification, commit, push, and repeat until every required check passes.

- [ ] **Step 4: Mark ready and merge**

Mark the PR ready only after all checks pass, then merge using the repository's permitted strategy without deleting the Conductor-managed worktree.

- [ ] **Step 5: Verify post-merge CI end to end**

Watch workflows triggered by the merge commit until completion. If any fail, fix forward on the same workspace with a follow-up PR and repeat verification until the target branch is green.
