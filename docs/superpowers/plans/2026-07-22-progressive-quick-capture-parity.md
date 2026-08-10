# Progressive Quick Capture Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the durable local Quick Capture editor Notion-like focus, block commands, formatting, autosave, note lifecycle, and accessibility behavior.

**Architecture:** Preserve `CaptureEditorSession`, the typed WebKit bridge, revisioned SwiftData persistence, and transition gate. Add pure TypeScript interaction helpers around the existing Tiptap editor, render contextual browser UI from a data-driven command catalog, flatten the native/web shell, and extend deterministic Markdown export for the one new persisted node family: task lists.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, SwiftData, XCTest, TypeScript 7, Tiptap 3.28, Node test runner, esbuild

## Global Constraints

- Quick Capture remains a local-first durable draft editor and does not create a remote Notion page on launch.
- Preserve the existing 300 ms autosave debounce, exact-request retry, revision, conflict, stash/restore, and relaunch semantics.
- Remove the manual Save affordance; visible `New note` continues to use the existing durable stash transition.
- Initial supported blocks are text, H1-H3, bullet list, numbered list, task list, quote, code block, and divider.
- Do not add uploads, images, files, embeds, databases, collaboration, comments, mentions, AI, or drag-and-drop block handles.
- Use `Untitled` only as display fallback; persist an empty title as an empty string.
- Preserve concurrent unrelated PiP typing/chrome work in the shared worktree.

---

### Task 1: Interaction model and command catalog

**Files:**
- Modify: `Web/QuickCaptureEditor/editor.ts`
- Modify: `Web/QuickCaptureEditor/editor.test.ts`

**Interfaces:**
- Produces: `BLOCK_COMMANDS`, `filterBlockCommands(query)`, `displayTitle(title)`, `routeTitleKey(input)`, and `routeOverlayKey(input)`.
- Consumes: no browser DOM; helpers remain deterministic Node-testable functions.

- [ ] **Step 1: Add failing unit tests for command filtering and keyboard routing**

Add tests that require stable command ordering, aliases, case-insensitive filtering, `Untitled` fallback, Enter/Tab/ArrowDown title routing, and layered slash-menu Escape/arrow/Enter routing. Representative assertions:

```ts
assert.deepEqual(filterBlockCommands("head").map((item) => item.id), ["heading1", "heading2", "heading3"]);
assert.deepEqual(filterBlockCommands("todo").map((item) => item.id), ["taskList"]);
assert.equal(displayTitle("  "), "Untitled");
assert.equal(routeTitleKey({ key: "Enter", atBoundary: false }), "focusBody");
assert.equal(routeOverlayKey({ key: "Escape", isOpen: true }), "dismiss");
```

- [ ] **Step 2: Verify the focused test fails for missing exports**

Run `npm ci && npm test` and confirm the new tests fail because the helpers are not exported.

- [ ] **Step 3: Implement the pure interaction model**

Define a typed catalog with IDs, labels, aliases, and Tiptap command names. Normalize queries with `trim().toLocaleLowerCase()` and return catalog order. Return explicit routing outcomes rather than touching DOM from helpers.

```ts
export type BlockCommandID = "text" | "heading1" | "heading2" | "heading3" |
  "bulletList" | "orderedList" | "taskList" | "quote" | "codeBlock" | "divider";
export type OverlayRoute = "previous" | "next" | "select" | "dismiss" | "none";
export type TitleRoute = "focusBody" | "none";
```

- [ ] **Step 4: Run Node tests and typecheck**

Run `npm test && npm run typecheck`; expect zero failures and zero type errors.

- [ ] **Step 5: Commit the interaction model**

Commit only the two Task 1 files with `feat: add quick capture interaction model`.

---

### Task 2: Notion-like page shell and launch focus

**Files:**
- Modify: `Sources/Perch/Resources/QuickCapture/index.html`
- Modify: `Sources/Perch/Resources/QuickCapture/composer.css`
- Modify: `Web/QuickCaptureEditor/editor.ts`
- Modify: `Tests/PerchTests/CaptureWebViewIntegrationTests.swift`
- Modify: `Sources/Perch/Views/QuickCaptureView.swift`

**Interfaces:**
- Consumes: title routing helpers from Task 1.
- Produces: stable selectors `#page`, `#title`, `#editor`, `#status`, `#retry`, `#new-note`, `#slash-menu`, and `#format-toolbar`.

- [ ] **Step 1: Add failing WebKit focus and accessibility tests**

Verify an empty authoritative draft focuses `#title`, a populated draft focuses `.tiptap` at its end, Enter/Tab from title focus `.tiptap`, and the generated editor has `role="textbox"`, `aria-label="Note content"`, and `aria-multiline="true"`.

