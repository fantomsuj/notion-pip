# Notion PiP

> A little piece of Notion that stays with you.

Notion PiP is a native macOS menu-bar app that keeps one Notion page in a durable floating panel, ready wherever your work takes you. Think of it as leaving a notebook open beside your keyboard: a calm, familiar place to put down a thought before it disappears.

I built it because I love Notion as a home for ideas. We live with an extraordinary amount of information at our fingertips, and personal knowledge management is my way of making that abundance useful instead of overwhelming. A page can become a project, a question, a draft, a trail of research, or simply a place to think.

I am happily biased toward writing. Writing is how I build scaffolding for my ideas: it gives loose thoughts somewhere to land, connect, and grow. Notion PiP is meant to make that habit a little more effortless. You should be able to reach for your workspace while you are designing, reading, coding, or wandering through the rest of your Mac—not only when you remember to switch back to it.

## What it feels like

Pin the Notion page you are living in and keep it close without turning it into another full window. The PiP can stay visible across Spaces, tuck itself neatly onto a screen edge, and return to the same live page when you need it again.

- Create a fresh Notion page from the `+` button; it becomes the new pinned page automatically.
- Stash the panel against the nearest screen edge and restore it from its slim tab, the menu bar, or `Command-Shift-P`.
- Keep working in the real, embedded Notion page—not a screenshot or a simplified native imitation.
- Use Quick Capture to get a thought into your workspace without losing the thread of what you were doing.

The app is intentionally a menu-bar accessory, so you will find it in the menu bar rather than the Dock.

## A native Mac app with a real Notion page inside

One of my favorite things about this project is its combination of native macOS behavior and the full Notion experience. Notion PiP is written in Swift 6.2 for macOS 14+ and uses WebKit’s `WKWebView` to host the live Notion app in a native floating panel. That means the panel gets to feel at home on the Mac while the page remains the actual Notion editor, with its familiar session and navigation.

Around that WebKit core are the small native details that make a difference: a menu-bar home, an always-available panel, keyboard control, safe Notion URL handoff, persistence for your pinned page, and a Quick Capture flow.

## Why I love building with Notion

Notion is already a wonderful canvas for thinking. Its API makes it possible for a companion app to participate in that canvas thoughtfully: search a workspace, understand a chosen destination, create a page, and append captured writing without pretending to own your data. For Quick Capture, Notion PiP keeps that API surface narrow and deliberate, with the personal integration token entered only in the app’s own settings.

That combination is the point: the flexibility of a workspace you can shape around your life, plus a tiny native tool that helps you return to it more often.

## Build and run

Full Xcode 26.2 or newer is required. The project-local script builds the SwiftPM executable, stages `dist/NotionPiP.app`, copies resources, ad-hoc signs the app, and launches it through Launch Services:

```sh
./script/build_and_run.sh
```

Optional modes are `--debug`, `--logs`, `--telemetry`, and `--verify`.

Run the tests with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Set up with Codex

After cloning the repository, open it in Codex and ask:

> Set up and run this app locally. Follow the repository's AGENTS.md instructions.

Codex will check the Mac and Xcode prerequisites, build and verify the app, and explain any manual setup that remains. The detailed setup and troubleshooting guidance lives in [`AGENTS.md`](AGENTS.md).

## Security and project notes

Notion PiP accepts only HTTPS Notion page URLs with a canonical 32-character page ID. It removes credentials, query strings, and fragments during canonicalization. The `notion-pip` handoff contract is documented in [the handoff protocol](docs/HANDOFF_PROTOCOL.md).

The development app is sandboxed with outbound network access. Its ad-hoc signature is for local development, not Developer ID distribution or notarization. Reference provenance and reuse exclusions live in [the upstream-reuse notes](docs/UPSTREAM_REUSE.md).
