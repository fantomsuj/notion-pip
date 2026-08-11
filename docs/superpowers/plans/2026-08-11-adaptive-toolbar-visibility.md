# Adaptive Toolbar Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Show Perch's complete toolbar while Notion is idle and hide the complete toolbar during typing or scrolling.

**Architecture:** Extend the existing trusted WebKit activity bridge with debounced scroll activity. Publish one interaction state from NotionWebSession and feed it into a pure PiPChromeView visibility policy, preserving top-edge and accessibility overrides.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, WebKit, XCTest, macOS 14+

## Global Constraints

- Keep WebKit messages restricted to trusted Notion HTTPS main frames.
- Do not depend on Notion private CSS classes.
- Hide the complete toolbar, including corner arrows.
- Typing returns to idle after 800 milliseconds without another edit event.
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

- [x] **Step 1: Write failing policy tests**

Add assertions that idle returns true; active interaction returns false; top-edge hover and each assistive-access flag override active interaction; and topToolbarPresentation returns hidden for active interaction even when a position controller exists.

- [x] **Step 2: Verify RED**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests

Expected: FAIL because the visibility policy lacks isInteractingWithPage and compact presentation still keeps corner arrows visible.

- [x] **Step 3: Implement the minimal view policy**

Make idle the default expanded state, suppress the entire toolbar while isInteractingWithPage is true, retain hover and accessibility overrides, add an opacity transition, and keep reduced-motion behavior.

- [x] **Step 4: Verify GREEN**

Run the focused PiPChromeViewTests and the legacy chrome-policy tests in NotionWebSessionTests. Expect zero failures.

### Task 2: Publish semantic typing and scrolling activity

**Files:**
- Modify: Tests/PerchTests/NotionWebSessionTests.swift
- Modify: Tests/PerchTests/NotionWebScriptMessageCoordinatorTests.swift
- Modify: Sources/Perch/Platform/NotionWebScriptMessageCoordinator.swift
- Modify: Sources/Perch/Platform/NotionWebSession.swift

**Interfaces:**
- Extends: NotionEditorActivity with scrollingStarted and scrollingEnded.
- Produces: independent NotionWebSession.isTypingInPage and isScrollingInPage state, plus derived isInteractingWithPage.

- [x] **Step 1: Write failing session and script tests**

Assert typing and scrolling start/end independently across interleaved and duplicate messages; navigation clears both. Assert the installed activity script contains an 800 millisecond typing quiet timer, capture-phase nested-scroll handling, a resettable 500 millisecond scroll quiet timer, and reusable pagehide/pageshow resets. Execute these behaviors in a trusted WKWebView fixture.

- [x] **Step 2: Verify RED**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter '(NotionWebSessionTests|NotionWebScriptMessageCoordinatorTests)'

Expected: FAIL because scrolling activity cases and isInteractingWithPage do not exist.

- [x] **Step 3: Implement the minimal activity flow**

Extend the existing activity enum and document-start script. Reset the 800 millisecond typing quiet timer on each edit. Capture main and nested scrolls, reset the 500 millisecond scroll quiet timer, and preserve continuous interaction when transitioning between activities. Track typing and scrolling independently in NotionWebSession, suppress duplicate published assignments, and reset both through existing navigation and lifecycle paths.

- [x] **Step 4: Verify GREEN**

Run the same focused suites and expect zero failures.

### Task 3: Align onboarding copy

**Files:**
- Modify: Sources/Perch/Views/OnboardingView.swift

**Interfaces:**
- Produces: User-facing and accessibility descriptions of the adaptive toolbar.

- [x] **Step 1: Update the existing onboarding copy**

Replace the persistent-arrow and hover-only explanation with: the full toolbar stays visible while idle, hides while typing or scrolling, and can be revealed from the top edge. Update the artwork caption and accessibility summary consistently.

- [x] **Step 2: Verify onboarding coverage**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OnboardingContentTests

Expected: zero failures after updating any exact-copy expectations.

### Task 4: Full verification and publication

**Files:**
- Verify all changed source, test, onboarding, spec, and plan files.

- [x] **Step 1: Run the full Swift suite**

Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

Expected: zero failures.

- [x] **Step 2: Run script tests**

Run: bash Tests/ScriptTests/sign_app_tests.sh

Expected: zero failures.

- [x] **Step 3: Inspect the complete branch diff**

Confirm only adaptive-toolbar files and their tests/docs changed, and confirm no placeholder text or whitespace errors.

- [x] **Step 4: Open a draft pull request**

Target master from agent/adaptive-toolbar-visibility. Summarize behavior, WebKit security, accessibility, and validation.

Verification note: GitHub Actions CI run 152 passed script tests, 434 non-WebKit tests, and every isolated WebKit-dependent suite after the final source and test changes.
