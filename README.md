# Notion PiP

> A little piece of Notion that stays with you.

Notion PiP is a native macOS accessory that keeps one Notion page in a durable floating panel, ready wherever your work takes you. Its menu-bar icon is available by default and can be hidden in Settings. Think of it as leaving a notebook open beside your keyboard: a calm, familiar place to put down a thought before it disappears.

I built it because I love Notion as a home for ideas. We live with an extraordinary amount of information at our fingertips, and personal knowledge management is my way of making that abundance useful instead of overwhelming. A page can become a project, a question, a draft, a trail of research, or simply a place to think.

I am happily biased toward writing. Writing is how I build scaffolding for my ideas: it gives loose thoughts somewhere to land, connect, and grow. Notion PiP is meant to make that habit a little more effortless. You should be able to reach for your workspace while you are designing, reading, coding, or wandering through the rest of your Mac—not only when you remember to switch back to it.

## What it feels like

Pin the Notion page you are living in and keep it close without turning it into another full window. The PiP can stay visible across Spaces, tuck itself neatly onto a screen edge, and return to the same live page when you need it again.

- Create a fresh Notion page from the `+` button; it becomes the new pinned page automatically.
- Stash the panel against the nearest screen edge and restore it from its slim tab, the optional menu-bar icon, or `Command-Shift-P`; when the PiP itself is zoomed or full screen, the shortcut first returns it to its prior floating size.
- Keep working in the real, embedded Notion page—not a screenshot or a simplified native imitation.
- Reload the currently displayed Notion page with `Command-R`, including the sign-in page if your session has expired.
- Hover at the panel’s top edge and open the page switcher to resume one of seven
  pinned favorites or seven recent pages. Give pins optional device-local roles
  such as “Today” or “Project Brief”; the switcher keeps the Notion title visible
  and searches both role and title without creating another live web view.
- Save device-local panel size presets in Settings and apply them from the PiP
  or menu-bar menus without reloading the live Notion page.
- Opt in to launching Notion PiP when you log in to your Mac. The Settings
  toggle reads macOS's current registration state and points you to Login Items
  settings when the system requires approval.
- Use Quick Capture to get a thought into your workspace without losing the thread of what you were doing.

The app intentionally runs as an accessory rather than appearing in the Dock. Its menu-bar icon is shown by default, and you can turn it off in Settings while continuing to use the edge handle and global shortcut.

## A native Mac app with a real Notion page inside

One of my favorite things about this project is its combination of native macOS behavior and the full Notion experience. Notion PiP is written in Swift 6.2 for macOS 14+ and uses WebKit’s `WKWebView` to host the live Notion app in a native floating panel. That means the panel gets to feel at home on the Mac while the page remains the actual Notion editor, with its familiar session and navigation.

Around that WebKit core are the small native details that make a difference: optional menu-bar access, an always-available panel or edge handle, keyboard control, safe Notion URL handoff, persistence for your pinned page, and a Quick Capture flow.

The page switcher keeps one live `WKWebView`, not one view per page. During the
current app session, switching pages preserves WebKit interaction state such as
navigation history when WebKit can restore it. Across launches—or after memory
pressure discards that opaque state—the app restores the last validated Notion
URL and makes a best-effort, two-second attempt to restore scroll position. If
that fallback cannot load, it returns to the page’s canonical URL and natural
scroll position. If WebKit's live content process exits, the app keeps the
surviving view, invalidates DOM-bound state, and makes one canonical reload with
a same-page scroll fallback. A repeated termination or failed reload stops the
automatic cycle and presents a native retry action.

## Why I love building with Notion

Notion is already a wonderful canvas for thinking. Its API makes it possible for a companion app to participate in that canvas thoughtfully: search a workspace, understand a chosen destination, create a page, and append captured writing without pretending to own your data. For Quick Capture, Notion PiP keeps that API surface narrow and deliberate, with the personal integration token entered only in the app’s own settings.

That combination is the point: the flexibility of a workspace you can shape around your life, plus a tiny native tool that helps you return to it more often.

## Build and run

Full Xcode 26.2 or newer is required. The project-local script builds the SwiftPM executable, stages `dist/NotionPiP.app`, copies resources, ad-hoc signs the app, and launches it through Launch Services:

```sh
./script/build_and_run.sh
```

Optional modes are `--debug`, `--logs`, `--telemetry`, and `--verify`.

Launch at Login must be exercised from the staged `dist/NotionPiP.app`. Running
the SwiftPM executable directly does not provide the signed app-bundle identity
required by ServiceManagement. The local bundle is ad-hoc signed and is rebuilt
in place, so macOS may ask for approval again or retain a stale Login Items entry
after a rebuild. That is useful development coverage, but it does not replace
testing a Developer ID-signed and notarized beta installed at a stable path.

Run the tests with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Set up with Codex

After cloning the repository, open it in Codex and ask:

> Set up and run this app locally. Follow the repository's AGENTS.md instructions.

Codex will check the Mac and Xcode prerequisites, build and verify the app, and explain any manual setup that remains. The detailed setup and troubleshooting guidance lives in [`AGENTS.md`](AGENTS.md).

## Security and project notes

Notion PiP accepts HTTPS page URLs on `app.notion.com`, `notion.com`, and `www.notion.com` with a canonical 32-character hexadecimal page ID. Legacy `notion.so` and `www.notion.so` links remain accepted; all non-app hosts canonicalize to `www.notion.com`. Every accepted host retains its percent-encoded path, while credentials, query strings, and fragments are removed. The `notion-pip` handoff contract is documented in [the handoff protocol](docs/HANDOFF_PROTOCOL.md).

The development app is unsandboxed so the explicitly enabled Quick Copy mode can read selected text from other applications after the user grants macOS Accessibility access. Quick Copy keeps selections in memory only and does not modify the clipboard. Local builds use an available Apple Development or Notion PiP local-development signing identity, falling back to ad-hoc signing when neither exists. Run `./script/setup_local_signing.sh` once to create the optional machine-local identity when repeated ad-hoc rebuilds trigger Keychain authorization prompts. This identity is only for local development; it is not Developer ID distribution signing or notarization. Launch at Login uses Apple's public ServiceManagement API and changes system registration only when you use its explicit toggle. Windowing and login-item checks live in [the manual test matrix](docs/MANUAL_TEST_MATRIX.md), while reference provenance and reuse exclusions live in [the open-source research](docs/OPEN_SOURCE_RESEARCH.md) and [upstream-reuse notes](docs/UPSTREAM_REUSE.md). Product opportunities, comparable interaction patterns, and recommended experiments are synthesized in the [product research report](docs/PRODUCT_RESEARCH_REPORT.md).
