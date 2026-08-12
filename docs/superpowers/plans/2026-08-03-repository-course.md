# Perch Repository Course Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete mixed-audience course that explains every authored part of Perch, supports a 12-lecture learning path and a condensed presentation, and equips maintainers to make verified changes.

**Architecture:** Focused Markdown documents under `docs/course/` form one learning system. Numbered lectures provide the narrative; shared architecture, glossary, change, presentation, and exhaustive file-atlas documents provide reference paths. The checked-out source is authoritative, and concrete claims link to files and tests.

**Tech Stack:** Markdown, Mermaid, Swift 6.2, Swift Package Manager, SwiftUI, AppKit, WebKit, SwiftData, structured concurrency, OSLog, Security/Keychain, Carbon, TypeScript 7, Tiptap 3, esbuild, Node test runner, happy-dom, shell scripting, macOS app bundles, entitlements, and ad-hoc signing.

## Global Constraints

- Preserve the dirty worktree; stage only course files.
- Distinguish committed architecture from uncommitted work present during production.
- Do not modify product code, dependencies, generated assets, signing, entitlements, or system configuration.
- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Treat the all-Spaces panel and accessory activation policy as intentional.
- Use repository-relative Markdown links.
- Never request Notion passwords, cookies, or tokens.
- Classify .build, dist, and node_modules as artifact groups rather than inventorying their contents.
- Label window-server, Spaces, focus, login-session, and Launch Services behavior as manually verified.
- Run the full Swift and web checks specified in Task 13.

---

## Files to Create

| File | Responsibility |
|---|---|
| `docs/course/README.md` | Outcomes, prerequisites, navigation, learning paths |
| `docs/course/01-product-and-user-experience.md` | Product intent and user journeys |
| `docs/course/02-repository-and-technology-stack.md` | Topology, stack, build, artifacts |
| `docs/course/03-application-lifecycle.md` | Startup, app lifecycle, concurrency, termination |
| `docs/course/04-composition-and-runtime.md` | Composition, runtime, controllers, state |
| `docs/course/05-panel-stashing-and-controls.md` | Panel, geometry, stash, controls |
| `docs/course/06-webkit-notion-session.md` | WebKit, Notion session, navigation, restoration |
| `docs/course/07-domain-modeling-and-policies.md` | Values, validation, policies, retries |
| `docs/course/08-persistence-and-restoration.md` | SwiftData, migrations, repositories |
| `docs/course/09-quick-capture-editor-bridge.md` | Tiptap, bridge, autosave, conflicts |
| `docs/course/10-notion-api-and-delivery.md` | Credentials, API, conversion, delivery |
| `docs/course/11-views-settings-and-state.md` | Views, presenters, commands, state |
| `docs/course/12-testing-debugging-and-change-workflow.md` | Tests, debugging, build, guided changes |
| `docs/course/ARCHITECTURE_MAP.md` | Six runtime-flow diagrams and prose |
| `docs/course/FILE_ATLAS.md` | One entry per repository-owned file |
| `docs/course/PRESENTER_GUIDE.md` | Full-course delivery guidance |
| `docs/course/CONDENSED_TALK.md` | 60–90 minute presentation |
| `docs/course/CHANGE_GUIDE.md` | Layer selection and maintenance playbook |
| `docs/course/GLOSSARY.md` | Beginner definitions with repo examples |

Every lecture must contain these exact H2 sections: Learning objectives; Before you begin; Foundation; Repository tour; Runtime trace; Deep dive; Common misconceptions and failure modes; Presenter notes; Knowledge check; Hands-on exercise; Recap. Each includes duration, source links, answers or expected observations, and explicit manual-verification labels.

---

### Task 1: Snapshot the source and create the syllabus

**Files:**
- Create: `docs/course/README.md`
- Create: `.context/course-source-files.txt` and `.context/course-source-snapshot.txt`; do not commit them

**Interfaces:**
- Consumes: approved course design
- Produces: course navigation and canonical file inventory

