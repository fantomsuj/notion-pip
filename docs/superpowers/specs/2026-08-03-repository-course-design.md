# Notion PiP Repository Course Design

## Purpose

Create a durable, presentation-ready course that teaches the complete Notion PiP repository to a mixed audience. A learner should finish with enough conceptual grounding to explain the product and its technology, trace important runtime behavior through the code, present the architecture to others, and make focused changes safely.

The course will describe the repository as it exists in the working checkout on August 3, 2026. It will distinguish committed architecture from any uncommitted work present during course production and will not alter unrelated product code.

## Audience

The course is for a mixed audience:

- Programmers who are new to Swift and native macOS development
- Swift developers who are new to AppKit, SwiftUI, WebKit, or SwiftData
- Experienced macOS developers who want an implementation-level repository tour
- Presenters who need a concise, accurate narrative for explaining the project

Every major topic will therefore use three layers:

1. **Foundation:** the technology and vocabulary needed to understand the topic
2. **Repository tour:** the exact files, types, responsibilities, and call paths in Notion PiP
3. **Deep dive:** ownership, concurrency, persistence, failure behavior, design trade-offs, and testing seams

Readers can skip the foundation layer when they already know the technology.

## Deliverables

The course will live in `docs/course/` and contain:

- `README.md`: course landing page, outcomes, prerequisites, and learning paths
- Numbered lecture documents: the full teaching sequence
- `ARCHITECTURE_MAP.md`: subsystem boundaries and cross-layer runtime flows
- `FILE_ATLAS.md`: an exhaustive inventory of repository-owned files and their roles
- `PRESENTER_GUIDE.md`: timing, talk tracks, demonstrations, questions, and transitions
- `CONDENSED_TALK.md`: a self-contained 60–90 minute presentation version
- `CHANGE_GUIDE.md`: a practical workflow for tracing and modifying the app safely
- `GLOSSARY.md`: Swift, macOS, WebKit, persistence, editor, and Notion terminology

Exercises and presenter notes will be embedded in the lecture where they are used so the relevant explanation and activity stay together. Large generated or dependency directories such as `.build`, `dist`, and `node_modules` will be explained as build artifacts rather than inventoried file by file.

## Course Structure

### Lecture 1: Product intent and user experience

- Why Notion PiP exists and which workflows it serves
- The accessory-app model, persistent panel, edge stash, page switching, and Quick Capture
- Intentional product constraints, including all-Spaces panel behavior and no Dock presence
- A guided product demonstration and a user-action-to-subsystem map

### Lecture 2: Repository topology and technology stack

- Swift Package Manager layout and executable/test targets
- Swift 6.2, SwiftUI, AppKit, WebKit, SwiftData, OSLog, Carbon shortcuts, and Security/Keychain concepts
- TypeScript, Tiptap, esbuild, Node test runner, and generated editor assets
- How `Sources`, `Tests`, `Web`, `Support`, `script`, and `docs` relate
- How to build, test, stage, sign, launch, and verify the app

### Lecture 3: Application lifecycle and native macOS foundations

- `@main`, `NSApplication`, `NSApplicationDelegate`, and accessory activation policy
- SwiftUI views hosted inside AppKit windows
- Main-actor isolation, actors, tasks, `Sendable`, and observable state
- Startup, URL-open handling, readiness measurement, and coordinated termination
- The executable entry path from `NotionPiPApp.main()` into the running application

### Lecture 4: Composition, runtime state, and controller boundaries

- `AppComposition` as the dependency-composition root
- `AppRuntime` as the application-facing facade
- Command relays, presenters, controllers, repositories, services, and protocol seams
- State observation and propagation into SwiftUI and menu-bar surfaces
- Healthy startup versus degraded startup when persistence is unavailable

### Lecture 5: PiP panel, stashing, and global controls

- `NSPanel` construction, window roles, Spaces behavior, activation, focus, and visibility
- Panel frame and stash policies, screen geometry, saved size presets, and the edge handle
- Menu-bar control, global shortcut registration, commands, and URL/clipboard pinning
- Why one live panel and one live Notion web view are maintained
- Manual behaviors that require real-window verification

### Lecture 6: Embedded Notion and WebKit session management

- `WKWebView` configuration and the shared Notion web session
- Navigation validation, page resolution, login/session behavior, and external navigation
- Interaction snapshots, page switching, restoration, scroll fallback, and memory-pressure eviction
- Editor-activity detection, chrome behavior, drag/drop activation, and WebKit delegates
- Trust boundaries between native code and the hosted Notion application

### Lecture 7: Domain modeling, validation, and policies

- Value types and policies in `Domain`
- Canonical Notion page references and external handoff parsing
- Page-working-set, history, matching, panel-size, delivery, retry, and export models
- Why pure value semantics and policy objects are highly testable
- Security properties of URL canonicalization and bounded bridge data

### Lecture 8: SwiftData persistence and restoration

- Versioned schemas, migrations, model containers, and model actors
- Page, restoration, destination, capture, draft, and settings models
- Repository interfaces and actor isolation
- Pinned/recent working-set rules, retention, capture claims, and atomic state transitions
- Failure modes and degraded-service reporting

### Lecture 9: Quick Capture and the Swift–TypeScript bridge

- The native Quick Capture window and `CaptureEditorSession`
- Bundled HTML/CSS/JavaScript resources and the Tiptap editor
- Bridge protocol versioning, validation, request/reply routing, and weak script handlers
- Autosave debouncing, revisions, transition gates, conflict recovery, formatting, and slash commands
- Source TypeScript versus checked-in generated editor assets

### Lecture 10: Notion API, credentials, and delivery reliability

