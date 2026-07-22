import AppKit
import OSLog
import SwiftUI

@MainActor
protocol PiPPanelWindow: AnyObject {
    var frame: CGRect { get }
    var isVisible: Bool { get }
    func present()
    func orderOut()
    func setFrame(_ frame: CGRect, display: Bool)
}

@MainActor
protocol PiPPanelCoordinating: AnyObject {
    var currentPage: NotionPageReference? { get }
    var isVisible: Bool { get }
    func show(page: NotionPageReference)
    func showCurrentPage() -> Bool
    func hide()
    func toggleCurrentPage() -> Bool
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
    private var screenConfigurationObserver: NSObjectProtocol?

    var isVisible: Bool {
        panel.isVisible
    }

    convenience init(
        nativePageDocument: NativePageDocument = NativePageDocument(),
        commandModel: AppCommandModel = .noOp
    ) {
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
            rootView: PiPChromeView(
                webSession: webSession,
                nativePageDocument: nativePageDocument,
                commandModel: commandModel
            ) { [weak panel] in
                panel?.orderOut(nil)
            }
        )

        self.init(panel: panel, pageLoader: webSession)
    }

    init(panel: any PiPPanelWindow, pageLoader: any NotionPageLoading) {
        self.panel = panel
        self.pageLoader = pageLoader
        screenConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reclampPanelFrame(visibleFrames: NSScreen.screens.map(\.visibleFrame))
            }
        }
    }

    isolated deinit {
        if let screenConfigurationObserver {
            NotificationCenter.default.removeObserver(screenConfigurationObserver)
        }
    }

    func show(page: NotionPageReference) {
        if currentPage?.pageID != page.pageID {
            pageLoader.activate(page: page)
            currentPage = page
        }
        panel.present()
        logger.notice("Panel show requested")
    }

    func hide() {
        panel.orderOut()
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        panel.present()
        logger.notice("Existing panel show requested")
        return true
    }

    func toggleCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        if isVisible {
            hide()
        } else {
            _ = showCurrentPage()
        }
        return true
    }

    func replace(page: NotionPageReference) {
        show(page: page)
    }

    func reclampPanelFrame(visibleFrames: [CGRect]) {
        panel.setFrame(
            PanelFramePolicy.clamped(panel.frame, visibleFrames: visibleFrames),
            display: true
        )
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