- [ ] **Step 2: Run the focus tests and confirm behavioral failures**

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CaptureWebViewIntegrationTests` and confirm the new focus assertions fail.

- [ ] **Step 3: Flatten the HTML and SwiftUI shell**

Replace the always-visible formatting row and Save/Stash footer with a semantic page shell containing the title, editor, single status, Retry, `New note`, and hidden overlay containers. Remove the duplicate SwiftUI heading/status and the rounded card stroke while retaining native conflict recovery.

- [ ] **Step 4: Implement title/body focus continuity**

Configure Tiptap `editorProps.attributes`, focus after the authoritative ready snapshot is installed, and route Enter/Tab/ArrowDown from the title into the body. Route ArrowUp from the start of the first body block back to the title. Do not steal focus when installing a newer snapshot for the same active draft.

- [ ] **Step 5: Apply the restrained page styling**

Use an unboxed canvas, large borderless title, readable body rhythm, quiet header actions, visible keyboard focus, automatic light/dark colors, and responsive overlay widths. Keep system typography per `.impeccable.md`.

- [ ] **Step 6: Rebuild and run focused tests**

Run `npm run build:editor` followed by the focused WebKit tests; expect all focus and accessibility assertions to pass.

- [ ] **Step 7: Commit the page shell slice**

Commit the Task 2 files plus generated `editor.js` with `feat: make quick capture a focused page canvas`.

---

### Task 3: Slash command menu and richer blocks

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Modify: `Web/QuickCaptureEditor/editor.ts`
- Modify: `Web/QuickCaptureEditor/editor.test.ts`
- Modify: `Sources/Perch/Resources/QuickCapture/composer.css`
- Modify: `Sources/Perch/Resources/QuickCapture/editor.js`
- Modify: `Tests/PerchTests/CaptureWebViewIntegrationTests.swift`

**Interfaces:**
- Consumes: `BLOCK_COMMANDS`, `filterBlockCommands`, overlay key routing.
- Produces: `slashQueryAtSelection(editorState)`, `executeBlockCommand(editor, id)`, task-list schema, and keyboard-accessible `#slash-menu` listbox.

- [ ] **Step 1: Add official Tiptap extensions**

Install exact `3.28.0` versions of `@tiptap/extension-placeholder`, `@tiptap/extension-task-list`, and `@tiptap/extension-task-item` using npm so the lockfile is updated deterministically.

- [ ] **Step 2: Add failing unit tests for slash detection and command dispatch**

Cover an empty slash, filtered `/hea`, non-leading slash text, command lookup, and unknown IDs. Use a fake chain to verify the exact Tiptap command sequence.

- [ ] **Step 3: Implement slash detection and block commands**

Recognize `/query` only from the start of the current text block through the collapsed selection. Delete that range before applying the selected command. Map catalog IDs to `setParagraph`, `toggleHeading`, list commands, `toggleTaskList`, `toggleBlockquote`, `toggleCodeBlock`, and `setHorizontalRule`.

- [ ] **Step 4: Render and control the slash menu**

Open on a valid slash query, filter on editor transactions, retain a bounded active index, handle Up/Down/Enter/Escape without moving the document selection, populate `role="option"` rows, and keep `aria-activedescendant` current. Close after selection, invalid query, focus loss, or Escape.

- [ ] **Step 5: Add integration coverage**

Use real WebKit key events to verify the menu opens, filters to headings, keyboard selection produces an H2, Escape dismisses without deleting text, Markdown markers create expected nodes, and task items autosave through the existing bridge.

- [ ] **Step 6: Run Node, typecheck, rebuild, and focused WebKit tests**

Run `npm test && npm run typecheck && npm run build:editor`, then the focused Swift integration suite. Expect all commands to pass.

- [ ] **Step 7: Commit the slash-command slice**

Commit Task 3 files with `feat: add quick capture slash commands`.

---

### Task 4: Contextual formatting and link paste

**Files:**
- Modify: `Web/QuickCaptureEditor/editor.ts`
- Modify: `Web/QuickCaptureEditor/editor.test.ts`
- Modify: `Sources/Perch/Resources/QuickCapture/index.html`
- Modify: `Sources/Perch/Resources/QuickCapture/composer.css`
- Modify: `Sources/Perch/Resources/QuickCapture/editor.js`
- Modify: `Tests/PerchTests/CaptureWebViewIntegrationTests.swift`

**Interfaces:**
- Produces: `FormattingCommand`, `formattingState(editor)`, `isLinkPaste(selection, text)`, contextual `#format-toolbar`.

