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
protocol PiPStashHandle: AnyObject {
    var isVisible: Bool { get }
    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void
    )
    func orderOut()
}

@MainActor
protocol PiPPanelCoordinating: AnyObject {
    var currentPage: NotionPageReference? { get }
    var isVisible: Bool { get }
    func show(page: NotionPageReference)
    func showCurrentPage() -> Bool
    func hide()
    func toggleCurrentPage() -> Bool
    func stashOrRestoreCurrentPage() -> Bool
    func replace(page: NotionPageReference)
}

@MainActor
final class PiPPanelCoordinator: PiPPanelCoordinating {
    private static let autosaveName = "NotionPiPPanel"
    private static let defaultSize = CGSize(width: 520, height: 680)

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "panel")
    private let panel: any PiPPanelWindow
    private let pageLoader: any NotionPageLoading
    private let stashHandle: (any PiPStashHandle)?
    private let visibleFramesProvider: @MainActor () -> [CGRect]
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
        let stashHandle = PiPStashHandleController()
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
        self.init(panel: panel, pageLoader: webSession, stashHandle: stashHandle)

        panel.contentView = NSHostingView(
            rootView: PiPChromeView(
                webSession: webSession,
                nativePageDocument: nativePageDocument,
                commandModel: commandModel,
                onStash: { [weak self] in
                    self?.stash(visibleFrames: NSScreen.screens.map(\.visibleFrame))
                },
                onHide: { [weak self] in
                    self?.hide()
                }
            )
        )
    }

    init(
        panel: any PiPPanelWindow,
        pageLoader: any NotionPageLoading,
        stashHandle: (any PiPStashHandle)? = nil,
        visibleFramesProvider: @escaping @MainActor () -> [CGRect] = {
            NSScreen.screens.map(\.visibleFrame)
        }
    ) {
        self.panel = panel
        self.pageLoader = pageLoader
        self.stashHandle = stashHandle
        self.visibleFramesProvider = visibleFramesProvider
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
        dismissStashHandle()
        panel.present()
        logger.notice("Panel show requested")
    }

    func hide() {
        panel.orderOut()
        dismissStashHandle()
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        dismissStashHandle()
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

    func stashOrRestoreCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        if panel.isVisible {
            if !stash(visibleFrames: visibleFramesProvider()) {
                hide()
            }
        } else {
            _ = showCurrentPage()
        }
        return true
    }

    func replace(page: NotionPageReference) {
        show(page: page)
    }

    @discardableResult
    func stash(visibleFrames: [CGRect]) -> Bool {
        guard currentPage != nil,
              let stashHandle,
              let placement = PanelStashPolicy.placement(
                  for: panel.frame,
                  visibleFrames: visibleFrames
              )
        else {
            return false
        }

        panel.orderOut()
        stashHandle.present(placement: placement) { [weak self] in
            self?.restoreFromStash()
        }
        logger.notice("Panel stashed to screen edge")
        return true
    }

    func restoreFromStash() {
        guard currentPage != nil else {
            dismissStashHandle()
            return
        }
        dismissStashHandle()
        panel.present()
        logger.notice("Panel restored from screen edge")
    }

    func reclampPanelFrame(visibleFrames: [CGRect]) {
        panel.setFrame(
            PanelFramePolicy.clamped(panel.frame, visibleFrames: visibleFrames),
            display: true
        )

        guard stashHandle?.isVisible == true else { return }
        guard let placement = PanelStashPolicy.placement(
            for: panel.frame,
            visibleFrames: visibleFrames
        ) else {
            dismissStashHandle()
            return
        }
        stashHandle?.present(placement: placement) { [weak self] in
            self?.restoreFromStash()
        }
    }

    private func dismissStashHandle() {
        guard stashHandle?.isVisible == true else { return }
        stashHandle?.orderOut()
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
