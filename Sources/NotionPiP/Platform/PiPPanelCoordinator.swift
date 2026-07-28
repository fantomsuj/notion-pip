import AppKit
import OSLog
import SwiftUI

@MainActor
protocol PiPPanelWindow: AnyObject {
    var frame: CGRect { get }
    var isVisible: Bool { get }
    var onClose: (@MainActor () -> Void)? { get set }
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

enum PiPPresentationState: Equatable, Sendable {
    case unavailable
    case visible
    case stashed
}

@MainActor
protocol PiPPanelCoordinating: AnyObject {
    var currentPage: NotionPageReference? { get }
    var presentationState: PiPPresentationState { get }
    func show(page: NotionPageReference)
    func show(page: NotionPageReference, restoration: DurablePageRestoration?)
    func reloadPinnedPage(_ page: NotionPageReference)
    func showCurrentPage() -> Bool
    func stashOrRestoreCurrentPage() -> Bool
    func replace(page: NotionPageReference)
    func replace(page: NotionPageReference, restoration: DurablePageRestoration?)
}

extension PiPPanelCoordinating {
    func show(page: NotionPageReference, restoration: DurablePageRestoration?) {
        show(page: page)
    }

    func replace(page: NotionPageReference, restoration: DurablePageRestoration?) {
        replace(page: page)
    }
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

    var presentationState: PiPPresentationState {
        guard currentPage != nil else { return .unavailable }
        return panel.isVisible ? .visible : .stashed
    }

    convenience init(
        webSession: NotionWebSession = NotionWebSession(),
        pageSwitcherController: PageSwitcherController = PageSwitcherController(),
        commandModel: AppCommandModel = .noOp,
        onReloadSavedPin: @escaping () -> Void = {},
        onPageSwitcherSelection: @escaping (PageSwitcherSelection) -> Void = { _ in },
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
        let contentView = NSHostingView(
            rootView: PiPChromeView(
                webSession: webSession,
                pageSwitcherController: pageSwitcherController,
                commandModel: commandModel,
                onReloadSavedPin: onReloadSavedPin,
                onStash: { [weak self] in
                    _ = self?.stashOrRestoreCurrentPage()
                },
                onPageSwitcherSelection: onPageSwitcherSelection
            )
        )
        // The retained panel owns its geometry while SwiftUI swaps the WebView in and out.
        contentView.sizingOptions = []
        panel.contentView = contentView
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
        panel.onClose = { [weak self] in
            _ = self?.stashOrRestoreCurrentPage()
        }
    }

    isolated deinit {
        if let screenConfigurationObserver {
            NotificationCenter.default.removeObserver(screenConfigurationObserver)
        }
    }

    func show(page: NotionPageReference) {
        show(page: page, restoration: nil)
    }

    func show(page: NotionPageReference, restoration: DurablePageRestoration?) {
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        if currentPage?.canonicalURL != page.canonicalURL {
            pageLoader.activate(page: page, restoration: restoration)
            currentPage = page
        } else {
            pageLoader.reselect(page: page)
        }
        restoreStashedPanelFrame()
        panel.present()
        dismissStashHandle()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        logger.notice("Panel show requested")
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        restoreStashedPanelFrame()
        currentPage = page
        panel.present()
        dismissStashHandle()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        pageLoader.reloadPinnedPage(page)
        logger.notice("Pinned page reload requested")
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        restoreStashedPanelFrame()
        panel.present()
        dismissStashHandle()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        logger.notice("Existing panel show requested")
        return true
    }

    func stashOrRestoreCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        switch presentationState {
        case .unavailable:
            return false
        case .visible:
            _ = stash(visibleFrames: visibleFramesProvider())
        case .stashed:
            _ = showCurrentPage()
        }
        return true
    }

    func replace(page: NotionPageReference) {
        show(page: page)
    }

    func replace(page: NotionPageReference, restoration: DurablePageRestoration?) {
        show(page: page, restoration: restoration)
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
        presentStashHandle(stashHandle, placement: placement)
        pageLoader.panelDidHide()
        panel.orderOut()
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
        panel.present()
        dismissStashHandle()
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
        guard !visibleFrames.isEmpty else { return }
        guard let activeStashPlacement,
              let placement = PanelStashPolicy.snappedPlacement(
            for: activeStashPlacement.frame,
            visibleFrames: visibleFrames
        ) else {
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
        if let onClose {
            onClose()
        } else {
            orderOut(nil)
        }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }
}
