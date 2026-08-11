# Adaptive Toolbar Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Show Perch's complete toolbar while Notion is idle and hide the complete toolbar during typing or scrolling.

**Architecture:** Extend the existing trusted WebKit activity bridge with debounced scroll activity. Publish one interaction state from NotionWebSession and feed it into a pure PiPChromeView visibility policy, preserving top-edge and accessibility overrides.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, WebKit, XCTest, macOS 14+

## Global Constraints

- Keep WebKit messages restricted to trusted Notion HTTPS main frames.
- Do not depend on Notion private CSS classes.
- Hide the complete toolbar, including corner arrows.
- Scrolling returns to idle after 500 milliseconds without another scroll event.
- Preserve zero reserved content height.
- VoiceOver, Switch Control, and Full Keyboard Access keep controls visible.
- Reduce Motion disables the visibility animation.

---

### Task 1: Define the adaptive toolbar policy

**Files:**
- Modify: Tests/PerchTests/PiPChromeViewTests.swift
- Modify: Tests/PerchTests/NotionWebSessionTests.swift
- Modify: Sources/Perch/Views/PiPChromeView.swift

**Interfaces:**
- Consumes: NotionWebSession.isInteractingWithPage
- Produces: PiPChromeView.shouldShowTopControls(isInteractingWithPage:isHoveringTopEdge:isVoiceOverEnabled:isSwitchControlEnabled:isFullKeyboardAccessEnabled:) and hidden/expanded PiPTopToolbarPresentation behavior.

- [ ] **Step 1: Write failing policy tests**

Add assertions that idle returns true; active interaction returns false; top-edge hover and each assistive-access flag override active interaction; and topToolbarPresentation returns hidden for active interaction even when a position controller exists.

- [ ] **Step 2: Verify RED**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests

Expected: FAIL because the visibility policy lacks isInteractingWithPage and compact presentation still keeps corner arrows visible.

- [ ] **Step 3: Implement the minimal view policy**

Make idle the default expanded state, suppress the entire toolbar while isInteractingWithPage is true, retain hover and accessibility overrides, add an opacity transition, and keep reduced-motion behavior.

- [ ] **Step 4: Verify GREEN**

Run the focused PiPChromeViewTests and the legacy chrome-policy tests in NotionWebSessionTests. Expect zero failures.

### Task 2: Publish semantic typing and scrolling activity

**Files:**
- Modify: Tests/PerchTests/NotionWebSessionTests.swift
- Modify: Tests/PerchTests/NotionWebScriptMessageCoordinatorTests.swift
- Modify: Sources/Perch/Platform/NotionWebScriptMessageCoordinator.swift
- Modify: Sources/Perch/Platform/NotionWebSession.swift

**Interfaces:**
- Extends: NotionEditorActivity with scrollingStarted and scrollingEnded.
- Produces: NotionWebSession.isInteractingWithPage.

- [ ] **Step 1: Write failing session and script tests**

Assert typingStarted sets both isTypingInPage and isInteractingWithPage; editingEnded clears both; scrollingStarted clears typing and sets interaction; scrollingEnded clears interaction; navigation clears interaction. Assert the installed activity script contains capture-phase scroll handling, scrollingStarted, scrollingEnded, and a 500 millisecond timer.

- [ ] **Step 2: Verify RED**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter '(NotionWebSessionTests|NotionWebScriptMessageCoordinatorTests)'

Expected: FAIL because scrolling activity cases and isInteractingWithPage do not exist.

- [ ] **Step 3: Implement the minimal activity flow**

Extend the existing activity enum and document-start script. On the first captured scroll event, end typing and send scrollingStarted. Reset a 500 millisecond timer on every scroll. Send scrollingEnded after the quiet period. In NotionWebSession, guard duplicate published assignments and reset both typing and interaction through existing reveal/navigation/lifecycle paths.

- [ ] **Step 4: Verify GREEN**

Run the same focused suites and expect zero failures.

### Task 3: Align onboarding copy

**Files:**
- Modify: Sources/Perch/Views/OnboardingView.swift

**Interfaces:**
- Produces: User-facing and accessibility descriptions of the adaptive toolbar.

- [ ] **Step 1: Update the existing onboarding copy**

Replace the persistent-arrow and hover-only explanation with: the full toolbar stays visible while idle, hides while typing or scrolling, and can be revealed from the top edge. Update the artwork caption and accessibility summary consistently.

- [ ] **Step 2: Verify onboarding coverage**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OnboardingViewTests

Expected: zero failures after updating any exact-copy expectations.

### Task 4: Full verification and publication

**Files:**
- Verify all changed source, test, onboarding, spec, and plan files.

- [ ] **Step 1: Run the full Swift suite**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

Expected: zero failures.

- [ ] **Step 2: Run script tests**

Run: bash Tests/ScriptTests/sign_app_tests.sh

Expected: zero failures.

- [ ] **Step 3: Inspect the complete branch diff**

Confirm only adaptive-toolbar files and their tests/docs changed, and confirm no placeholder text or whitespace errors.

- [ ] **Step 4: Open a draft pull request**

Target master from agent/adaptive-toolbar-visibility. Summarize behavior, WebKit security, accessibility, and validation.
