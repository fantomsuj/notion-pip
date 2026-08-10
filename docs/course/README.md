# Notion PiP Repository Course

> Archived source snapshot: this course describes the August 3, 2026 capture
> architecture. Quick Capture, its TypeScript editor, and its delivery pipeline
> were removed on August 10, 2026. The course remains for historical context;
> capture-related links and implementation tours do not describe the current
> checkout.

This course teaches Notion PiP as a complete system: the product experience,
the native macOS shell, the embedded Notion session, durable state, Quick
Capture, delivery, testing, and the workflow for making safe changes. It is
written for a mixed audience, so each lecture moves from a foundation through
a repository tour to an implementation-level deep dive.

## Outcomes

After completing the course:

1. A programmer new to macOS can explain the product, build layout, application lifecycle, and major technologies.
2. A Swift developer can trace startup, pinning/page switching, stashing, Quick Capture autosave, persistence, and delivery end to end.
3. An experienced developer can locate concurrency, ownership, security, reliability, and testing boundaries without reverse-engineering the entire repository again.
4. A presenter can deliver either the full sequence or the condensed talk using the supplied notes and demonstrations.
5. A maintainer can use the change guide to identify the correct layer and verification strategy for a proposed modification.
6. Every repository-owned file is accounted for through a lecture, the file atlas, or an explicit generated/build-artifact classification.

## Prerequisites

Required for every learner:

- Familiarity with basic programming ideas such as values, functions, state,
  errors, and tests. Prior Swift or macOS experience is not required.
- Comfort reading paths, running terminal commands, and inspecting a Git
  checkout without discarding work.
- A local checkout of this repository so that every course link resolves to
  the source being discussed.

Required for the hands-on build and native exercises:

- macOS 15.6 or newer as the build host. The built app targets macOS 14 or
  newer.
- Full Xcode 26.2 or newer installed at `/Applications/Xcode.app`. Command Line
  Tools alone are not sufficient.
- An Apple silicon or Intel Mac. SwiftPM builds a native executable for the
  current Mac.

Helpful, but taught or recapped where needed:

- Swift value semantics, protocols, structured concurrency, actors, and
  `Sendable` types.
- SwiftUI, AppKit, WebKit, SwiftData, Security/Keychain, OSLog, and Carbon.
- TypeScript, browser messaging, Tiptap/ProseMirror, HTTP APIs, and Node's test
  runner. Node.js and npm are needed only for the web-editor exercises; they
  are not required merely to build a fresh clone and run the app.

No `.env` file, Notion token, signing certificate, or other secret is required
to build and launch Notion PiP.

## Choose a learning path

### Complete path — about 17 hours

Read Lectures 1–12 in order and complete each embedded knowledge check and
exercise. Keep the [glossary](GLOSSARY.md) open, study the
[architecture map](ARCHITECTURE_MAP.md) after Lecture 4, and finish with the
[change guide](CHANGE_GUIDE.md). Use the [file atlas](FILE_ATLAS.md) whenever a
tour names an unfamiliar file. This path provides the full product,
implementation, reliability, and maintenance model.

### Fast path — about 5 hours

Read [Lecture 1](01-product-and-user-experience.md), then use the
[architecture map](ARCHITECTURE_MAP.md) for the system overview. Continue with
[Lecture 4](04-composition-and-runtime.md) for ownership and runtime state,
[Lecture 12](12-testing-debugging-and-change-workflow.md) for verification,
and the [change guide](CHANGE_GUIDE.md) for day-to-day maintenance. Consult the
[glossary](GLOSSARY.md) and [file atlas](FILE_ATLAS.md) only when a term or path
needs clarification.

### Presenter path — 60–90 minutes plus preparation

Start with the [presenter guide](PRESENTER_GUIDE.md) to choose a delivery
format, prepare the environment, and rehearse failure recovery. Deliver the
self-contained [condensed talk](CONDENSED_TALK.md) for a 60-, 75-, or 90-minute
session. For a longer workshop, use the presenter notes embedded in Lectures
1–12 and return to the [architecture map](ARCHITECTURE_MAP.md) for diagram
cues.

## Course navigation

Durations include the guided code tour, knowledge check, and hands-on exercise
unless a row is marked as a reference.

