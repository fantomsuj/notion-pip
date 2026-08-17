# Animated Perch Mark Design

## Goal

Turn the layered-card motion used by the Recent Pages toolbar control into Perch's consistent animated identity. Motion is interaction-triggered, never a continuous idle loop, and preserves the meaning of stateful controls.

## Visual Language

The shared mark is two overlapping rounded rectangles. At rest they read as a compact stack. In response to interaction, the layers separate slightly along their existing diagonal and settle back with the same quick ease-out character as the current Recent Pages control.

The mark must remain legible as a monochrome template at menu-bar size and as a semantic foreground-style SwiftUI view. It does not reproduce the detailed document lines or sparkle from the large app icon at small sizes. The existing static app icon remains unchanged because macOS does not support an animated Finder or bundle icon, and its layered documents already match the mark conceptually.

## Surfaces

### Recent Pages toolbar control

Replace the control's private stacked-rectangle drawing with the shared mark while preserving its current dimensions, hit target, accessibility label, hover distance, duration, and behavior.

### Onboarding

Replace the generic `rectangle.on.rectangle` symbol in the Perch header with the shared mark. It separates on pointer hover and otherwise rests quietly.

### Settings

Add the shared mark beside the Perch identity in the About section. The mark responds to pointer hover without changing the form's structure or making the section visually dominant.

### Edge handle

Use the shared mark in place of the generic overlapping-rectangle symbol. Tie separation to the handle's existing hover/reveal interaction so it reinforces the same behavior without adding another gesture or timer. Preserve the chevron and the handle's restore/recent-pages semantics.

### Menu bar

Render a monochrome two-layer Perch mark suitable for `NSStatusItem`. Preserve the existing states:

- visible: normal overlapping layers;
- stashed or unavailable: layers compress toward the screen edge;
- loading: a restrained dashed treatment;
- sign-in required: a small person badge or equivalent state cue that remains readable at status-bar size.

Pointer hover briefly separates the layers. A state change uses the existing short morph pulse, and shortcut summon keeps the existing nod. These effects compose around the mark rather than replacing its state information.

## Component Boundaries

Create one SwiftUI `PerchMark` view responsible only for drawing the two layers and applying a supplied separation value. A small pure motion policy maps interaction state and Reduce Motion to separation and timing. Existing controls own their pointer or presentation state and pass intent to the mark.

Keep AppKit menu-bar rendering separate in `StatusItemGlyphPolicy`: it produces template images for the same two-layer geometry and state variants. `StatusItemController` continues to own status-item events and event animations. Sharing numeric design constants is acceptable; coupling SwiftUI view state to AppKit is not.

## Motion and Accessibility

- Motion occurs only on hover, state change, shortcut summon, or an existing reveal interaction.
- There is no idle loop, repeating task, or background animation timer.
- When Reduce Motion is enabled, all geometric transitions resolve immediately to a stable, legible mark. State differences remain visible without motion.
- Existing accessible labels, help text, button hit targets, keyboard behavior, and pointer actions remain unchanged.
- Decorative mark instances are hidden from accessibility when adjacent text already names Perch.

## Error and Lifecycle Handling

The feature introduces no persistence, network work, or recoverable failure state. Menu-bar hover tracking must be installed and removed with the status-item button lifecycle, and any transient animation task must be cancellable when a newer interaction supersedes it or the controller is released.

## Testing

- Extend pure motion-policy tests for idle, hover, and Reduce Motion values.
- Extend status-item glyph-policy tests for every presentation/session/login state and verify generated images remain template images.
- Add controller-level tests where practical for hover/state transition routing without relying on animation timing.
- Keep existing toolbar, edge-handle, menu-bar accessibility, and command tests passing.
- Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- Build, launch, and process-verify with `./script/build_and_run.sh --verify`, then manually inspect the small-size menu-bar and in-app motion in both normal and Reduce Motion modes.

## Non-Goals

- Replacing the detailed `.icns` app artwork.
- Animating Finder, Login Items, or other system-owned icon presentations.
- Adding continuous ambient motion.
- Changing navigation, recent-page behavior, menu commands, app state semantics, signing, or entitlements.
