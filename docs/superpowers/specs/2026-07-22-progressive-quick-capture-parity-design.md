# Progressive Quick Capture Parity Design

## Goal

Make Quick Capture feel and behave like Notion's page editor while preserving the app's defining local-first guarantees: instant launch, durable offline drafts, continuous autosave, conflict recovery, stashing, and later delivery.

The result is a focused block editor, not a remote Notion page. It does not require a network connection or personal integration token.

## Product Principles

- Content is primary; editor chrome stays quiet and contextual.
- Opening Quick Capture always leaves a caret ready for typing.
- Edits persist automatically. There is no manual-save mental model.
- Existing drafts, revisions, conflicts, stashing, restoration, and delivery remain loss-safe.
- Keyboard and VoiceOver use are first-class.
- Match documented Notion behaviors where they fit a local editor; do not imitate cloud-only features.

## Research Basis

Official Notion documentation describes pages as block canvases, `/` as the block and action menu, Markdown marker conversions, Enter and Shift-Enter behavior, Tab-based nesting, contextual text formatting, block selection, URL-over-selection linking, and automatic cloud persistence without a Save button.

Primary references:

- <https://www.notion.com/help/create-your-first-page>
- <https://www.notion.com/help/writing-and-editing-basics>
- <https://www.notion.com/help/keyboard-shortcuts>
- <https://www.notion.com/help/what-is-a-block>
- <https://www.notion.com/help/back-up-your-data>
- <https://www.notion.com/help/use-pages-offline>
- <https://www.notion.com/help/duplicate-delete-and-restore-content>

Initial title focus, Enter-to-body continuity, and empty-page persistence are parity decisions inferred from the product experience rather than exact behaviors stated by those documents.

## User Experience

### Launch and focus

- A newly created empty draft focuses the title and selects no text.
- Reopening a non-empty active draft focuses the body at its end so capture can continue immediately.
- Enter in the title moves focus to the first body block without inserting a newline.
- Arrow Down at the end of the title also moves into the body. Arrow Up at the start of the first body block moves back to the end of the title.
- Tab from the title moves into the body instead of visiting formatting controls.

### Page surface

- Remove the duplicate SwiftUI "Quick Capture" heading and outer card treatment.
- Render one seamless page canvas using system typography and automatic light/dark appearance.
- Use a large, borderless title with `Untitled` placeholder copy.
- Keep a ready empty text block below it with `Type '/' for commands` placeholder copy.
- Remove the permanently visible formatting toolbar and bordered body box.
- Show one quiet persistence status in the page header. Do not expose revision numbers.

### Block creation and transformation

Typing `/` in an empty or text block opens a compact command menu anchored near the caret. The menu supports type-to-filter, Up/Down navigation, Enter selection, and Escape dismissal. Choosing a command removes the slash query and transforms the current block while retaining focus.

The first release supports:

- Text
- Heading 1, Heading 2, Heading 3
- Bulleted list
- Numbered list
- To-do list
- Quote
- Code block
- Divider

The command catalog is data-driven so later commands do not require rewriting menu behavior.

Tiptap input rules provide Notion-compatible conversions for `#`, `##`, `###`, `-`, `*`, `+`, `1.`, `[]`, `>`, and `---` where the installed extensions support them. Enter creates the next block; Shift-Enter inserts a soft break; Tab and Shift-Tab sink and lift supported list items.

### Text formatting

- Selecting text opens a small contextual toolbar.
- Support bold, italic, underline, strikethrough, inline code, and links.
- Keyboard shortcuts remain available through Tiptap and macOS conventions.
- Pasting a URL over selected text creates a link.
- Toolbar controls expose active state with `aria-pressed` and return focus to the editor after use.

### Note lifecycle

- Remove the Save button because the editor already autosaves after a short debounce.
- Preserve the explicit flush-before-transition guarantee.
- Replace the visible `Stash` label with `New note`. Activating it durably stashes the current draft and opens a fresh local draft.
- Keep empty drafts. They appear as `Untitled` wherever a title is required.
- Keep Retry visible only when persistence or a transition needs user action.
- The window's normal close behavior hides the editor without deleting or abandoning its active draft.

### Accessibility

