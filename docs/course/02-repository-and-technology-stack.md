# Lecture 2 — Repository and Technology Stack

**Duration:** 60 minutes

Notion PiP is one native macOS executable with two authoring toolchains. Swift
builds the application and owns its runtime behavior. TypeScript builds the
local Quick Capture editor that SwiftPM embeds as a resource. This lecture
turns the repository from a list of folders into a map of authored source,
generated input, build output, test evidence, and delivery machinery.

Keep the [course glossary](GLOSSARY.md) open for unfamiliar terms and use the
[architecture map](ARCHITECTURE_MAP.md) to connect these directories to runtime
ownership. The checked-out source is authoritative; historical plans under
`docs/superpowers` explain past decisions but do not override current code.

## Learning objectives

By the end of this lecture, you can:

1. Classify every repository root area as source, tests, configuration,
   documentation, tooling, generated input, dependency cache, or build output.
2. Explain how Swift Package Manager turns `Sources/NotionPiP` and its copied
   Quick Capture resources into one executable product.
3. Describe what TypeScript, Tiptap, esbuild, the Node test runner, and
   `happy-dom` each contribute to the web editor.
4. Separate the requirements for building from source from the requirements
   for running the staged app.
5. Trace `script/build_and_run.sh` through optional editor generation, Swift
   compilation, bundle staging, entitlement application, ad-hoc signing,
   Launch Services, and verification.
6. Choose the correct Swift, web, generated-asset, or manual verification for a
   change.

The concrete authorities are the SwiftPM [package manifest](../../Package.swift),
the web [package manifest](../../package.json), the
[TypeScript configuration](../../tsconfig.json), and the
[build-and-run script](../../script/build_and_run.sh).

## Before you begin

You need basic familiarity with files, directories, commands, and the idea that
source code is transformed into a runnable artifact. You do not need prior
Swift, macOS, or frontend experience.

Before running any repository command, inspect `git status --short` and
preserve unrelated work. In particular, the build script intentionally
terminates every running process named `NotionPiP`; save active edits and quit
the app before using it. The operational guardrails and supported setup flow
live in [`AGENTS.md`](../../AGENTS.md).

### Source-build requirements versus runtime requirements

These are different contracts:

| Concern | Building from source | Running the staged app |
|---|---|---|
| macOS | Build host must be macOS 15.6 or newer because Xcode 26.2 requires it | The bundle declares macOS 14.0 or newer |
| Apple tools | Full Xcode 26.2 or newer must exist at `/Applications/Xcode.app`; Command Line Tools alone are insufficient | Xcode is not required just to run an already staged build |
| Processor | SwiftPM builds a native executable for the current Apple silicon or Intel Mac | This local script does not create a universal distribution archive |
| Node and npm | Not required for a fresh clone's ordinary native build; required for web-editor work, and also required when an existing `node_modules` makes the script rebuild the editor | Not required by the launched app because the editor assets are bundled |
| Secrets | No `.env`, Notion token, signing certificate, password, or cookie is required | Sign in inside the embedded Notion UI; the optional personal token belongs only in Settings |
| Signing | The script creates an ad-hoc development signature | The result is suitable for local development, not Developer ID distribution or notarization |

The source contract comes from the repository
[setup instructions](../../AGENTS.md), while the runtime minimum is written
into the generated `Info.plist` by the
[build script](../../script/build_and_run.sh).

**Manual-verification boundary:** a successful compiler run cannot prove that
Launch Services, the Dock/accessory policy, Spaces, focus, or the real login
session behaves correctly. Those checks require a real Mac and the
[manual test matrix](../MANUAL_TEST_MATRIX.md).

## Foundation

### From source to process

A beginner can model the build with six nouns:

- A **package manifest** describes products, targets, platforms, and resources.
- A **target** is a group of source files compiled together. This repository
  has an executable target and a test target.
- A **resource** is data shipped with code but not compiled as Swift. The local
  Quick Capture HTML, CSS, and generated JavaScript are resources.
