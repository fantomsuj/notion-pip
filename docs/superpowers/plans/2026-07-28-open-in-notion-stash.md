# Open in Notion and Stash PiP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the PiP toolbar’s Safari icon with a Notion-style mark and stash the visible PiP after opening its active page via the system URL handler.

**Architecture:** `PiPChromeView` owns a compact vector Notion-mark view and a combined toolbar action. The action reuses `NotionWebSession.openInBrowser()` for URL dispatch, then calls the existing stash callback, which the panel coordinator already connects to its normal edge-stash policy.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, macOS 14.

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Do not add external image assets or change URL routing; macOS chooses the default Notion app or browser.
- Retain the existing accessible label and preserve the standalone stash control.
- Build on the user’s existing uncommitted hover-toolbar changes without reverting or staging them.
- Validate with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

---

### Task 1: Combine the external-page and PiP-stash toolbar behavior

**Files:**
- Modify: `Sources/NotionPiP/Views/PiPChromeView.swift:4-140`
- Test: `Tests/NotionPiPTests/PiPChromeViewTests.swift`

**Interfaces:**
- Consumes: `NotionWebSession.openInBrowser()` and `PiPChromeView.onStash`.
- Produces: `PiPChromeView.openInNotionAndStash()` and `NotionToolbarNotionMark`, a reusable view for the toolbar’s Notion mark.

- [ ] **Step 1: Write the failing combined-action test**

```swift
func testOpenInNotionAndStashOpensActivePageThenInvokesStash() throws {
    var openedURLs: [URL] = []
    var stashCount = 0
    let page = try makePage(id: firstPageID, title: "Roadmap")
    let session = NotionWebSession(openURL: { openedURLs.append($0) })
    session.activate(page: page)
    let chrome = PiPChromeView(webSession: session, onStash: { stashCount += 1 })

    chrome.openInNotionAndStash()

    XCTAssertEqual(openedURLs, [page.canonicalURL])
    XCTAssertEqual(stashCount, 1)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests/testOpenInNotionAndStashOpensActivePageThenInvokesStash`

Expected: compilation failure because `openInNotionAndStash()` does not exist.

- [ ] **Step 3: Implement the minimal toolbar action and mark**

```swift
func openInNotionAndStash() {
    webSession.openInBrowser()
    onStash()
}

Button(action: openInNotionAndStash) {
    NotionToolbarNotionMark()
}
.buttonStyle(.plain)
.accessibilityLabel("Open Notion page in browser")
```

Implement `NotionToolbarNotionMark` as a local SwiftUI `View` made from vector
primitives, sized for a toolbar control and rendered as a template so it adapts
to the surrounding control color. Do not alter the existing accessibility
label, help text, page-opening route, or separate stash button.

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests/testOpenInNotionAndStashOpensActivePageThenInvokesStash`

Expected: PASS; the URL array contains the active canonical URL once and the
stash callback count is one.

- [ ] **Step 5: Commit the focused implementation**

```bash
git add Sources/NotionPiP/Views/PiPChromeView.swift Tests/NotionPiPTests/PiPChromeViewTests.swift
git commit -m "feat: stash PiP when opening Notion"
```

Do not stage `Sources/NotionPiP/Views/TopControlsHoverController.swift` or
unrelated user changes.

### Task 2: Verify the package regression suite

**Files:**
- Verify only: `Sources/NotionPiP/Views/PiPChromeView.swift`
- Verify only: `Tests/NotionPiPTests/PiPChromeViewTests.swift`

**Interfaces:**
- Consumes: the completed combined toolbar action and full Swift package test suite.
- Produces: fresh test evidence that toolbar behavior, session URL dispatch, and
edge-stash behavior remain compatible.

- [ ] **Step 1: Inspect the focused diff**

Run: `git diff -- Sources/NotionPiP/Views/PiPChromeView.swift Tests/NotionPiPTests/PiPChromeViewTests.swift`

Expected: the diff contains the Notion toolbar mark, the combined action, and
the focused regression test; the pre-existing hover-controller edits are left
intact.

- [ ] **Step 2: Run the complete Swift package suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Expected: exit status 0 with all tests passing.
