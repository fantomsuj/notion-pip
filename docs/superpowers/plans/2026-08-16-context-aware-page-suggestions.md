# Context-Aware Page Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in, local context sensing that recommends one pinned/recent Notion page and opens it at its saved position.

**Architecture:** A pure matcher scores local pages against a transient Accessibility context snapshot. A main-actor controller owns permission, cooldown, and activation while a narrow AppKit controller presents a nonactivating SwiftUI card.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, ApplicationServices Accessibility, SwiftData-backed `PageWorkingSetPersisting`, XCTest.

## Global Constraints

- Preserve macOS 14+, Swift 6.2, the single retained `WKWebView`, and direct distribution.
- Do not require a Notion token or search outside the existing 14-page working set.
- Do not persist or log raw application, window-title, URL, selection, or DOM context.
- Do not prompt for Accessibility access until the user explicitly enables the feature.
- Follow test-first red/green cycles for production behavior.

---

### Task 1: Context matching domain

**Files:**
- Create: `Sources/Perch/Domain/ContextSuggestion.swift`
- Create: `Tests/PerchTests/ContextSuggestionMatcherTests.swift`

**Interfaces:**
- Produces: `ContextSnapshot`, `ContextSuggestion`, and `ContextSuggestionMatcher.bestSuggestion(in:context:activePageID:)`.
- Consumes: `PageWorkingSetSnapshot`, `StoredPageSnapshot`, and `DurablePageRestoration`.

- [ ] Write tests with literal working-set fixtures for role priority, title fallback, active-page exclusion, URL tokens, pinned tie-breaking, low-confidence silence, and restoration propagation.
- [ ] Run `swift test --filter ContextSuggestionMatcherTests` and confirm the missing-type compile failure.
- [ ] Implement normalized token extraction and deterministic scoring with stop-word removal and a minimum confidence threshold.
- [ ] Run the focused tests and confirm they pass.

### Task 2: Opt-in monitor and controller

**Files:**
- Create: `Sources/Perch/Platform/AccessibilityContextMonitor.swift`
- Create: `Sources/Perch/Persistence/ContextSuggestionPreferenceStore.swift`
- Create: `Sources/Perch/App/ContextSuggestionController.swift`
- Create: `Tests/PerchTests/ContextSuggestionControllerTests.swift`

**Interfaces:**
- Consumes: `ContextSuggestionMatcher`, `PageWorkingSetPersisting`.
- Produces: `ContextMonitoring`, `ContextSuggestionPermissionState`, observable `ContextSuggestionController`, `setEnabled`, `acceptSuggestion`, and `dismissSuggestion`.

- [ ] Write controller tests proving disabled-by-default behavior, explicit permission request, permission denial, changed-context matching, duplicate suppression, thirty-minute dismissal suppression, activation with restoration, and immediate stop on disable.
- [ ] Run `swift test --filter ContextSuggestionControllerTests` and confirm the missing-type compile failure.
- [ ] Implement a preference store and controller with injected clock/monitor/store for deterministic tests.
- [ ] Implement a polling Accessibility adapter that reads frontmost app, focused window title, and optional `kAXDocumentAttribute` URL without reading selected text.
- [ ] Run the focused controller tests and confirm they pass.

### Task 3: Nonactivating card and composition

**Files:**
- Modify: `Sources/Perch/Platform/WindowRolePolicy.swift`
- Create: `Sources/Perch/Views/ContextSuggestionCard.swift`
- Create: `Sources/Perch/Platform/ContextSuggestionPanelController.swift`
- Modify: `Sources/Perch/Views/SettingsView.swift`
- Modify: `Sources/Perch/Platform/AppWindowFactory.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Sources/Perch/App/AppRuntimeStateTypes.swift`
- Modify: `Tests/PerchTests/WindowRolePolicyTests.swift`
- Create: `Tests/PerchTests/ContextSuggestionCardTests.swift`

**Interfaces:**
- Consumes: observable `ContextSuggestionController` and `AppRuntime.activate`.
- Produces: `WindowRole.contextSuggestion`, `ContextSuggestionCardPresentation`, and a retained `ContextSuggestionPanelController`.

- [ ] Write failing tests for the nonactivating window role and concise card presentation/accessibility copy.
- [ ] Run focused tests and confirm the new role/presentation is absent.
- [ ] Add the window role, SwiftUI card, panel placement, Settings toggle/status, and composition wiring.
- [ ] Route acceptance through `PageActivationSource.contextSuggestion` with the candidate restoration.
- [ ] Run focused tests and confirm they pass.

### Task 4: Documentation and verification

**Files:**
- Modify: `README.md`
- Modify: `docs/PRIVACY.md`
- Modify: `docs/MANUAL_TEST_MATRIX.md`

**Interfaces:**
- Consumes: completed feature behavior.
- Produces: accurate user-facing setup, privacy boundary, and manual verification matrix.

- [ ] Document opt-in Accessibility behavior, local-only context fields, disabling/revocation, and saved-position restoration.
- [ ] Run `git diff --check`.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` on macOS; when unavailable, record the environment blocker and run all portable script tests.
- [ ] Review the complete diff against the design constraints, then commit and publish a draft PR.