- An **app bundle** is a directory ending in `.app` with a prescribed layout:
  executable in `Contents/MacOS`, metadata in `Contents/Info.plist`, and data in
  `Contents/Resources`.
- **Entitlements** declare privileged capabilities granted to a signed app.
- **Launch Services** is the macOS facility used by `open` to launch and
  register an app bundle, including its URL scheme.

Compilation alone produces a command-line-shaped executable and a SwiftPM
resource bundle. Staging assembles those outputs into
`dist/NotionPiP.app`; signing binds code, bundle contents, and entitlements;
launching asks macOS to start the bundle.

### The technologies and their jobs

| Technology | Plain-language role | Repository evidence |
|---|---|---|
| Swift 6.2 and SwiftPM | Compile one native executable and its tests | [`Package.swift`](../../Package.swift) |
| SwiftUI | Declare app views and bind them to observable state | [`Sources/NotionPiP/Views`](../../Sources/NotionPiP/Views) |
| AppKit | Own application lifecycle, panels, menus, shortcuts, and windows | [`Sources/NotionPiP/Platform`](../../Sources/NotionPiP/Platform) |
| WebKit | Host one live Notion session and a separate local editor bridge | [`NotionWebSession.swift`](../../Sources/NotionPiP/Platform/NotionWebSession.swift), [`CaptureEditorSession.swift`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift) |
| SwiftData | Persist pages, restoration state, captures, and destinations behind actor-backed repositories | [`Sources/NotionPiP/Persistence`](../../Sources/NotionPiP/Persistence) |
| Security/Keychain | Store the optional personal integration token outside preferences and web content | [`PersonalTokenCredentialVault.swift`](../../Sources/NotionPiP/Platform/PersonalTokenCredentialVault.swift) |
| Carbon | Register global keyboard shortcuts | [`GlobalShortcutRegistrar.swift`](../../Sources/NotionPiP/Platform/GlobalShortcutRegistrar.swift) |
| OSLog/signposts | Emit privacy-aware diagnostics and performance intervals | [`PerformanceSignposter.swift`](../../Sources/NotionPiP/Platform/PerformanceSignposter.swift) |
| TypeScript 7 | Type-check the local Quick Capture editor and its bridge protocol | [`tsconfig.json`](../../tsconfig.json), [`Web/QuickCaptureEditor`](../../Web/QuickCaptureEditor) |
| Tiptap 3 / ProseMirror | Supply the structured rich-text editor and document model | [`package.json`](../../package.json), [`editor.ts`](../../Web/QuickCaptureEditor/editor.ts) |
| esbuild | Bundle authored editor modules and dependencies into browser-ready JavaScript | [`build.ts`](../../Web/QuickCaptureEditor/build.ts) |
| Node test runner / `happy-dom` | Run TypeScript unit tests and browser-like DOM tests without launching the macOS app | [`package.json`](../../package.json), [`dom.ts`](../../Web/QuickCaptureEditor/test-support/dom.ts) |

The architecture map uses **composition root**, **repository**, **generated
editor asset**, and **manual-verification boundary** for these same ideas. Reuse
those terms rather than inventing a second vocabulary.

## Repository tour

### Top-level tree

This tree shows every tracked root entry and the important nested areas. The
three bracketed directories are local artifact groups ignored by Git, not
authored root areas.

