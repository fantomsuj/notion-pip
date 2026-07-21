import AppKit
import OSLog
import SwiftUI

@MainActor
protocol PiPPanelWindow: AnyObject {
    func present()
    func orderOut()
}

@MainActor
protocol PiPPanelCoordinating: AnyObject {
    var currentPage: NotionPageReference? { get }
    func show(page: NotionPageReference)
    func hide()
    func replace(page: NotionPageReference)
}

@MainActor
final class PiPPanelCoordinator: PiPPanelCoordinating {
    private static let autosaveName = "NotionPiPPanel"
    private static let defaultSize = CGSize(width: 520, height: 680)

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "panel")
    private let panel: any PiPPanelWindow
    private let pageLoader: any NotionPageLoading
    private(set) var currentPage: NotionPageReference?

    convenience init() {
        let webSession = NotionWebSession()
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let defaultFrame = Self.defaultFrame(visibleFrames: visibleFrames)
        let panel = KeyCapablePiPPanel(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Notion PiP"

        _ = panel.setFrameUsingName(Self.autosaveName)
        _ = panel.setFrameAutosaveName(Self.autosaveName)
        panel.setFrame(
            PanelFramePolicy.clamped(panel.frame, visibleFrames: visibleFrames),
            display: false
        )
        panel.contentView = NSHostingView(
            rootView: PiPChromeView(webSession: webSession) { [weak panel] in
                panel?.orderOut(nil)
            }
        )

        self.init(panel: panel, pageLoader: webSession)
    }

    init(panel: any PiPPanelWindow, pageLoader: any NotionPageLoading) {
        self.panel = panel
        self.pageLoader = pageLoader
    }

    func show(page: NotionPageReference) {
        if currentPage?.pageID != page.pageID {
            pageLoader.load(page: page)
            currentPage = page
        }
        panel.present()
        logger.notice("Panel show requested")
    }

    func hide() {
        panel.orderOut()
    }

    func replace(page: NotionPageReference) {
        show(page: page)
    }

    private static func defaultFrame(visibleFrames: [CGRect]) -> CGRect {
        guard let visibleFrame = visibleFrames.first else {
            return CGRect(origin: .zero, size: defaultSize)
        }

        return CGRect(
            x: visibleFrame.maxX - defaultSize.width - 24,
            y: visibleFrame.maxY - defaultSize.height - 24,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }
}

private final class KeyCapablePiPPanel: NSPanel, PiPPanelWindow {
    override var canBecomeKey: Bool {
        true
    }

    override func close() {
        orderOut(nil)
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }
}
