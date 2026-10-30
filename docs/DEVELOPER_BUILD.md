# Developer build and live diagnostics

Perch's debug builds double as a developer build. They add tools for seeing what
the embedded Notion page and Perch itself are doing, live, without attaching
Instruments. Release builds compile none of it.

## How it is switched on

`Package.swift` defines the `PERCH_DEVELOPER` compilation condition for the
debug configuration only, on both the app and test targets:

```swift
.define("PERCH_DEVELOPER", .when(configuration: .debug))
```

`swift build`, `swift test`, and `script/build_and_run.sh` build debug, so they
are developer builds. `script/package_release.sh` and CI's release build use
`--configuration release`, so the notarized DMG never contains the developer
code, the Web Inspector flag, or the WebKit SPI call described below.
`DeveloperBuild.isEnabled` reports which kind of build is running.

## What a developer build adds

| Tool | Where | What it is for |
| --- | --- | --- |
| Web Inspector | Safari → Develop → *your Mac* → Perch | Notion's console errors, network, JS memory, layout and timelines. |
| Diagnostics HUD | Developer → Toggle Diagnostics HUD (⌃⌥⌘D), or `build_and_run.sh --diagnostics` | Live memory and CPU for Perch and the web content process, web view state, key delay while typing, counters, latest signpost timings, recent events. |
| Diagnostics report | Developer → Copy Diagnostics Report (⌃⌥⌘C) | A plain-text snapshot for an issue or a chat. Page IDs are shortened; no titles or URLs. |
| Simulate memory pressure | Developer menu | Runs Perch's real warning or critical handler, so eviction can be tested without starving the Mac. |
| Evict web view | Developer menu | Asks for the normal eviction, which only happens while the panel is hidden. |
| Kill web content process | Developer menu | Sends `SIGKILL` to WebKit's renderer to exercise crash recovery. |

The Developer menu lives in the app's main menu. Perch is an accessory app, so
the menu bar is not shown, but its shortcuts work whenever the Perch panel is
focused, the same way ⌘R reload does.

The HUD samples once a second only while it is open. With the HUD closed, a
developer build does no extra work beyond recording a few events in memory.

### Where the numbers come from

- **Memory** is the physical footprint from `proc_pid_rusage`, the same figure
  Activity Monitor's Memory column shows.
- **CPU** is the change in user plus system time between samples, divided by
  wall time, so 100% is one full core. rusage reports CPU time in Mach ticks,
  which are converted with `mach_timebase_info`.
- **Web content process** is the WebKit renderer that holds almost all of
  Notion's memory. Its pid comes from WebKit's `_webProcessIdentifier` SPI. Only
  developer builds call it, after checking WebKit still responds to it.
- **Timings** come from the existing `PerformanceSignposter` intervals. In
  developer builds each finished interval is also recorded with its duration.
- **Counters and events** come from the memory-pressure handler, renderer
  termination, navigation failures, and web view construction and eviction.

### Finding typing pauses

The HUD's **Key delay** section times every key press in two places:

- **Waiting on Perch**: from the moment macOS stamped the key event until
  Perch's main thread had passed it to the web view. If this is high, Perch
  itself was busy (look for the work in Instruments' Time Profiler or in the
  recent events).
- **Notion page**: from the key event inside the page until the frame after
  Notion handled it. If this is high and the Perch number is low, Notion's
  JavaScript, a garbage collection, or WebKit layout was the cause. Record a
  timeline in Web Inspector (Timelines → JavaScript & Events and Rendering
  Frames) while typing to see which.

Each value shows the last key, the worst key, and how many keys took 50 ms or
more. Every slow key is also added to the recent events, so a pause can be
matched to whatever else happened at the same moment. Reset the counters
before a test, type until a pause happens, then copy the report. The page
probe is only installed in developer builds.

A debug build runs Perch's own Swift code unoptimized, so judge Perch's
numbers against a release build before treating a small delay as a bug.

## Research summary

How comparable apps (WKWebView and Electron wrappers, Apple's own apps, debug
SDKs) ship developer tooling, and what that meant for Perch:

1. **Web Inspector is the standard tool for an embedded web view.** Since macOS
   13.3, `WKWebView.isInspectable` must be set for Safari to list the view;
   Apple recommends turning it on for debug builds only. Perch's minimum is
   macOS 14, so no availability check is needed.
   ([Apple](https://developer.apple.com/documentation/safari-developer-tools/enabling-inspecting-content-in-your-apps),
   [WebKit](https://webkit.org/web-inspector/enabling-web-inspector/))
2. **Gate developer code at compile time, not with a runtime flag.** A
   compilation condition per build configuration keeps debug-only code and SPI
   out of shipped binaries. SwiftPM supports this with
   `.define(_:, .when(configuration: .debug))`.
   ([Swift forums](https://forums.swift.org/t/how-to-use-a-custom-build-configuration-in-a-swift-package/36259),
   [Augmented Code](https://augmentedcode.io/2022/05/02/linking-a-swift-package-only-in-debug-builds/))
3. **An in-app HUD is common for live numbers.** Performance overlays such as
   GDPerformanceView and Apple's Metal HUD show memory and CPU on top of the app.
   For a WKWebView app the important process is `com.apple.WebKit.WebContent`,
   which routinely uses several hundred MB, far more than the host app.
   ([GDPerformanceView](https://cocoapods.org/pods/GDPerformanceView-Swift),
   [Metal HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance))
4. **Keep using unified logging and signposts.** Perch already logs through
   `Logger` and measures with `OSSignposter`; `build_and_run.sh --telemetry`
   streams them and Instruments reads the signposts. The HUD complements these
   rather than replacing them. `OSLogStore(scope: .currentProcessIdentifier)` can
   feed an in-app log viewer later.
   ([Use Your Loaf](https://useyourloaf.com/blog/fetching-oslog-messages-in-swift/),
   [Donny Wals](https://www.donnywals.com/modern-logging-with-the-oslog-framework-in-swift/))
5. **Crash-recovery paths need a way to trigger them.** WebKit can kill the
   content process under memory pressure, leaving a blank view; apps handle
   `webViewWebContentProcessDidTerminate`. Killing the renderer on purpose is the
   usual way to test that path.
   ([Never Meant](https://nevermeant.dev/handling-blank-wkwebviews/))

## Not done here

- **Side-by-side install.** A separate bundle ID (for example
  `com.fantomsuj.Perch.dev`) would let a developer build run next to the release
  app, but it would also get its own Notion sign-in, login item, and
  permissions, and the build script currently quits any running Perch. Worth
  doing if running both at once becomes useful.
- **In-app log viewer** using `OSLogStore`.
- **Networking and GPU process metrics.** WebKit exposes no pid for them.