```text
.
├── .codex/                    # Codex environment and Run action
├── .conductor/                # Conductor workspace run configuration
├── .github/                   # CI workflow
├── .gitignore                 # ignored build, dependency, secret, and evidence paths
├── .gitkeep                   # empty repository placeholder
├── .impeccable.md             # product design context
├── AGENTS.md                  # contributor and local-setup guardrails
├── Package.swift              # SwiftPM product, targets, platform, resource rule
├── README.md                  # product intent and primary build entry point
├── Sources/NotionPiP/
│   ├── App/                   # entry, composition, runtime, application controllers
│   ├── Domain/                # validated values and pure policies
│   ├── Persistence/           # SwiftData schemas, models, repositories, preferences
│   ├── Platform/              # AppKit, WebKit, Carbon, Keychain, logging adapters
│   ├── Resources/QuickCapture/# HTML, CSS, and checked-in generated editor.js
│   ├── Services/              # capture lifecycle, delivery, Notion API
│   └── Views/                 # SwiftUI presentation
├── Support/                   # entitlements and release version/build number
├── Tests/NotionPiPTests/      # Swift Testing regression suite and test support
├── Web/QuickCaptureEditor/    # authored TypeScript editor, build entry, and tests
├── docs/                      # current docs, research, history, and this course
├── package.json               # web scripts and direct dependencies
├── package-lock.json          # pinned npm dependency graph
├── script/                    # native build, staging, signing, launch script
├── tsconfig.json              # strict, no-emit TypeScript rules
├── [.build/]                  # SwiftPM build output
├── [dist/]                    # staged NotionPiP.app output
└── [node_modules/]            # installed npm dependency cache
```

### Root-area classification

| Root entry | Classification and responsibility |
|---|---|
| [`.codex/`](../../.codex) | Tool configuration. Its environment exposes the repository build script as a Run action. |
| [`.conductor/`](../../.conductor) | Workspace configuration. It defines the same app script as the default nonconcurrent run action. |
| [`.github/`](../../.github) | Automation. CI runs Swift tests, web tests, type-checking, editor generation, and a generated-asset diff check. |
| [`.gitignore`](../../.gitignore) | Source-control policy for `.build`, `dist`, `node_modules`, secrets, and local course evidence. |
| [`.gitkeep`](../../.gitkeep) | Empty placeholder with no compile-time or runtime behavior. |
| [`.impeccable.md`](../../.impeccable.md) | Product design context: native, focused, trustworthy, state-preserving UI. |
| [`AGENTS.md`](../../AGENTS.md) | Maintainer contract for safe changes, supported toolchains, setup, and troubleshooting. |
| [`Package.swift`](../../Package.swift) | Swift build manifest and macOS deployment target. |
| [`README.md`](../../README.md) | Product-facing overview and concise build guidance. |
| [`Sources/`](../../Sources) | Authored Swift production source plus runtime resources. |
| [`Support/`](../../Support) | Bundle capabilities and release identity inputs. |
| [`Tests/`](../../Tests) | Authored Swift regression tests; these are not packaged into the app. |
| [`Web/`](../../Web) | Authored browser-editor modules and web tests; most files are build-time inputs, not separately copied at runtime. |
| [`docs/`](../../docs) | Current operating/product docs, research, historical plans/specs, and course material. |
| [`package.json`](../../package.json) | npm commands plus pinned direct Tiptap and tool dependencies. |
| [`package-lock.json`](../../package-lock.json) | npm lockfile version 3 graph used by `npm ci` for reproducible installation. |
| [`script/`](../../script) | Shell automation that builds, stages, signs, launches, and optionally verifies. |
| [`tsconfig.json`](../../tsconfig.json) | Strict TypeScript checking for `Web/**/*.ts`, targeting ES2022 with Node and DOM types and emitting no files. |

`docs/superpowers` is historical design and implementation evidence; current
source and tests win when history disagrees. `.build`, `dist`, and
`node_modules` are artifact groups and should not be reviewed as authored
source file by file. Local `.context` and `.superpowers` work records are also
ignored and are not product inputs.

## Runtime trace

The default path from checkout to running process is:

```text
package.json + Web/QuickCaptureEditor (only when node_modules exists)
                         │
                         ▼
        Sources/.../Resources/QuickCapture/editor.js
                         │
Package.swift + Sources/NotionPiP + copied QuickCapture resource directory
                         │ swift build --product NotionPiP
                         ▼
          native executable + SwiftPM resource bundle
                         │ stage bundle and create Info.plist
                         ▼
                 dist/NotionPiP.app
                         │ entitlements + ad-hoc codesign
                         ▼
                  open -n through Launch Services
                         │
                         ▼
                 running NotionPiP process
```

