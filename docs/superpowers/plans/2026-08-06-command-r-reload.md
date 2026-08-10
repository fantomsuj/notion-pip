# Command-R Reload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standard macOS `Command-R` command that reloads the URL currently displayed by the focused Perch `WKWebView`.

**Architecture:** Extend the existing AppKit main-menu factory with a targetless View → Reload item. AppKit's responder chain will route `reload:` to `WKWebView`, preserving the current URL, cookies, and sign-in state without adding a system-wide shortcut or application-specific reload state.

**Tech Stack:** Swift 6.2, AppKit, WebKit, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Keep the existing saved-page re-pin behavior unchanged.
- Do not register `Command-R` as a Carbon global shortcut.
- Validate with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

---

### Task 1: Route Command-R to the focused WebKit view

**Files:**
- Modify: `Tests/PerchTests/AppMainMenuTests.swift`
- Modify: `Sources/Perch/Platform/AppMainMenuFactory.swift`

**Interfaces:**
- Consumes: AppKit's targetless menu-item responder routing and `WKWebView`'s Objective-C `reload:` action.
- Produces: `AppMainMenuFactory.make()` returns a main menu containing View → Reload with key equivalent `r` and modifier mask `.command`.

- [ ] **Step 1: Write the failing responder-chain test**

Add `import WebKit` and this test to `AppMainMenuTests`:

```swift
func testViewMenuRoutesCommandRReloadThroughTheResponderChain() throws {
    let mainMenu = AppMainMenuFactory.make()
    let viewMenu = try XCTUnwrap(mainMenu.item(withTitle: "View")?.submenu)
    let reload = try XCTUnwrap(viewMenu.item(withTitle: "Reload"))

    XCTAssertTrue(viewMenu.autoenablesItems)
    XCTAssertEqual(reload.action, NSSelectorFromString("reload:"))
    XCTAssertNil(reload.target)
    XCTAssertEqual(reload.keyEquivalent, "r")
    XCTAssertEqual(reload.keyEquivalentModifierMask, [.command])
    XCTAssertTrue(WKWebView().responds(to: try XCTUnwrap(reload.action)))
}
```

- [ ] **Step 2: Run the focused test and verify the expected red state**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter AppMainMenuTests/testViewMenuRoutesCommandRReloadThroughTheResponderChain
```

Expected: FAIL because `AppMainMenuFactory.make()` does not yet create a `View` menu.

- [ ] **Step 3: Add the minimal View → Reload menu implementation**

Update `AppMainMenuFactory.make()` to append a View menu after Edit, and add:

```swift
private static func makeViewMenu() -> NSMenu {
    let menu = NSMenu(title: "View")
    menu.autoenablesItems = true
    menu.addItem(
        command(
            title: "Reload",
            action: NSSelectorFromString("reload:"),
            keyEquivalent: "r"
        )
    )
    return menu
}
```

- [ ] **Step 4: Run the focused test and verify green**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Run the full Swift test suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 6: Inspect the final diff and commit**

Run `git diff --check` and inspect `git diff origin/master...HEAD`, then commit:

```sh
git add Sources/Perch/Platform/AppMainMenuFactory.swift \
  Tests/PerchTests/AppMainMenuTests.swift \
  docs/superpowers/plans/2026-08-06-command-r-reload.md
git commit -m "feat: reload Notion page with command-r"
```
