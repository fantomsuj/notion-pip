# Animated Perch Mark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Recent Pages layered-card hover motion Perch's consistent interaction-triggered identity across SwiftUI and menu-bar surfaces.

**Architecture:** Introduce a focused SwiftUI `PerchMark` drawing primitive backed by a pure `PerchMarkMotionPolicy`, then make existing SwiftUI surfaces own and pass their interaction state. Keep menu-bar drawing in AppKit through `StatusItemGlyphPolicy`, using the same geometry and state semantics without coupling SwiftUI state to `NSStatusItem`.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, QuartzCore, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve macOS 14+, Swift 6.2, public API, signing, and entitlement contracts.
- Motion occurs only on hover, state change, shortcut summon, or an existing reveal interaction; add no idle loop or repeating timer.
- Respect Reduce Motion by resolving to a stable mark without geometric animation.
- Preserve existing accessible labels, help text, hit targets, keyboard behavior, pointer actions, and menu-bar state meaning.
- Keep `Support/Perch.icns` and `Support/Perch-AppIcon.png` unchanged.
- Do not change navigation, recent-page behavior, menu commands, app state semantics, signing, or entitlements.

---

## File Map

- Create `Sources/Perch/Views/PerchMark.swift`: reusable two-layer SwiftUI mark and pure separation policy.
- Modify `Sources/Perch/Views/ToolbarMotionIcon.swift`: delegate the page-stack glyph to `PerchMark` and remove duplicate geometry.
- Modify `Sources/Perch/Views/OnboardingView.swift`: use an interactive decorative mark in the Perch header.
- Modify `Sources/Perch/Views/SettingsView.swift`: add a restrained interactive mark to About.
- Modify `Sources/Perch/Views/PiPStashHandleView.swift`: show the mark and feed it existing hover state.
- Modify `Sources/Perch/Platform/StatusItemGlyphPolicy.swift`: draw stateful template variants of the mark.
- Modify `Sources/Perch/Platform/StatusItemMotionPolicy.swift`: define menu-bar hover separation.
- Modify `Sources/Perch/Platform/StatusItemController.swift`: install lifecycle-safe hover tracking and render the hover variant.
- Modify `Tests/PerchTests/PiPChromeViewTests.swift`: test shared mark motion policy and toolbar delegation behavior.
- Modify `Tests/PerchTests/StatusItemGlyphPolicyTests.swift`: test stateful mark rendering and template-image guarantees.
- Modify `Tests/PerchTests/StatusItemMotionPolicyTests.swift`: test hover separation and Reduce Motion behavior.
- Modify `Tests/PerchTests/PiPStashHandleInteractionTests.swift`: retain coverage that handle hover is forwarded once.

### Task 1: Shared SwiftUI Perch Mark

**Files:**
- Create: `Sources/Perch/Views/PerchMark.swift`
- Modify: `Sources/Perch/Views/ToolbarMotionIcon.swift`
- Test: `Tests/PerchTests/PiPChromeViewTests.swift`

**Interfaces:**
- Produces: `PerchMarkMotionPolicy.separation(isActive:reducesMotion:) -> CGFloat`
- Produces: `PerchMark(isActive:lineWidth:)`, a decorative SwiftUI `View`
- Consumes: `PanelCornerControls.minimumHitTarget` only at the toolbar call site; the mark itself has no control sizing dependency.

- [ ] **Step 1: Write the failing shared-policy test**

Replace `testPageStackSeparatesOnlyForPointerHoverWithMotionEnabled` in `PiPChromeViewTests.swift` with:

```swift
func testPerchMarkSeparatesOnlyForInteractionWithMotionEnabled() {
    XCTAssertEqual(
        PerchMarkMotionPolicy.separation(isActive: false, reducesMotion: false),
        0
    )
    XCTAssertEqual(
        PerchMarkMotionPolicy.separation(isActive: true, reducesMotion: false),
        1.5
    )
    XCTAssertEqual(
        PerchMarkMotionPolicy.separation(isActive: true, reducesMotion: true),
        0
    )
    XCTAssertEqual(PerchMarkMotionPolicy.duration, 0.12)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests/testPerchMarkSeparatesOnlyForInteractionWithMotionEnabled
```