In concrete order, [`build_and_run.sh`](../../script/build_and_run.sh):

1. Selects full Xcode through `DEVELOPER_DIR`, validates the version fields in
   [`Support/Version.env`](../../Support/Version.env), validates its mode, and
   terminates an existing `NotionPiP` process.
2. Runs `npm run build:editor --if-present` only when both `package.json` and an
   existing `node_modules` directory are present.
3. Runs `swift build --product NotionPiP`, discovers SwiftPM's binary directory,
   and requires an executable output.
4. Recreates `dist/NotionPiP.app`, copies the executable into
   `Contents/MacOS`, and copies every top-level SwiftPM `.bundle` into
   `Contents/Resources`.
5. Generates `Contents/Info.plist` with bundle identity, version, the
   `notion-pip` URL scheme, macOS 14.0 minimum, and `LSUIElement = true` for the
   accessory/no-Dock role.
6. Ad-hoc signs with `codesign --sign - --timestamp=none`, applying
   [`NotionPiP.entitlements`](../../Support/NotionPiP.entitlements), then
   verifies the signature.
7. Uses `open -n dist/NotionPiP.app`, asking Launch Services to launch a new
   instance rather than invoking the executable path directly.

The five accepted modes share the same build, staging, and signing work:

| Command | Behavior after staging |
|---|---|
| `./script/build_and_run.sh` or `run` | Launch and return. |
| `./script/build_and_run.sh --debug` | Launch, wait for the process, and attach LLDB. |
| `./script/build_and_run.sh --logs` | Launch and stream unified logs for the `NotionPiP` process. |
| `./script/build_and_run.sh --telemetry` | Launch and stream logs for subsystem `com.fantomsuj.NotionPiP`. |
| `./script/build_and_run.sh --verify` | Capture startup logs, launch, verify bundle metadata/resource/signature/process stability, and reject selected SwiftData concurrency diagnostics. |

These arguments are script modes, not Swift compiler optimization flags. The
script calls ordinary `swift build` and does not pass `-c release`.

**Manual-verification boundary:** `--verify` establishes concrete startup and
bundle facts, but Launch Services behavior, URL delivery, accessory presence,
and window behavior still require observation on a real Mac.

## Deep dive

### SwiftPM targets and copied resources

[`Package.swift`](../../Package.swift) declares Swift tools version 6.2 and a
macOS 14 platform minimum. It has no external Swift package dependencies and
defines:

- executable product `NotionPiP` backed by executable target `NotionPiP` at
  [`Sources/NotionPiP`](../../Sources/NotionPiP);
- test target `NotionPiPTests` at
  [`Tests/NotionPiPTests`](../../Tests/NotionPiPTests), depending on the
  executable target;
- a `.copy("Resources/QuickCapture")` rule, which preserves the local editor
  directory inside SwiftPM's generated resource bundle.

The runtime editor inputs are
[`index.html`](../../Sources/NotionPiP/Resources/QuickCapture/index.html),
[`composer.css`](../../Sources/NotionPiP/Resources/QuickCapture/composer.css),
and [`editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js).
The verification mode specifically expects the staged resource at
`Contents/Resources/NotionPiP_NotionPiP.bundle/QuickCapture/index.html`.

### Authored web source versus checked-in generated asset

The TypeScript source under
[`Web/QuickCaptureEditor`](../../Web/QuickCaptureEditor) is the human-authored
editor implementation. Tiptap supplies editor primitives and ProseMirror's
document model. Repository controllers add formatting, slash commands,
autosave, transition serialization, and the Swift–JavaScript bridge. esbuild's
[`build.ts`](../../Web/QuickCaptureEditor/build.ts) bundles that source and its
dependencies into the checked-in generated
[`editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js).

