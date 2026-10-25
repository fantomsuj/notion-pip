#if PERCH_DEVELOPER
import AppKit
import SwiftUI

/// Owns the Developer menu and the live diagnostics HUD in developer builds.
///
/// Sampling runs only while the HUD is open, so a developer build with the HUD
/// closed behaves like a normal debug build.
@MainActor
final class DeveloperToolsController: NSObject, NSWindowDelegate {
    static let sampleInterval: TimeInterval = 1
    static let menuTitle = "Developer"

    private let webSession: NotionWebSession
    private let log: DeveloperDiagnosticsLog
    private let model = DiagnosticsHUDModel()
    private let appProcessID = ProcessInfo.processInfo.processIdentifier
    private var tracker = ProcessResourceTracker()
    private var panel: NSPanel?
    private var timer: Timer?

    init(webSession: NotionWebSession, log: DeveloperDiagnosticsLog = .shared) {
        self.webSession = webSession
        self.log = log
    }

    var isHUDVisible: Bool {
        panel?.isVisible == true
    }

    /// Adds the Developer menu to `mainMenu`. Its shortcuts work while the Perch
    /// panel is focused.
    func install(in mainMenu: NSMenu?) {
        guard let mainMenu, mainMenu.item(withTitle: Self.menuTitle) == nil else { return }
        let item = NSMenuItem(title: Self.menuTitle, action: nil, keyEquivalent: "")
        item.submenu = makeMenu()
        mainMenu.addItem(item)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: Self.menuTitle)
        menu.autoenablesItems = false
        menu.addItem(item("Toggle Diagnostics HUD", #selector(toggleHUD(_:)), key: "d"))
        menu.addItem(item("Copy Diagnostics Report", #selector(copyReport(_:)), key: "c"))
        menu.addItem(.separator())
        menu.addItem(item("Simulate Memory Pressure Warning", #selector(simulateMemoryWarning(_:))))
        menu.addItem(item("Simulate Memory Pressure Critical", #selector(simulateMemoryCritical(_:))))
        menu.addItem(item("Evict Web View If Hidden", #selector(evictWebView(_:))))
        menu.addItem(item("Kill Web Content Process", #selector(killWebContentProcess(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Reset Diagnostics Counters", #selector(resetCounters(_:))))
        return menu
    }

    /// Opens the HUD when Perch was launched with `-PerchShowDiagnosticsHUD YES`.
    func showHUDIfRequestedAtLaunch(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: DeveloperBuild.showHUDAtLaunchDefaultsKey) {
            showHUD()
        }
    }

    func showHUD() {
        let panel = panel ?? makePanel()
        self.panel = panel
        refresh()
        startSampling()
        panel.orderFrontRegardless()
    }

    func hideHUD() {
        panel?.orderOut(nil)
        stopSampling()
    }

    /// Takes one sample and publishes it to the HUD.
    @discardableResult
    func refresh() -> DiagnosticsSnapshot {
        let web = webSession.developerDiagnosticsSnapshot
        var readings: [pid_t: ProcessResourceReading] = [:]
        readings[appProcessID] = ProcessResourceReader.read(pid: appProcessID)
        if let webPID = web.webContentProcessID {
            readings[webPID] = ProcessResourceReader.read(pid: webPID)
        }
        let samples = tracker.sample(readings)
        let snapshot = DiagnosticsSnapshot(
            appVersion: AppMetadata.current.versionAndBuild,
            appProcessID: appProcessID,
            app: samples[appProcessID],
            webContent: web.webContentProcessID.flatMap { samples[$0] },
            web: web,
            counters: log.counters,
            latestIntervals: log.latestIntervalPerOperation,
            recentEvents: log.events
        )
        model.snapshot = snapshot
        return snapshot
    }

    // MARK: - Menu actions

    @objc func toggleHUD(_: Any?) {
        if isHUDVisible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    @objc func copyReport(_: Any?) {
        let report = refresh().report()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        log.record(.developer, "Copied diagnostics report")
    }

    @objc func simulateMemoryWarning(_: Any?) {
        log.record(.developer, "Simulating memory pressure warning")
        webSession.handleMemoryPressure(.warning)
        refresh()
    }

    @objc func simulateMemoryCritical(_: Any?) {
        log.record(.developer, "Simulating memory pressure critical")
        webSession.handleMemoryPressure(.critical)
        refresh()
    }

    @objc func evictWebView(_: Any?) {
        log.record(.developer, "Requested web view eviction")
        webSession.evictWarmWebView()
        refresh()
    }

    @objc func killWebContentProcess(_: Any?) {
        guard let pid = webSession.developerDiagnosticsSnapshot.webContentProcessID else {
            log.record(.developer, "No web content process to kill")
            return
        }
        // Exercises the same recovery path as a real WebKit crash.
        let result = kill(pid, SIGKILL)
        log.record(
            .developer,
            result == 0 ? "Killed web content process \(pid)" : "Could not kill web content process \(pid)"
        )
    }

    @objc func resetCounters(_: Any?) {
        log.reset()
        refresh()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        stopSampling()
    }

    // MARK: - Private

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        // Control-Option-Command keeps these clear of Notion's own shortcuts.
        item.keyEquivalentModifierMask = [.control, .option, .command]
        return item
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = "Perch Diagnostics"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        let hostingView = NSHostingView(rootView: DiagnosticsHUDView(model: model))
        hostingView.sizingOptions = [.preferredContentSize]
        panel.contentView = hostingView
        panel.setFrameAutosaveName("PerchDiagnosticsHUD")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.minX + 24, y: visible.maxY - 24))
        }
        return panel
    }

    private func startSampling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopSampling() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