- Personal integration token lifecycle and Keychain storage
- Workspace search, destination selection, API request transport, decoding, and safe errors
- Converting editor content into Notion blocks
- Capture lifecycle, outbox records, scheduling, retries, rate limits, reconnect pauses, ambiguity, and idempotency strategy
- Differences among managed delivery, manual append, child-page creation, and data-source-page creation

### Lecture 11: Views, settings, commands, and state propagation

- SwiftUI view hierarchy and AppKit hosting/presentation
- PiP chrome, page switcher, Quick Capture, status, conflict, and settings surfaces
- Controllers for page switching, destinations, connection, sizing, hover, and status items
- User event flow from controls to runtime mutation and persistence
- Accessibility, discoverability, and resilience decisions visible in the UI layer

### Lecture 12: Testing, debugging, and making changes safely

- Swift Testing organization, fakes, protocol boundaries, and independent test design
- TypeScript unit and DOM testing with the Node test runner and `happy-dom`
- The role of manual windowing tests and why some AppKit behavior cannot be proven by unit tests
- Logs, signposts, build modes, entitlements, ad-hoc signing, and staged app verification
- A repeatable change workflow: identify the behavior, trace the flow, choose the owning layer, add a regression test, implement, and verify
- Guided change examples at beginner, intermediate, and advanced levels

## Architecture Map

The architecture material will use compact Mermaid diagrams plus prose fallbacks. It will include at least these flows:

1. Application startup and dependency composition
2. Pin or page-switch request through validation, persistence, panel presentation, and WebKit navigation
3. PiP stash and restore behavior across panel, geometry policy, handle, shortcut, and menu-bar control
4. Quick Capture editor change through the JavaScript bridge, native draft persistence, outbox enqueue, scheduler, delivery engine, and Notion API
5. Termination preparation and autosave acknowledgement
6. Settings and observable state propagation

Every diagram will name the concrete types involved and link to the lecture that explains them.

## File Atlas Coverage

`FILE_ATLAS.md` will account for every repository-owned file returned by `rg --files`, organized by responsibility rather than as one undifferentiated list. Each entry will state:

- What the file owns
- Its important types or artifacts
- What calls or consumes it
- The lecture where it is explained
- The tests that protect it, where applicable

The atlas will cover:

- Root configuration and instruction files
- App, Domain, Persistence, Platform, Services, Views, and Resources
- All Swift tests and shared test-support files
- TypeScript editor source, controllers, bridge, state, build script, and tests
- Shell build/staging logic, entitlements, and package configuration
- Product documentation, protocol notes, research notes, manual test matrices, and historical design/implementation documents

Historical specs and plans will be cataloged by feature and purpose. The course will not reteach each historical implementation step line by line when the current code is the authoritative result.

## Teaching and Presentation Format

Each lecture will include:

- Learning objectives
- Estimated duration
- Prerequisite concepts
- A plain-language opening model
- A guided code tour with stable repository-relative links
- One or more runtime traces
- Common misconceptions and failure modes
- Presenter cues and demonstration instructions
- A short knowledge check
- A hands-on exercise or investigation task
- A recap and pointers to the next lecture

The condensed talk will select the product story, system map, four highest-value runtime flows, reliability model, and change workflow. It will reference full lectures for optional depth rather than attempting to compress every file into slides.

## Change Guide

The practical change guide will teach learners how to:

1. Preserve a dirty worktree and inspect surrounding call sites and tests
2. Start from visible behavior and trace toward the owning policy, controller, repository, service, or platform adapter
3. Decide whether a change belongs to pure domain logic, main-actor UI orchestration, an actor-isolated service/repository, or the web editor
4. Extend protocols and fakes only when an actual seam is required
5. Add regression coverage appropriate to the layer
6. Run focused tests, the full Swift suite, web checks when applicable, and manual window verification when required
7. Interpret common compiler, concurrency, persistence, bridge, WebKit, signing, and launch failures

Three guided examples will illustrate low-, medium-, and high-complexity modifications without changing product code as part of course creation.

## Accuracy and Verification

Course production will use the checked-out source as the primary authority. Existing README and project documentation will provide product intent and operational context. Historical design documents will be used to explain rationale only when the current code still reflects that decision.

Before completion:

- Every repository-owned file will be represented in the atlas or explicitly classified as a generated/build artifact
- Every named type and runtime path will be checked against the source
- Relative Markdown links will be validated
- Mermaid blocks and document structure will be inspected for readability
- The course will clearly label demonstrations that require macOS UI interaction
- Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, `npm test`, and `npm run typecheck`; if an environmental prerequisite prevents a command from running, record the command, failure, and unverified scope
- Any unverified claim or environment-dependent behavior will be identified explicitly

## Scope Boundaries

The course will explain the repository comprehensively, but it will not:

- Reproduce every source file line by line
- Turn historical plans into current architectural truth
- Modify product code, signing settings, entitlements, dependencies, or user system configuration
- Request or expose Notion passwords, session cookies, or integration tokens
- Treat generated dependencies and compiler output as authored source requiring individual atlas entries
- Promise that unit tests prove window-server, Spaces, focus, or Launch Services behavior that requires manual verification

## Acceptance Criteria

The course is complete when:

1. A programmer new to macOS can explain the product, build layout, application lifecycle, and major technologies.
2. A Swift developer can trace startup, pinning/page switching, stashing, Quick Capture autosave, persistence, and delivery end to end.
3. An experienced developer can locate concurrency, ownership, security, reliability, and testing boundaries without reverse-engineering the entire repository again.
4. A presenter can deliver either the full sequence or the condensed talk using the supplied notes and demonstrations.
5. A maintainer can use the change guide to identify the correct layer and verification strategy for a proposed modification.
6. Every repository-owned file is accounted for through a lecture, the file atlas, or an explicit generated/build-artifact classification.