Checking in the generated asset is deliberate: a fresh native checkout can
build and run without installing Node. There are two regeneration paths:

1. Intentional web work runs `npm run build:editor` and reviews the generated
   diff.
2. The native build script regenerates automatically when `node_modules`
   already exists, because that directory signals an available web toolchain.

CI installs from the lockfile, runs tests and type-checking, regenerates the
asset, then requires no diff in `editor.js`. Locally, do not regenerate it for
an unrelated native or documentation change.

### Web checks and compiler rules

[`package.json`](../../package.json) defines three scripts:

```sh
npm test
npm run typecheck
npm run build:editor
```

`npm test` uses Node's test runner with type stripping to execute the
`Web/**/*.test.ts` suites. DOM-facing tests use `happy-dom`. `typecheck` invokes
TypeScript with no emit. The [TypeScript configuration](../../tsconfig.json)
uses ES2022, NodeNext modules/resolution, Node and DOM libraries, strict mode,
`noUncheckedIndexedAccess`, and exact optional-property types. The build script
uses esbuild to create the browser artifact; type-checking and bundling are
separate operations.

For web-editor dependency work, `npm ci` installs the exact graph in
[`package-lock.json`](../../package-lock.json). The direct runtime dependencies
are pinned Tiptap 3.28.0 packages; development dependencies include TypeScript
7.0.2, esbuild 0.28.1, Node types, and `happy-dom`.

### Sandbox, signing, and bundle identity

[`NotionPiP.entitlements`](../../Support/NotionPiP.entitlements) grants exactly
two capabilities:

- `com.apple.security.app-sandbox`: run inside the App Sandbox;
- `com.apple.security.network.client`: make outbound network connections for
  the embedded Notion page and Notion API delivery.

The file does not grant arbitrary file access or inbound network service. The
build script applies these entitlements while creating an ad-hoc signature,
then performs strict deep verification. Ad-hoc signing proves local bundle
coherence and carries entitlements; it does not provide a Developer ID,
notarization ticket, distribution identity, or public release readiness. See
the distinction in [beta readiness](../BETA_READINESS.md).

The generated `Info.plist` supplies the bundle identifier
`com.fantomsuj.NotionPiP`, version values, custom URL scheme, minimum system
version, principal class, and `LSUIElement`. `LSUIElement = true` complements
the runtime accessory activation policy: no ordinary Dock icon is intentional.

### Verification ladder

Choose checks by the changed surface:

```sh
# Native source and Swift tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Web editor dependencies and automated checks
npm ci
npm test
npm run typecheck

# Intentional generated-editor changes only
npm run build:editor

# Full local bundle staging and startup verification
./script/build_and_run.sh --verify
```

Swift tests and web tests are automated evidence. The staged-app verification
checks bundle shape and startup stability. Window-server, Spaces, focus,
login-session, and Launch Services behavior remain manual evidence even after
all commands pass.

## Common misconceptions and failure modes

1. **“This is two applications because it has Swift and TypeScript.”** No. It
   is one native executable product. The TypeScript editor becomes a bundled
   local resource rendered by WebKit.
2. **“Node is always required to run Notion PiP.”** No. The generated editor is
   checked in. Node is needed for editor work and is conditionally invoked by
   the native script only when `node_modules` already exists.
3. **“Deleting `node_modules` is the normal fix when a build surprises me.”**
   First explain why the conditional rebuild ran and inspect its failure.
   Dependency deletion changes local state and is not an automatic remedy.
4. **“`swift build` has produced the same artifact as the app script.”** It has
   produced the executable and SwiftPM resources, not the staged `.app`, its
   generated `Info.plist`, entitlements, signature, or Launch Services launch.
5. **“Ad-hoc signed means ready to distribute.”** It means locally signed for
   development. Developer ID signing and notarization are separate release
   work.
6. **“The sandbox blocks Notion because networking is dangerous.”** The app is
   sandboxed and explicitly has outbound client networking. There is no broad
   file entitlement in the current capability set.