Expected: compilation fails because `PerchMarkMotionPolicy` does not exist.

- [ ] **Step 3: Add the minimal shared mark and policy**

Create `PerchMark.swift` with these declarations and geometry:

```swift
import SwiftUI

enum PerchMarkMotionPolicy {
    static let duration: TimeInterval = 0.12

    static func separation(isActive: Bool, reducesMotion: Bool) -> CGFloat {
        isActive && !reducesMotion ? 1.5 : 0
    }
}

struct PerchMark: View {
    let isActive: Bool
    var lineWidth: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let separation = PerchMarkMotionPolicy.separation(
            isActive: isActive,
            reducesMotion: reduceMotion
        )

        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: lineWidth)
                .offset(x: -0.75 - separation / 2, y: -0.75 - separation / 2)
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(lineWidth: lineWidth)
                .offset(x: 0.75 + separation / 2, y: 0.75 + separation / 2)
        }
        .frame(width: 11, height: 9)
        .animation(
            reduceMotion ? nil : .easeOut(duration: PerchMarkMotionPolicy.duration),
            value: isActive
        )
        .accessibilityHidden(true)
    }
}
```

In `ToolbarMotionIcon`, replace `pageStackGlyph` with `PerchMark(isActive: isHovering)` and delete `ToolbarIconMotionPolicy.pageStackSeparation` plus the duplicated `ZStack`.

- [ ] **Step 4: Run focused toolbar tests**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests
```

Expected: all `PiPChromeViewTests` pass and the page-switcher label/help behavior is unchanged.

- [ ] **Step 5: Commit the shared mark**

```sh
git add Sources/Perch/Views/PerchMark.swift Sources/Perch/Views/ToolbarMotionIcon.swift Tests/PerchTests/PiPChromeViewTests.swift
git commit -m "Add shared animated Perch mark"
```

### Task 2: Apply the Mark to SwiftUI Identity Surfaces

**Files:**
- Modify: `Sources/Perch/Views/OnboardingView.swift`
- Modify: `Sources/Perch/Views/SettingsView.swift`
- Modify: `Sources/Perch/Views/PiPStashHandleView.swift`
- Test: `Tests/PerchTests/PiPStashHandleInteractionTests.swift`

**Interfaces:**
- Consumes: `PerchMark(isActive:lineWidth:)` from Task 1.
- Produces: `PerchIdentityLabel`, a private reusable label in `PerchMark.swift` with local hover state for text-adjacent branding.
- Preserves: `PiPStashHandleView.onHoverChanged` callback contract.

- [ ] **Step 1: Add a failing handle-hover forwarding assertion**

Extend the existing hover test in `PiPStashHandleInteractionTests.swift` so one enter and one exit still produce exactly `[true, false]` after mark integration:

```swift
XCTAssertEqual(hoverStates, [true, false])
```

If the existing test already asserts that exact sequence, leave it intact and run it as the regression gate rather than duplicating it.

- [ ] **Step 2: Run the focused handle test before editing**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPStashHandleInteractionTests
```

Expected: PASS, establishing the callback behavior that the visual change must preserve.

- [ ] **Step 3: Add the identity label and replace generic marks**

Append this private-state wrapper to `PerchMark.swift`:

```swift
struct PerchIdentityLabel: View {
    let title: String
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            PerchMark(isActive: isHovering)
            Text(title)
        }
        .onHover { isHovering = $0 }
    }
}
```

Use `PerchIdentityLabel(title: "Perch")` in the onboarding header. In Settings About, replace the plain Application value with a compact `LabeledContent("Application") { PerchIdentityLabel(title: "Perch") }`.