- [ ] Record `git rev-parse HEAD`, `git status --short`, and `git log -12 --oneline --decorate` in `.context/course-source-snapshot.txt`.
- [ ] Build `.context/course-source-files.txt` from the sorted union of `git ls-files` and `git ls-files --others --exclude-standard`.
- [ ] Write the syllabus with six acceptance outcomes, required/helpful prerequisites, complete/fast/presenter paths, all document links and durations, source-snapshot note, exact build/test commands, and safety notes.
- [ ] Verify each of the 18 planned course filenames appears in `README.md` and `git diff --check -- docs/course/README.md` passes.
- [ ] Commit only `README.md` with message `docs: add Perch course syllabus`.

### Task 2: Create shared vocabulary and architecture

**Files:**
- Create: `docs/course/GLOSSARY.md`
- Create: `docs/course/ARCHITECTURE_MAP.md`

**Interfaces:**
- Consumes: manifests and declarations from all production layers
- Produces: terminology and six canonical flows used by all lectures

- [ ] Inventory Swift declarations with `rg` and TypeScript exports with `rg` into .context notes.
- [ ] Write alphabetized glossary entries for Swift/concurrency, AppKit/SwiftUI, WebKit/bridge, SwiftData/reliability, and Tiptap/Notion API; every entry links a concrete repo example.
- [ ] Write the subsystem/ownership map and Mermaid plus prose flows for startup, page activation, stash/restore, capture delivery, termination/autosave, and settings propagation.
- [ ] Verify `ARCHITECTURE_MAP.md` contains at least six `^```mermaid$` blocks and each required flow phrase; verify every named type exists in source.
- [ ] Commit both files with `docs: map Perch architecture and vocabulary`.

### Task 3: Write Lectures 1–2

**Files:**
- Create: `docs/course/01-product-and-user-experience.md`
- Create: `docs/course/02-repository-and-technology-stack.md`

**Interfaces:**
- Consumes: README, AGENTS, Package.swift, package files, tsconfig, entitlements, build script, and current product docs
- Produces: shared product and repository model

- [ ] Read every consumed file completely; record verified product, requirement, layout, build, signing, and artifact facts.
- [ ] Write Lecture 1 covering the notebook metaphor, user journeys, accessory/no-Dock behavior, all-Spaces panel, live Notion view, switching, stashing, sizing, Quick Capture, optional token, and user-action map.
- [ ] Write Lecture 2 covering every root area, SwiftPM targets/resources, web toolchain/generated assets, entitlements, staging, signing, Launch Services, modes, tests, and a repository tree.
- [ ] Run the shared H2-section check against both files and verify every linked path exists.
- [ ] Commit with `docs: teach product and repository foundations`.

### Task 4: Write Lectures 3–4

**Files:**
- Create: `docs/course/03-application-lifecycle.md`
- Create: `docs/course/04-composition-and-runtime.md`

**Interfaces:**
- Consumes: all App sources, app-facing factories/presenters, runtime/command/termination tests
- Produces: lifecycle and dependency models

- [ ] Trace startup, URL-open buffering, state observation, degraded startup, and termination from source and tests.
- [ ] Write Lecture 3: executable entry, NSApplication/delegate, accessory policy, URL handling, signposts, termination, MainActor, actors/tasks, and Sendable; trace `PerchApp.main()` through the event loop.
- [ ] Write Lecture 4: AppComposition order, protocols, relays, AppRuntime facade/extensions, controller observation, lazy presenters, degraded persistence, and an owner/lifetime/isolation/consumer/failure table.
- [ ] Verify named symbols with `rg` and run the shared H2-section check.
- [ ] Commit with `docs: explain lifecycle and runtime composition`.

### Task 5: Write Lectures 5–6

**Files:**
- Create: `docs/course/05-panel-stashing-and-controls.md`
- Create: `docs/course/06-webkit-notion-session.md`

**Interfaces:**
- Consumes: panel/window/shortcut/status/WebKit source, policies, related views/tests, handoff protocol, manual matrix
- Produces: native panel and embedded-Notion models

- [ ] Read the complete panel, geometry, stash, shortcut, status, WebKit, navigation, editor-selection, drop, and related test files; record state machines and manual-only assertions.
- [ ] Write Lecture 5: NSPanel, roles, collection behavior, activation/focus, frame/stash policies, handle/drag, menu fallback, shortcut, size presets, and stash-drag-restore trace.
- [ ] Write Lecture 6: single WKWebView, configuration, navigation validation, resolution/login, activity, snapshots, restoration/scroll, eviction, delegates, drops, state diagram, trust table.
- [ ] Verify manual limitations are explicit, matching tests are linked, and shared sections exist.
- [ ] Commit with `docs: teach panel behavior and embedded Notion`.

### Task 6: Write Lectures 7–8

**Files:**
- Create: `docs/course/07-domain-modeling-and-policies.md`
- Create: `docs/course/08-persistence-and-restoration.md`

**Interfaces:**
- Consumes: every Domain/Persistence source and matching test
- Produces: pure-policy and durable-state models

- [ ] Build a .context matrix with one row per source: types, invariants, consumers, representation, isolation, tests.
- [ ] Write Lecture 7: value semantics, page references, URL routing, working-set/history/matching, panel sizes, capture/export, delivery, retry/retention, destinations, JSON, exact security invariants.
- [ ] Write Lecture 8: SwiftData models, schema/migrations, container, model actors, page/restoration/capture/draft/destination/settings repos, claims/transitions/retention, degradation, schema and lifecycle diagrams.
- [ ] For every Domain/Persistence Swift file, require its basename in one of the two lectures; run shared-section validation.
- [ ] Commit with `docs: explain domain policies and persistence`.

### Task 7: Write Lectures 9–10

**Files:**
- Create: `docs/course/09-quick-capture-editor-bridge.md`
- Create: `docs/course/10-notion-api-and-delivery.md`

**Interfaces:**
- Consumes: native editor/bridge, all web editor source/tests/resources, API/delivery services, vault, capture persistence/domain/tests
- Produces: authoring-to-delivery explanation

- [ ] Trace keystroke-to-Notion behavior, protocol shapes, revisions, state transitions, retries, and destinations into .context notes.
- [ ] Write Lecture 9: ownership, resources, Tiptap/ProseMirror, bridge validation, weak handler, bootstrap, formatting/blocks, debounce/ack, transitions, revisions/conflicts/recovery, generated assets, edit-to-save sequence.
- [ ] Write Lecture 10: Keychain, connection/search, transport/errors, destinations, block conversion, enqueue/scheduler/recovery, claims/backoff, 401/409/429/5xx, ambiguity, idempotency, manual append, child and data-source pages.
- [ ] Verify all state/error/destination terms occur, linked paths exist, and shared sections exist.
- [ ] Commit with `docs: teach capture bridge and delivery pipeline`.

### Task 8: Write Lectures 11–12

**Files:**
- Create: `docs/course/11-views-settings-and-state.md`
- Create: `docs/course/12-testing-debugging-and-change-workflow.md`

**Interfaces:**
- Consumes: every View, view-facing controller/presenter, every test/support file, build script, entitlements, manual matrix, signposts
- Produces: UI/state map and capstone lecture

- [ ] Build a .context matrix for each view's inputs/actions/owner/tests and each test's behavior/category/support.
- [ ] Write Lecture 11: all view groups, hosting, bindings, commands, chrome/hover/switcher, URL input, capture/outbox/conflict, settings/shortcut/sizes, service/developer status, and three event traces.
- [ ] Write Lecture 12: Swift Testing, fakes, independence, in-memory SwiftData, WebKit support, Node/DOM tests, manual matrix, logs/signposts, build/bundle/entitlements/sign/launch, disciplined change loop, and three guided investigations.
- [ ] Require every Views basename in Lecture 11; verify all automated/manual/build topics and shared sections.
- [ ] Commit with `docs: teach UI state testing and maintenance`.

### Task 9: Write the change guide

**Files:**
- Create: `docs/course/CHANGE_GUIDE.md`

**Interfaces:**
- Consumes: lecture patterns, project instructions, protocol seams, verification constraints
- Produces: standalone maintainer playbook

- [ ] Write `Choosing the owning layer` for Domain, Persistence, Services, App, Platform, Views, and Web with inputs, outputs, isolation, examples, tests, and exclusions.
- [ ] Write `Safe change workflow`, `Diagnostic playbook`, and `Verification ladder` with exact dirty-worktree, tracing, tests, implementation, full-check, and manual steps plus concurrency/migration/bridge/WebKit/API/signing/accessory-app branches.
- [ ] Write `Worked scenarios` for a beginner policy edit, intermediate persisted setting, and advanced bridge extension, including discovery commands, files, invariants, tests, and verification.
- [ ] Verify all five headings, all seven layers, and three scenarios exist; check links.
- [ ] Commit with `docs: add Perch change playbook`.

### Task 10: Build the exhaustive file atlas

**Files:**
- Create: `docs/course/FILE_ATLAS.md`
- Refresh: `.context/course-source-files.txt`; do not commit

**Interfaces:**
- Consumes: every repository-owned file and lecture mapping
- Produces: exact exhaustive coverage

- [ ] Refresh the sorted union of tracked and non-ignored untracked paths.
- [ ] Add one exact backticked-path row per inventory item, grouped by root/config, Swift layer, resources, Swift tests/support, web source/tests/build, Support/script, current docs, historical specs/plans, and course docs.
- [ ] Give every row role, types/artifacts, consumer, lecture, and tests or Manual/generated/reference only; explain excluded artifact groups and individually include checked-in editor.js.
- [ ] For each inventory line, run `rg -Fq` for its backticked exact path in FILE_ATLAS; add missing rows until exit status is zero.
- [ ] Commit with `docs: catalog every repository file`.

### Task 11: Write the presenter guide

**Files:**
- Create: `docs/course/PRESENTER_GUIDE.md`

**Interfaces:**
- Consumes: all lectures and references
- Produces: full-course facilitation plan

- [ ] Define six-session, twelve-session, and two-day schedules with durations, breaks, prerequisites, exercises, and demos.
- [ ] For Lectures 1–12 add hook, takeaway, hard concept, diagram cue, code-tour entry, demo, audience question, misconception, debrief, transition, optional cut.
- [ ] Add environment/privacy/accessibility preparation and recovery for build, login, network, WebKit, shortcut, and focus demo failures.
- [ ] Verify each numbered lecture and all three schedule formats appear.
- [ ] Commit with `docs: add full-course presenter guide`.

### Task 12: Write the condensed talk

**Files:**
- Create: `docs/course/CONDENSED_TALK.md`

**Interfaces:**
- Consumes: product, architecture, four main flows, reliability, change and presenter guides
- Produces: self-contained 60–90 minute talk

- [ ] Write 18–24 slide-equivalent sections totaling 75 minutes, with marked cuts to 60 and extensions to 90; cover product, stack, architecture, startup, panel/WebKit, persistence, bridge, delivery, tests, changes.
- [ ] Give each section elapsed target, visible content, spoken narrative, source links, diagram cue, and demo or No demo; include product and code-flow demos.
- [ ] Add five checkpoints with answers, four closing ideas, and audience-specific next-study links.
- [ ] Verify 60/75/90 timings and every required topic appear; check links.
- [ ] Commit with `docs: add condensed architecture talk`.

### Task 13: Cross-link and verify the complete course

**Files:**
- Modify: `docs/course/README.md`
- Modify: `docs/course/FILE_ATLAS.md`
- Modify: any `docs/course/*.md` with a verified defect

**Interfaces:**
- Consumes: complete course and working checkout
- Produces: coherent, source-backed, navigable, verified final course

- [ ] Refresh the inventory and repeat the exact atlas check, adding final presenter/talk/course rows until none are missing.
- [ ] Extract every local Markdown target, resolve relative to its document, strip anchors, and fix missing targets individually with apply_patch until none remain.
- [ ] Validate all 11 shared H2 headings and an answer/expected-observation section in each lecture.
- [ ] Scan for `T[B]D|T[O]DO|F[I]XME|implement[ ]later|fill[ ]in[ ]details|add[ ]appropriate|similar[ ]to[ ]task`; fix every occurrence.
- [ ] Verify every backticked concrete Swift/TypeScript type in maps and traces with rg; remove unsupported claims or label inference.
- [ ] Run `git diff --check -- docs/course` and verify Mermaid blocks exist.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. Expected: pass; if pre-existing code fails, preserve it and report exact failures separately.
- [ ] Run `npm test` and `npm run typecheck`. Expected: pass. Do not run `npm run build:editor`.
- [ ] Compare final files with all design deliverables and six acceptance criteria; confirm staged paths contain only `docs/course/*`.
- [ ] Commit final corrections with `docs: complete and verify Perch course`.