7. **“`--debug` creates a debug build while the default creates release.”**
   Every mode currently runs the same unqualified `swift build`; `--debug`
   changes what happens after launch by attaching LLDB.
8. **“No Dock icon means launch failed.”** The bundle declares `LSUIElement`
   and the app selects accessory activation. Look for the menu-bar item, edge
   handle, or configured shortcut.
9. **“Passing `--verify` proves macOS integration.”** It checks specified
   bundle, process, signature, resource, and startup-log facts. Real Spaces,
   focus, URL handoff, and Launch Services behavior are manual-verification
   boundaries.
10. **“Everything visible in the checkout is authored source.”** `.build`,
    `dist`, and `node_modules` are derived or installed artifact groups. The
    checked-in `editor.js` is generated, but intentionally versioned as a
    native-build input.

## Presenter notes

### Suggested 60-minute pacing

- **0–5 min:** contrast source, target, resource, app bundle, and process.
- **5–15 min:** walk the top-level tree and ask learners to classify entries.
- **15–25 min:** explain the SwiftPM target/resource model and native stack.
- **25–35 min:** explain authored TypeScript, Tiptap, tests, esbuild, and the
  checked-in generated asset.
- **35–47 min:** trace build, staging, entitlements, ad-hoc signing, and launch.
- **47–52 min:** separate source-build requirements from runtime requirements.
- **52–56 min:** discuss failure modes and manual-verification boundaries.
- **56–60 min:** run the knowledge check and assign the exercise.

### Demonstration plan

Start with the repository tree, then open
[`Package.swift`](../../Package.swift), [`package.json`](../../package.json),
and [`build_and_run.sh`](../../script/build_and_run.sh) in that order. This
sequence moves from structure to the two authoring toolchains to delivery.

For a safe, read-only artifact demonstration, inspect an existing
`dist/NotionPiP.app/Contents` if present. Do not run the build script until the
audience has saved work and confirmed no `NotionPiP` process is active. If Node
is unavailable, teach the fresh-clone path from the checked-in `editor.js`
rather than installing tooling during the talk.

**Manual demonstration:** launching via `open`, observing no Dock icon, testing
the URL scheme, and checking panel behavior require a real macOS login session.
If those conditions are unavailable, show the responsible `Info.plist`
generation and point to the manual matrix; do not claim the integration passed.

## Knowledge check

1. Why can a fresh checkout build the native app without Node?
2. What are the two SwiftPM targets, and which depends on which?
3. Is `editor.js` authored source, disposable build output, or a checked-in
   generated input?
4. What does the `.copy("Resources/QuickCapture")` rule accomplish?
5. Which two sandbox capabilities are granted?
6. What is the difference between `swift build` and
   `./script/build_and_run.sh`?
7. What changes when `--debug` is supplied?
8. Which requirement applies to the built app but not to the source build
   host: macOS 14 minimum or macOS 15.6 minimum?
9. Name one fact `--verify` checks and one behavior it cannot prove.

### Answers

1. The generated Quick Capture `editor.js` is checked in and copied as a Swift
   resource.
2. `NotionPiP` is the executable target; `NotionPiPTests` is the test target and
   depends on `NotionPiP`.
3. It is a checked-in generated input to the ordinary native build. It should
   be regenerated only from intentional editor changes and reviewed.
4. It preserves the Quick Capture resource directory in SwiftPM's generated
   bundle so the app can load HTML, CSS, and JavaScript at runtime.
5. App Sandbox and outbound network client access.
6. `swift build` compiles the executable/resources. The script also performs
   conditional editor generation, `.app` staging, metadata creation,
   entitlement application, signing, launch, and mode-specific behavior.
7. Compilation is unchanged; after launch the script waits for the process and
   attaches LLDB.
8. macOS 14 is the staged app's deployment minimum. Building with Xcode 26.2
   requires a macOS 15.6-or-newer host.