In `PiPStashHandleView`, add `@State private var isHovering = false`, replace `Image(systemName: "rectangle.on.rectangle")` with `PerchMark(isActive: isHovering, lineWidth: 1.2)`, and wrap the existing callback passed to `PiPStashHandleInteractionSurface`:

```swift
onHoverChanged: { hovering in
    isHovering = hovering
    onHoverChanged(hovering)
}
```

Keep the chevron, material, content shape, and accessibility hiding unchanged.

- [ ] **Step 4: Run the SwiftUI and handle regression tests**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PiPChromeViewTests|PiPStashHandleInteractionTests|OnboardingTests|AppMetadataTests'
```

Expected: all selected tests pass; hover callbacks are neither swallowed nor duplicated.

- [ ] **Step 5: Commit the SwiftUI surface adoption**

```sh
git add Sources/Perch/Views/PerchMark.swift Sources/Perch/Views/OnboardingView.swift Sources/Perch/Views/SettingsView.swift Sources/Perch/Views/PiPStashHandleView.swift Tests/PerchTests/PiPStashHandleInteractionTests.swift
git commit -m "Use Perch mark across app surfaces"
```

### Task 3: Render and Animate the Stateful Menu-Bar Mark

**Files:**
- Modify: `Sources/Perch/Platform/StatusItemGlyphPolicy.swift`
- Modify: `Sources/Perch/Platform/StatusItemMotionPolicy.swift`
- Modify: `Sources/Perch/Platform/StatusItemController.swift`
- Test: `Tests/PerchTests/StatusItemGlyphPolicyTests.swift`
- Test: `Tests/PerchTests/StatusItemMotionPolicyTests.swift`

**Interfaces:**
- Produces: `StatusItemGlyphPolicy.makeImage(for:separation:verticalOffset:) -> NSImage`
- Produces: `StatusItemMotionPolicy.hoverSeparation(reducesMotion:) -> CGFloat`
- Consumes: existing `StatusItemGlyph`, runtime publishers, morph pulse, and summon nod.

- [ ] **Step 1: Replace symbol-name assertions with failing image-contract tests**

Delete the four `systemSymbolName` assertions from `StatusItemGlyphPolicyTests.swift` and add:

```swift
func testEveryGlyphRendersAsANonemptyTemplateImage() {
    for glyph in [
        StatusItemGlyph.visible,
        .stashed,
        .loading,
        .needsSignIn,
    ] {
        let image = StatusItemGlyphPolicy.makeImage(for: glyph)
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}

func testHoveredVisibleMarkKeepsItsCanvasSize() {
    let resting = StatusItemGlyphPolicy.makeImage(for: .visible)
    let hovered = StatusItemGlyphPolicy.makeImage(for: .visible, separation: 1.5)
    XCTAssertEqual(resting.size, hovered.size)
    XCTAssertTrue(hovered.isTemplate)
}
```

Add to `StatusItemMotionPolicyTests.swift`:

```swift
XCTAssertEqual(StatusItemMotionPolicy.hoverSeparation(reducesMotion: false), 1.5)
XCTAssertEqual(StatusItemMotionPolicy.hoverSeparation(reducesMotion: true), 0)
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'StatusItemGlyphPolicyTests|StatusItemMotionPolicyTests'
```

Expected: compilation fails because the separation overload and `hoverSeparation` do not exist.

- [ ] **Step 3: Draw stateful template images**

Remove `StatusItemGlyph.systemSymbolName`. Update `makeImage` to accept `separation: CGFloat = 0` before `verticalOffset`, create a fixed 18-by-18 point `NSImage`, and draw two rounded rectangle paths centered in that canvas. Use these state treatments:

```swift
switch glyph {
case .visible:
    drawLayers(separation: separation, dashed: false, compressed: false)
case .stashed:
    drawLayers(separation: 0, dashed: false, compressed: true)
case .loading:
    drawLayers(separation: separation, dashed: true, compressed: false)
case .needsSignIn:
    drawLayers(separation: separation, dashed: false, compressed: false)
    drawPersonBadge()
}
```

Keep drawing helpers private to `StatusItemGlyphPolicy`; use `NSBezierPath(roundedRect:xRadius:yRadius:)`, a 1.25-point stroke, round joins, and monochrome `NSColor.labelColor`. Apply `verticalOffset` while constructing the layer rectangles instead of redrawing an already-rendered image. Set `image.isTemplate = true` after drawing.

In `StatusItemMotionPolicy`, add:

```swift
static let markHoverSeparation: CGFloat = 1.5

static func hoverSeparation(reducesMotion: Bool) -> CGFloat {
    reducesMotion ? 0 : markHoverSeparation
}
```

- [ ] **Step 4: Install lifecycle-safe pointer tracking**

In `StatusItemController`, store `private var hoverTrackingArea: NSTrackingArea?`. After configuring the status button, install an `.inVisibleRect`, `.mouseEnteredAndExited`, `.activeAlways` tracking area owned by the controller.

Add Objective-C event handlers:

```swift
@objc func mouseEntered(with event: NSEvent) {
    guard let button = statusItem.button, let glyph = currentGlyph else { return }
    let separation = StatusItemMotionPolicy.hoverSeparation(reducesMotion: reducesMotion())
    button.image = StatusItemGlyphPolicy.makeImage(for: glyph, separation: separation)
    if separation > 0 { playMorphPulse(on: button) }
}

@objc func mouseExited(with event: NSEvent) {
    guard let button = statusItem.button, let glyph = currentGlyph else { return }
    button.image = StatusItemGlyphPolicy.makeImage(for: glyph)
}
```

Remove the tracking area in `deinit` when the button and area still exist. Preserve click routing, state-change pulse, nod cancellation, accessibility labels, and status visibility publishers.

- [ ] **Step 5: Run menu-bar policy and controller regression tests**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'StatusItemGlyphPolicyTests|StatusItemMotionPolicyTests|RuntimeActivationAndMenuBarTests|StatusItemEventRouterTests'
```

Expected: all selected tests pass; every glyph is a template image and state precedence is unchanged.

- [ ] **Step 6: Commit the menu-bar mark**

```sh
git add Sources/Perch/Platform/StatusItemGlyphPolicy.swift Sources/Perch/Platform/StatusItemMotionPolicy.swift Sources/Perch/Platform/StatusItemController.swift Tests/PerchTests/StatusItemGlyphPolicyTests.swift Tests/PerchTests/StatusItemMotionPolicyTests.swift
git commit -m "Animate Perch mark in the menu bar"
```

### Task 4: Full Verification and Visual Inspection

**Files:**
- Modify only files needed to fix regressions found by the commands below.

**Interfaces:**
- Consumes: all completed tasks.
- Produces: a verified `dist/Perch.app` with one running process.

- [ ] **Step 1: Run formatting and diff checks**

Run:

```sh
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional task changes remain.

- [ ] **Step 2: Run the complete Swift test suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: exit code 0 with all tests passing.

- [ ] **Step 3: Build, launch, and verify the staged app**

After confirming no unsaved work is open in a running Perch instance, run:

```sh
./script/build_and_run.sh --verify
```

Expected: `Verified .../dist/Perch.app` and exactly one `Perch` process.

- [ ] **Step 4: Inspect interaction-triggered motion**

Verify manually:

- Recent Pages mark retains its current separation feel and 28-point hit target.
- Onboarding and Settings marks animate only while hovered.
- Edge-handle mark follows the existing hover/reveal interaction while the chevron and restore behavior remain intact.
- Menu-bar mark is legible in light and dark menu bars, preserves all four states, separates on hover, pulses on state change, and nods on shortcut summon.
- With Reduce Motion enabled, state cues remain visible and all geometric transitions resolve without animation.
- The `.icns` app icon remains unchanged.

- [ ] **Step 5: Record the verified final state**

Run `git status --short` and record the exact commit IDs produced by Tasks 1–3. If verification required a fix, return to the task that owns that file, repeat its focused test cycle, and amend that task with a new focused commit. Do not create an empty verification commit.
