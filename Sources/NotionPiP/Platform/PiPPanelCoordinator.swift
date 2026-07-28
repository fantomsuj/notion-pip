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
    func reloadPinnedPage(_ page: NotionPageReference)
    func showCurrentPage() -> Bool
    func hide()
    func toggleCurrentPage() -> Bool
    func stashOrRestoreCurrentPage() -> Bool
    func replace(page: NotionPageReference)
}

@MainActor
final class PiPPanelCoordinator: PiPPanelCoordinating, PanelSizing {
    private static let autosaveName = "NotionPiPPanel"

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "panel")
    private let panel: any PiPPanelWindow
    private let pageLoader: any NotionPageLoading
    private let stashHandle: (any PiPStashHandle)?
    private let performanceSignposter: (any PerformanceSignposting)?
    private let visibleFramesProvider: @MainActor () -> [CGRect]
    private let frameForContentRect: @MainActor (CGRect) -> CGRect
    private let contentRectForFrameRect: @MainActor (CGRect) -> CGRect
    private(set) var currentPage: NotionPageReference?
    private var screenConfigurationObserver: NSObjectProtocol?
    private var liveResizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var initialFrameProvider: (@MainActor () -> CGRect?)?
    private var activeStashPlacement: PanelStashPlacement?
    private var didAttemptFirstPresentation = false
    private var stashedPanelFrame: CGRect?
    private var preferredWorkingContentSize: CGSize
    private var preservedFrameAnchor: PanelFrameAnchor?
    private var preferredVisibleFrame: CGRect?
    private var programmaticFrameChangeGeneration = 0
    private var isApplyingProgrammaticFrame = false

    var onManualResizeCompletion: (@MainActor (CGSize) -> Void)?
    var onPinnedPageAvailabilityChange: (@MainActor () -> Void)?

    var isVisible: Bool {
        panel.isVisible
    }

    var hasPinnedPage: Bool {
        currentPage != nil
    }

    var currentPanelContentSize: CGSize {
        PanelFramePolicy.contentSize(
            forFrame: stashedPanelFrame ?? panel.frame,
            contentRectForFrameRect: contentRectForFrameRect
        )
    }

    var sizingScreenSize: CGSize {
        let logicalFrame = stashedPanelFrame ?? panel.frame
        return PanelFramePolicy.targetVisibleFrame(
            for: logicalFrame,
            from: visibleFramesProvider()
        )?.size ?? NSScreen.main?.visibleFrame.size
            ?? CGSize(width: 1_440, height: 900)
    }

    convenience init(
        webSession: NotionWebSession = NotionWebSession(),
        commandModel: AppCommandModel = .noOp,
        onReloadSavedPin: @escaping () -> Void = {},
        panelSizeController: PanelSizeController? = nil,
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
        let frameForContentRect: @MainActor (CGRect) -> CGRect = {
            panel.frameRect(forContentRect: $0)
        }
        let contentRectForFrameRect: @MainActor (CGRect) -> CGRect = {
            panel.contentRect(forFrameRect: $0)
        }
        let savedWorkingContentSize = panelSizeController?
            .preferences.lastExplicitWorkingContentSize?.cgSize
        var initialPreferredContentSize: CGSize?
        if didRestoreAutosavedFrame, let savedWorkingContentSize {
            let placement = PanelFramePolicy.placement(
                preferredContentSize: savedWorkingContentSize,
                anchoredTo: panel.frame,
                visibleFrames: visibleFrames,
                minimumContentSize: policy.minimumContentSize,
                frameForContentRect: frameForContentRect
            )
            panel.setFrame(placement.frame, display: false)
            initialPreferredContentSize = savedWorkingContentSize
        } else if didRestoreAutosavedFrame {
            let minimumFrameSize = PanelFramePolicy.frameSize(
                forContentSize: policy.minimumContentSize,
                frameForContentRect: frameForContentRect
            )
            panel.setFrame(
                PanelFramePolicy.clamped(
                    panel.frame,
                    visibleFrames: visibleFrames,
                    minimumSize: minimumFrameSize
                ),
                display: false
            )
            initialPreferredContentSize = PanelFramePolicy.contentSize(
                forFrame: panel.frame,
                contentRectForFrameRect: contentRectForFrameRect
            )
        }
        let initialFrameProvider: (@MainActor () -> CGRect?)?
        if didRestoreAutosavedFrame {
            initialFrameProvider = nil
        } else {
            initialFrameProvider = {
                let screens = NSScreen.screens.map {
                    ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
                }
                let targetScreen =
                    screens.first {
                        $0.frame.contains(NSEvent.mouseLocation)
                    } ?? screens.first
                let contentSize =
                    savedWorkingContentSize
                    ?? panelSizeController?.preferences.defaultPreset.contentSize(
                        forScreenSize: targetScreen?.visibleFrame.size
                            ?? CGSize(width: 1_440, height: 900)
                    ).cgSize
                    ?? policy.initialContentSize
                return PanelFramePolicy.initialFrame(
                    contentSize: contentSize,
                    minimumContentSize: policy.minimumContentSize,
                    pointerLocation: NSEvent.mouseLocation,
                    screens: screens,
                    frameForContentRect: frameForContentRect
                )
            }
        }
        self.init(
            panel: panel,
            pageLoader: webSession,
            stashHandle: stashHandle,
            performanceSignposter: performanceSignposter,
            initialFrameProvider: initialFrameProvider,
            initialPreferredContentSize: initialPreferredContentSize,
            frameForContentRect: frameForContentRect,
            contentRectForFrameRect: contentRectForFrameRect
        )
        panelSizeController?.bind(to: self)
        panel.onClose = { [weak self] in
            self?.pageLoader.panelDidHide()
        }

        let contentView = NSHostingView(
            rootView: PiPChromeView(
                webSession: webSession,
                commandModel: commandModel,
                panelSizeController: panelSizeController,
                onReloadSavedPin: onReloadSavedPin,
                onStash: { [weak self] in
                    self?.stash(visibleFrames: NSScreen.screens.map(\.visibleFrame))
                }
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
        initialFrameProvider: (@MainActor () -> CGRect?)? = nil,
        initialPreferredContentSize: CGSize? = nil,
        frameForContentRect: @escaping @MainActor (CGRect) -> CGRect = { $0 },
        contentRectForFrameRect: @escaping @MainActor (CGRect) -> CGRect = { $0 }
    ) {
        self.panel = panel
        self.pageLoader = pageLoader
        self.stashHandle = stashHandle
        self.performanceSignposter = performanceSignposter
        self.visibleFramesProvider = visibleFramesProvider
        self.initialFrameProvider = initialFrameProvider
        self.frameForContentRect = frameForContentRect
        self.contentRectForFrameRect = contentRectForFrameRect
        preferredWorkingContentSize =
            initialPreferredContentSize
            ?? PanelFramePolicy.contentSize(
                forFrame: panel.frame,
                contentRectForFrameRect: contentRectForFrameRect
            )
        if initialPreferredContentSize != nil,
            let visibleFrame = PanelFramePolicy.targetVisibleFrame(
                for: panel.frame,
                from: visibleFramesProvider()
            )
        {
            preferredVisibleFrame = visibleFrame
            preservedFrameAnchor = PanelFramePolicy.nearestAnchor(
                for: panel.frame,
                in: visibleFrame
            )
        }
        screenConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reclampPanelFrame(visibleFrames: NSScreen.screens.map(\.visibleFrame))
            }
        }
        liveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordManualResizeCompletion()
            }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordPanelMove()
            }
        }
    }

    isolated deinit {
        if let screenConfigurationObserver {
            NotificationCenter.default.removeObserver(screenConfigurationObserver)
        }
        if let liveResizeObserver {
            NotificationCenter.default.removeObserver(liveResizeObserver)
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    func show(page: NotionPageReference) {
        let hadPinnedPage = currentPage != nil
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        if currentPage?.canonicalURL != page.canonicalURL {
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
        if !hadPinnedPage {
            onPinnedPageAvailabilityChange?()
        }
        logger.notice("Panel show requested")
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        let hadPinnedPage = currentPage != nil
        let measurement = beginFirstPresentation()
        prepareInitialFrameIfNeeded()
        restoreStashedPanelFrame()
        dismissStashHandle()
        currentPage = page
        panel.present()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        pageLoader.reloadPinnedPage(page)
        if !hadPinnedPage {
            onPinnedPageAvailabilityChange?()
        }
        logger.notice("Pinned page reload requested")
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
    func applyPanelContentSize(_ contentSize: CGSize) -> Bool {
        guard currentPage != nil else { return false }

        let wasVisible = panel.isVisible
        let logicalFrame = stashedPanelFrame ?? panel.frame
        preferredWorkingContentSize = contentSize
        preservedFrameAnchor = nil
        preferredVisibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: logicalFrame,
            from: visibleFramesProvider()
        )
        let placement = preferredPlacement(
            anchoredTo: logicalFrame,
            visibleFrames: visibleFramesProvider()
        )
        setPanelFrame(placement.frame, display: wasVisible)
        stashedPanelFrame = nil
        dismissStashHandle()

        if !wasVisible {
            panel.present()
            pageLoader.panelDidShow()
        }
        logger.notice("Panel content size applied")
        return true
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
            let placement = preferredPlacement(
                anchoredTo: panel.frame,
                visibleFrames: visibleFrames
            )
            setPanelFrame(placement.frame, display: true)
        }

        guard stashHandle?.isVisible == true else { return }
        guard let activeStashPlacement,
            let placement = PanelStashPolicy.snappedPlacement(
                for: activeStashPlacement.frame,
                visibleFrames: visibleFrames
            )
        else {
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
        setPanelFrame(frame, display: false)
        preferredWorkingContentSize = PanelFramePolicy.contentSize(
            forFrame: frame,
            contentRectForFrameRect: contentRectForFrameRect
        )
        preferredVisibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: frame,
            from: visibleFramesProvider()
        )
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
        let placement = preferredPlacement(
            anchoredTo: stashedPanelFrame,
            visibleFrames: visibleFramesProvider()
        )
        setPanelFrame(placement.frame, display: false)
        self.stashedPanelFrame = nil
    }

    private func preferredPlacement(
        anchoredTo frame: CGRect,
        visibleFrames: [CGRect]
    ) -> PanelFramePlacement {
        if preservedFrameAnchor == nil, let preferredVisibleFrame {
            preservedFrameAnchor = PanelFramePolicy.nearestAnchor(
                for: frame,
                in: preferredVisibleFrame
            )
        }
        let placementFrames: [CGRect]
        if let preferredVisibleFrame,
            visibleFrames.contains(preferredVisibleFrame)
        {
            placementFrames = [preferredVisibleFrame]
        } else {
            placementFrames = visibleFrames
        }
        let placement = PanelFramePolicy.placement(
            preferredContentSize: preferredWorkingContentSize,
            anchoredTo: frame,
            visibleFrames: placementFrames,
            minimumContentSize: WindowRole.pictureInPicture.policy.minimumContentSize,
            preserving: preservedFrameAnchor,
            frameForContentRect: frameForContentRect
        )
        preservedFrameAnchor = placement.anchor
        if preferredVisibleFrame == nil {
            preferredVisibleFrame = PanelFramePolicy.targetVisibleFrame(
                for: frame,
                from: visibleFrames
            )
        }
        return placement
    }

    private func recordManualResizeCompletion() {
        let contentSize = currentPanelContentSize
        preferredWorkingContentSize = contentSize
        preservedFrameAnchor = nil
        preferredVisibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: panel.frame,
            from: visibleFramesProvider()
        )
        onManualResizeCompletion?(contentSize)
    }

    func recordPanelMove() {
        guard !isApplyingProgrammaticFrame,
            let visibleFrame = PanelFramePolicy.targetVisibleFrame(
                for: panel.frame,
                from: visibleFramesProvider()
            )
        else {
            return
        }
        preferredVisibleFrame = visibleFrame
        preservedFrameAnchor = PanelFramePolicy.nearestAnchor(
            for: panel.frame,
            in: visibleFrame
        )
    }

    private func setPanelFrame(_ frame: CGRect, display: Bool) {
        programmaticFrameChangeGeneration &+= 1
        let generation = programmaticFrameChangeGeneration
        isApplyingProgrammaticFrame = true
        panel.setFrame(frame, display: display)
        Task { @MainActor [weak self] in
            guard let self,
                programmaticFrameChangeGeneration == generation
            else {
                return
            }
            isApplyingProgrammaticFrame = false
        }
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