9. Examples checked: bundle ID, minimum version, accessory flag, URL scheme,
   copied resource, signature, process stability, and selected concurrency
   diagnostics. Examples not proven: actual Spaces, focus, Dock, URL delivery,
   login-session, or Launch Services behavior.

## Hands-on exercise

### Exercise: classify a proposed directory

In pairs, classify each item below using one of these labels: **authored
production source**, **authored tests**, **configuration**, **documentation**,
**checked-in generated input**, **installed dependencies**, or **build/staged
output**. Then state whether an ordinary native-only change should edit, run,
review, or ignore it.

1. `Sources/NotionPiP/Platform`
2. `Sources/NotionPiP/Resources/QuickCapture/editor.js`
3. `Tests/NotionPiPTests`
4. `Web/QuickCaptureEditor`
5. `Support/NotionPiP.entitlements`
6. `docs/superpowers`
7. `node_modules`
8. `.build`
9. `dist/NotionPiP.app`
10. `.github/workflows`

Next, imagine adding a new TypeScript editor command. Write the smallest
verification path that accounts for authored source, tests, type checking,
generated output, native resource packaging, and the manual boundary. Do not
run the commands for this classification exercise.

### Expected answers and observations

| Item | Classification | Expected treatment |
|---|---|---|
| `Sources/NotionPiP/Platform` | Authored production source | Edit for owning native adapter behavior; add focused Swift tests and run Swift verification. |
| `.../QuickCapture/editor.js` | Checked-in generated input | Review its diff after intentional editor generation; do not hand-edit or regenerate for unrelated work. |
| `Tests/NotionPiPTests` | Authored tests | Edit when adding/regressing native behavior; never package it into the app. |
| `Web/QuickCaptureEditor` | Authored production source plus colocated authored tests/build entry | Edit for editor behavior; run web tests/type-check and regenerate intentionally. |
| `Support/NotionPiP.entitlements` | Configuration and security contract | Change only for an explicit capability requirement; verify signing and behavior. |
| `docs/superpowers` | Historical documentation | Consult for rationale, but verify claims against current source and tests. |
| `node_modules` | Installed dependencies | Do not review file by file or commit; its presence triggers conditional editor generation. |
| `.build` | SwiftPM build output | Do not edit or commit. |
| `dist/NotionPiP.app` | Staged build output | Inspect or launch for verification; do not treat it as source. |
| `.github/workflows` | Automation configuration | Edit only when changing CI behavior; keep local and CI commands aligned. |

For the proposed editor command, the expected path is: edit
`Web/QuickCaptureEditor` and its test, run `npm test`, run
`npm run typecheck`, intentionally run `npm run build:editor`, review the
`editor.js` diff, run the relevant Swift resource/bridge tests, and stage with
`./script/build_and_run.sh --verify` when a live bundle check is warranted.
Actual WebKit interaction, focus, and Launch Services integration remain manual
observations.

## Recap

- Notion PiP is one SwiftPM executable with one Swift test target and one copied
  Quick Capture resource directory.
- Swift owns the native app; TypeScript and Tiptap author the local editor;
  esbuild produces a checked-in runtime asset.
- A fresh clone can build without Node, while web-editor development uses npm,
  Node tests, TypeScript checking, and intentional asset regeneration.
- The staged development app targets macOS 14+, while building it requires
  macOS 15.6+ and full Xcode 26.2+ at the repository's selected path.
- The build script goes beyond compilation: it stages an app bundle, generates
  metadata, applies sandbox/network entitlements, ad-hoc signs, launches through
  Launch Services, and offers debug/log/telemetry/verification modes.
- `.build`, `dist`, and `node_modules` are artifact groups; `editor.js` is the
  unusual but deliberate checked-in generated input.
- Automated checks establish source and bundle facts. Window-server, Spaces,
  focus, login-session, and Launch Services behavior still require manual
  verification.

Continue with the application-lifecycle lecture listed in the
[course navigation](README.md#course-navigation) to follow the staged
executable from process entry through composition, startup, and termination.