| Document | Focus | Duration |
|---|---|---:|
| [01-product-and-user-experience.md](01-product-and-user-experience.md) | Product intent, accessory-app behavior, and user journeys | 45 min |
| [02-repository-and-technology-stack.md](02-repository-and-technology-stack.md) | Repository topology, toolchains, artifacts, build, and launch | 60 min |
| [03-application-lifecycle.md](03-application-lifecycle.md) | Entry point, application lifecycle, concurrency, and termination | 60 min |
| [04-composition-and-runtime.md](04-composition-and-runtime.md) | Dependency composition, runtime facade, controllers, and state | 75 min |
| [05-panel-stashing-and-controls.md](05-panel-stashing-and-controls.md) | PiP panel, geometry, edge stashing, and global controls | 75 min |
| [06-webkit-notion-session.md](06-webkit-notion-session.md) | Shared WebKit session, navigation, switching, and restoration | 75 min |
| [07-domain-modeling-and-policies.md](07-domain-modeling-and-policies.md) | Value types, validation, policies, retries, and security invariants | 75 min |
| [08-persistence-and-restoration.md](08-persistence-and-restoration.md) | SwiftData schemas, repositories, transitions, and degraded service | 75 min |
| [09-quick-capture-editor-bridge.md](09-quick-capture-editor-bridge.md) | Tiptap editor, Swift–TypeScript bridge, autosave, and conflicts | 90 min |
| [10-notion-api-and-delivery.md](10-notion-api-and-delivery.md) | Credentials, Notion API, conversion, scheduling, and reliable delivery | 90 min |
| [11-views-settings-and-state.md](11-views-settings-and-state.md) | Views, presenters, commands, settings, and event propagation | 75 min |
| [12-testing-debugging-and-change-workflow.md](12-testing-debugging-and-change-workflow.md) | Automated and manual tests, diagnostics, packaging, and change workflow | 90 min |
| [ARCHITECTURE_MAP.md](ARCHITECTURE_MAP.md) | Six cross-layer runtime flows and subsystem ownership | 45 min reference |
| [FILE_ATLAS.md](FILE_ATLAS.md) | Exhaustive repository-owned file inventory | 30 min orientation; ongoing reference |
| [PRESENTER_GUIDE.md](PRESENTER_GUIDE.md) | Full-course schedules, talk tracks, demos, and recovery plans | 45 min preparation |
| [CONDENSED_TALK.md](CONDENSED_TALK.md) | Self-contained architecture presentation | 60, 75, or 90 min |
| [CHANGE_GUIDE.md](CHANGE_GUIDE.md) | Owning-layer decisions, diagnostics, verification, and worked changes | 60 min |
| [GLOSSARY.md](GLOSSARY.md) | Swift, macOS, WebKit, persistence, editor, and API terms | 30 min orientation; ongoing reference |

## Source snapshot and authority

The course describes the working checkout as it existed on August 3, 2026.
Course production records the starting commit, dirty-worktree status, recent
history, and a sorted union of tracked and non-ignored untracked paths in local
`.context/course-source-snapshot.txt` and `.context/course-source-files.txt`
evidence files. Those evidence files are intentionally not committed.

The final Task 13 Swift and web verification runs against the recorded dirty
working tree, including the pre-existing product and test edits shown by
`git status --short`; it is not evidence from a pristine checkout or from an
isolated course-only commit. Lecture-specific baseline notes remain the
authority when a current linked file differs from the source taught there.

The checked-out source is the primary authority. Existing project documentation
adds product and operational context; historical specifications and plans
explain rationale only when the current implementation still reflects the
decision. Course claims distinguish committed architecture from uncommitted
work that was present during production.

## Build and verification commands

Before running anything, preserve local work with `git status --short`. Confirm
the supported host and full Xcode installation with:

```sh
sw_vers -productVersion
test -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version
```

Build, stage, ad-hoc sign, launch, and verify the native app with:

```sh
./script/build_and_run.sh --verify
```

The verified development bundle is staged at `dist/NotionPiP.app`. Run the full
Swift suite with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

When working on `Web/QuickCaptureEditor`, install the pinned JavaScript
dependencies and run the web checks with:

```sh
npm ci
npm test
npm run typecheck
```

`npm run build:editor` regenerates the checked-in editor asset and is not part
of the course verification pass. Run it only when intentionally changing the
web editor and review the generated diff.

## Safety and manual-verification boundaries

- Inspect `git status --short` before making changes. Preserve unrelated work,
  follow nearby source and test patterns, and stage only the intended files.
- Save active work and quit Notion PiP before running
  `./script/build_and_run.sh --verify`; the script terminates any running
  `NotionPiP` process before rebuilding.
- A pre-existing `node_modules` directory makes the build script regenerate
  Quick Capture editor assets and therefore requires Node.js and npm. A fresh
  clone uses the checked-in generated assets without Node.
- Do not change product code, dependencies, generated assets, signing,
  entitlements, or system configuration merely to follow the course.
- The all-Spaces floating panel and accessory activation policy are intentional.
  Notion PiP does not appear in the Dock; its menu-bar icon is visible by
  default and can be hidden.
- Treat window-server, Spaces, focus, login-session, and Launch Services
  behavior as manual verification. Unit tests do not prove those integrations.
- Never paste a Notion password, session cookie, personal integration token, or
  another secret into chat or a terminal command. Authentication happens in
  the embedded Notion UI, and an optional integration token belongs only in the
  app's settings UI.
- The local app is ad-hoc signed for development. It is not a Developer
  ID-signed or notarized distribution build.
- `.build`, `dist`, and `node_modules` are build/dependency artifact groups, not
  individually authored course inventory entries.
