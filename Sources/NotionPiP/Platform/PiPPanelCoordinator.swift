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
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void
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

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "panel")
    private let panel: any PiPPanelWindow
    private let pageLoader: any NotionPageLoading
    private let stashHandle: (any PiPStashHandle)?
    private let performanceSignposter: (any PerformanceSignposting)?
    private let visibleFramesProvider: @MainActor () -> [CGRect]
    private(set) var currentPage: NotionPageReference?
    private var screenConfigurationObserver: NSObjectProtocol?
    private var initialFrameProvider: (@MainActor () -> CGRect?)?
    private var activeStashPlacement: PanelStashPlacement?
    private var didAttemptFirstPresentation = false
    private var stashedPanelFrame: CGRect?

    var isVisible: Bool {
        panel.isVisible
    }

    convenience init(
        webSession: NotionWebSession = NotionWebSession(),
        commandModel: AppCommandModel = .noOp,
        performanceSignposter: (any PerformanceSignposting)? = AppPerformanceSignposter.shared
    ) {
        let stashHandle = PiPStashHandleController()
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let policy = WindowRole.pictureInPicture.policy
        guard let panel = WindowRole.pictureInPicture.makeWindow() as? KeyCapablePiPPanel else {
            preconditionFailure("PiP role must create KeyCapablePiPPanel")
        }
        panel.title = "Notion PiP"

        let didRestoreAutosavedFrame = panel.setFrameUsingName(Self.autosaveName)
        _ = panel.setFrameAutosaveName(Self.autosaveName)
        if didRestoreAutosavedFrame {
            panel.setFrame(
                PanelFramePolicy.clamped(
                    panel.frame,
                    visibleFrames: visibleFrames,
                    minimumSize: policy.minimumContentSize
                ),
                display: false
            )
        }
        let initialFrameProvider: (@MainActor () -> CGRect?)?
        if didRestoreAutosavedFrame {
            initialFrameProvider = nil
        } else {
            initialFrameProvider = {
                PanelFramePolicy.initialFrame(
                    size: policy.initialContentSize,
                    minimumSize: policy.minimumContentSize,
                    pointerLocation: NSEvent.mouseLocation,
                    screens: NSScreen.screens.map {
                        ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
                    }
                )
            }
        }
        self.init(
            panel: panel,
            pageLoader: webSession,
            stashHandle: stashHandle,
            performanceSignposter: performanceSignposter,
            initialFrameProvider: initialFrameProvider
        )
        panel.onClose = { [weak self] in
            self?.pageLoader.panelDidHide()
        }

        panel.contentView = NSHostingView(
            rootView: PiPChromeView(
                webSession: webSession,
                commandModel: commandModel,
                onStash: { [weak self] in
                    self?.stash(visibleFrames: NSScreen.screens.map(\.visibleFrame))
                }
            )
        )
    }

    init(
        panel: any PiPPanelWindow,
        pageLoader: any NotionPageLoading,
        stashHandle: (any PiPStashHandle)? = nil,
        performanceSignposter: (any PerformanceSignposting)? = nil,
        visibleFramesProvider: @escaping @MainActor () -> [CGRect] = {
            NSScreen.screens.map(\.visibleFrame)
        },
        initialFrameProvider: (@MainActor () -> CGRect?)? = nil
    ) {
        self.panel = panel
        self.pageLoader = pageLoader
        self.stashHandle = stashHandle
        self.performanceSignposter = performanceSignposter
        self.visibleFramesProvider = visibleFramesProvider
        self.initialFrameProvider = initialFrameProvider
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
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        if currentPage?.pageID != page.pageID {
            pageLoader.activate(page: page)
            currentPage = page
        } else {
            pageLoader.reselect(page: page)
        }
        restoreStashedPanelFrame()
        dismissStashHandle()
        panel.present()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        logger.notice("Panel show requested")
    }

    func hide() {
        pageLoader.panelDidHide()
        restoreStashedPanelFrame()
        panel.orderOut()
        dismissStashHandle()
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        restoreStashedPanelFrame()
        dismissStashHandle()
        panel.present()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
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

        stashedPanelFrame = panel.frame
        pageLoader.panelDidHide()
        panel.orderOut()
        presentStashHandle(stashHandle, placement: placement)
        logger.notice("Panel stashed to screen edge")
        return true
    }

    func restoreFromStash() {
        guard currentPage != nil else {
            dismissStashHandle()
            return
        }
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        restoreStashedPanelFrame()
        dismissStashHandle()
        panel.present()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        logger.notice("Panel restored from screen edge")
    }

    func reclampPanelFrame(visibleFrames: [CGRect]) {
        if stashedPanelFrame == nil {
            panel.setFrame(
                PanelFramePolicy.clamped(
                    panel.frame,
                    visibleFrames: visibleFrames,
                    minimumSize: WindowRole.pictureInPicture.policy.minimumContentSize
                ),
                display: true
            )
        }

        guard stashHandle?.isVisible == true else { return }
        guard let activeStashPlacement,
              let placement = PanelStashPolicy.snappedPlacement(
            for: activeStashPlacement.frame,
            visibleFrames: visibleFrames
        ) else {
            dismissStashHandle()
            return
        }
        if let stashHandle {
            presentStashHandle(stashHandle, placement: placement)
        }
    }

    private func dismissStashHandle() {
        activeStashPlacement = nil
        guard stashHandle?.isVisible == true else { return }
        stashHandle?.orderOut()
    }

    private func prepareInitialFrameIfNeeded() {
        guard let initialFrameProvider else { return }
        self.initialFrameProvider = nil
        guard let frame = initialFrameProvider() else { return }
        panel.setFrame(frame, display: false)
    }

    private func beginFirstPresentation() -> (
        signposter: any PerformanceSignposting,
        token: PerformanceIntervalToken?
    )? {
        guard !didAttemptFirstPresentation else { return nil }
        didAttemptFirstPresentation = true
        guard let performanceSignposter else { return nil }
        return (
            performanceSignposter,
            performanceSignposter.begin(.firstPiPPresentation)
        )
    }

    private func endFirstPresentation(
        _ measurement: (
            signposter: any PerformanceSignposting,
            token: PerformanceIntervalToken?
        )?
    ) {
        measurement?.signposter.end(measurement?.token, outcome: .success)
    }

    private func presentStashHandle(
        _ stashHandle: any PiPStashHandle,
        placement: PanelStashPlacement
    ) {
        activeStashPlacement = placement
        stashHandle.present(
            placement: placement,
            onRestore: { [weak self] in
                self?.restoreFromStash()
            },
            onPlacementChange: { [weak self] placement in
                self?.activeStashPlacement = placement
            }
        )
    }

    private func restoreStashedPanelFrame() {
        guard let stashedPanelFrame else { return }
        panel.setFrame(
            PanelFramePolicy.clamped(
                stashedPanelFrame,
                visibleFrames: visibleFramesProvider(),
                minimumSize: WindowRole.pictureInPicture.policy.minimumContentSize
            ),
            display: false
        )
        self.stashedPanelFrame = nil
    }
}

final class KeyCapablePiPPanel: NSPanel, PiPPanelWindow {
    var onClose: (@MainActor () -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override func close() {
        onClose?()
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