- The generated Tiptap surface is a named multiline textbox.
- The title is a separately named text field.
- Slash menu uses listbox/option semantics with an announced active descendant.
- Contextual formatting controls expose names, shortcuts where useful, and pressed state.
- Status changes use one polite live region.
- All commands are reachable without a pointer.
- Reduced-motion behavior remains respected.

## Architecture

### Editor interaction modules

`Web/QuickCaptureEditor/editor.ts` retains bridge, autosave, and transition orchestration. Focused exported helpers provide independently testable behavior for:

- Command catalog and slash-query filtering
- Keyboard routing between title, editor, slash menu, and contextual UI
- Slash-range detection and command execution
- Formatting active-state projection
- URL-over-selection detection
- Display-title fallback

The browser bootstrap composes those helpers with Tiptap and the existing bridge. Persistence classes are not coupled to menu or DOM state.

### Tiptap extensions

StarterKit continues to provide core blocks, history, input rules, and list behavior. Add narrowly scoped official Tiptap extensions for placeholder, underline, task list, and task item. Link remains configured through StarterKit. Custom slash-menu behavior is implemented locally because it is application interaction, not stored document data.

Task-list nodes become part of the persisted ProseMirror JSON. The Swift Markdown exporter gains explicit task-list rendering so durable export and delivery do not fall back to recovery JSON for supported content.

### DOM and styling

The packaged HTML declares the stable page shell, title, editor mount, status, retry action, new-note action, slash menu container, and contextual toolbar container. JavaScript owns dynamic menu options and toolbar state. CSS owns the restrained Notion-like page treatment, anchored overlays, focus visibility, responsive sizing, and light/dark colors.

### Native shell

`QuickCaptureView` becomes a flat WebView host with native conflict recovery below it. The native status heading is removed so the web editor is the single status surface. Window sizing remains native but is adjusted if necessary to preserve a useful writing viewport.

## Data Flow

1. The native session loads the local editor and answers `ready` with the authoritative active draft.
2. JavaScript installs the snapshot, unlocks the editor, and applies the launch-focus rule.
3. Title or document changes pass through the existing 300 ms debounced publisher.
4. Native persistence acknowledges the authoritative revision; JavaScript updates the single status region.
5. `New note` drains pending changes, sends the existing stash transition, installs the returned successor draft, and focuses its title.
6. Conflict responses keep current editor work visible and locked while native recovery choices are active.

## Failure Handling

- Autosave failures retain the exact failed request and show concise error copy with Retry.
- Slash and formatting UI never changes durable state outside normal editor transactions.
- A failed `New note` transition keeps the current draft visible and locked until the exact transition is retried or definitively rejected.
- Unsupported pasted content degrades through Tiptap's parser; the one-megabyte bridge limit remains enforced.
- Empty titles persist as empty strings internally and render as `Untitled` only at display boundaries.

## Testing

### TypeScript unit tests

- Command ordering, aliases, and filtering
- Slash-query parsing and command selection
- Keyboard routing and layered Escape handling
- Display-title fallback
- Formatting command dispatch and active-state projection
- URL-over-selection eligibility
- Existing autosave, retry, and transition behavior remains green

### WebKit integration tests

- Empty launch focuses title; populated reopen focuses body
- Enter, Tab, and Arrow transitions preserve the caret
- Slash menu opens, filters, navigates, executes, and dismisses
- Markdown marker conversions produce expected ProseMirror nodes
- Selection toolbar exposes pressed state and link behavior
- Autosave persists new supported nodes
- `New note` flushes, stashes, returns a blank draft, and focuses title
- Accessible roles and labels exist on the live generated editor DOM

### Swift tests

- Task-list export renders deterministic Markdown
- Existing capture flow, persistence, bridge validation, resource loading, recovery, and relaunch tests remain green
- Full Swift package suite and packaged-app verification run after the generated editor bundle is rebuilt

## Scope Boundaries

This pass does not implement uploads, images, files, embeds, databases, collaboration, comments, mentions, reminders, AI, synced blocks, page nesting, or complete drag-and-drop block handles. Those features require remote data, asset storage, or substantially broader selection and delivery models.

The design also does not replace the native persistence engine, bridge protocol, revision semantics, or conflict-recovery model.