- [ ] **Step 1: Add failing formatting and URL tests**

Verify active-state projection for bold, italic, underline, strike, code, and link; accept only `http:` and `https:` URL text over a non-empty text selection; reject empty selections and unsafe schemes.

- [ ] **Step 2: Implement formatting helpers and commands**

Project Tiptap `isActive` state into a plain object. Dispatch the six formatting actions through a focused chain. Configure StarterKit link behavior to avoid auto-opening inside the local editor.

- [ ] **Step 3: Implement the contextual toolbar**

Show only for a non-empty text selection while the editor has focus. Anchor it above the selection, set `aria-pressed`, prevent pointer-down focus loss, refocus after action, and close on collapsed selection, Escape, or blur.

- [ ] **Step 4: Implement URL-over-selection paste**

Intercept paste only when the clipboard contains one safe URL and the selection is non-empty, then apply a link mark without replacing the selected text. Leave all other paste behavior to ProseMirror.

- [ ] **Step 5: Verify formatting behavior**

Run Node tests, typecheck, rebuild the editor, and run focused WebKit tests for toolbar visibility, pressed state, Escape, and URL paste.

- [ ] **Step 6: Commit the formatting slice**

Commit Task 4 files with `feat: add contextual quick capture formatting`.

---

### Task 5: Autosave-first note lifecycle and task export

**Files:**
- Modify: `Web/QuickCaptureEditor/editor.ts`
- Modify: `Web/QuickCaptureEditor/editor.test.ts`
- Modify: `Sources/Perch/Resources/QuickCapture/index.html`
- Modify: `Sources/Perch/Resources/QuickCapture/composer.css`
- Modify: `Sources/Perch/Resources/QuickCapture/editor.js`
- Modify: `Sources/Perch/Domain/CaptureExport.swift`
- Modify: `Tests/PerchTests/CaptureExportTests.swift`
- Modify: `Tests/PerchTests/CaptureWebViewIntegrationTests.swift`

**Interfaces:**
- Consumes: existing `EditorTransitionGate` and `stash` bridge request.
- Produces: visible `New note` action, display-only `Untitled` fallback, task-list Markdown rendering.

- [ ] **Step 1: Add failing lifecycle and export tests**

Verify no `#save` control exists, `#new-note` is enabled only when mutation is safe, activating it flushes edits before stash, the returned empty successor focuses title, and task lists export as `- [ ]` / `- [x]` Markdown with nested content indented.

- [ ] **Step 2: Wire `New note` to the existing durable transition**

Rename only the visible lifecycle action. Keep the request type and transition key as `stash` for protocol compatibility. After the authoritative successor snapshot installs, reset overlays and apply new-draft title focus.

- [ ] **Step 3: Consolidate persistence feedback**

Keep one live status region with `Saving…`, `Saved`, and concise failures. Preserve Retry for exact pending requests. Do not render revision numbers or a manual Save action.

- [ ] **Step 4: Extend deterministic Markdown export**

Render `taskList` by delegating to children and `taskItem` from its `checked` attribute. Preserve current unknown-node recovery for unsupported nodes.

- [ ] **Step 5: Run lifecycle and export verification**

Run Node tests, typecheck, editor build, `CaptureExportTests`, `CaptureEditorFlowTests`, and `CaptureWebViewIntegrationTests`. Expect zero failures.

- [ ] **Step 6: Commit the lifecycle slice**

Commit Task 5 files with `feat: finish autosaved quick note lifecycle`.

---

### Task 6: Full regression and packaged-app verification

**Files:**
- Modify only if verification exposes an in-scope defect.

**Interfaces:**
- Validates every requirement in the design spec against source and test evidence.

- [ ] **Step 1: Verify JavaScript source and generated bundle**

Run:

```sh
npm ci
npm test
npm run typecheck
npm run build:editor
git diff --exit-code -- Sources/Perch/Resources/QuickCapture/editor.js
```

If the generated-file diff exists only because the rebuilt bundle has not yet been committed, inspect it, commit it with the owning task, and rerun the diff check.

- [ ] **Step 2: Run the full Swift package suite**

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; expect all tests to pass.

- [ ] **Step 3: Verify the packaged app**

Run `./script/build_and_run.sh --verify`; expect a successful build, staged app bundle, resource checks, and signature verification.

- [ ] **Step 4: Review accessibility and scope evidence**

Re-read the design spec, confirm every requirement has a test or direct DOM/source check, verify no prohibited remote/media features or secrets were added, and run `git diff --check`.

- [ ] **Step 5: Commit any verification-only correction**

If Task 6 required an in-scope correction, commit only those files with `fix: close quick capture verification gaps`.
