import AppKit
import OSLog
import QuartzCore
import SwiftUI

@MainActor
protocol PiPPanelWindow: AnyObject {
    var frame: CGRect { get }
    var isVisible: Bool { get }
    var isExpanded: Bool { get }
    var onClose: (@MainActor () -> Void)? { get set }
    func present()
    func orderOut()
    func dismissForStash(
        toward side: PanelStashSide,
        completion: @escaping @MainActor () -> Void
    )
    func restoreFromExpandedState()
    func setFrame(_ frame: CGRect, display: Bool)
    func setFrame(_ frame: CGRect, display: Bool, animate: Bool)
}

extension PiPPanelWindow {
    func setFrame(_ frame: CGRect, display: Bool, animate: Bool) {
        setFrame(frame, display: display)
    }
}

extension PiPPanelWindow {
    func dismissForStash(
        toward side: PanelStashSide,
        completion: @escaping @MainActor () -> Void
    ) {
        orderOut()
        completion()
    }
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
    func performGlobalShortcutAction() -> Bool
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

    func performGlobalShortcutAction() -> Bool {
        stashOrRestoreCurrentPage()
    }
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
    private var cornerSnapTask: Task<Void, Never>?
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

    var presentationState: PiPPresentationState {
        guard currentPage != nil else { return .unavailable }
        return panel.isVisible ? .visible : .stashed
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
        pageSwitcherController: PageSwitcherController = PageSwitcherController(),
        commandModel: AppCommandModel = .noOp,
        quickCopyController: QuickCopyController? = nil,
        onReloadSavedPin: @escaping () -> Void = {},
        panelSizeController: PanelSizeController? = nil,
        onPageSwitcherSelection: @escaping (PageSwitcherSelection) -> Void = { _ in },
        performanceSignposter: (any PerformanceSignposting)? = AppPerformanceSignposter.shared
    ) {
        let stashHandle = PiPStashHandleController()
        let quickCopyController = quickCopyController ?? QuickCopyController(
            monitor: AccessibilitySelectionMonitor(),
            target: webSession
        )
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
        if didRestoreAutosavedFrame {
            let fallbackScreenSize = PanelFramePolicy.targetVisibleFrame(
                for: panel.frame,
                from: visibleFrames
            )?.size ?? NSScreen.main?.visibleFrame.size
                ?? CGSize(width: 1_440, height: 900)
            let fallbackContentSize = panelSizeController?
                .preferences.defaultPreset.contentSize(
                    forScreenSize: fallbackScreenSize
                ).cgSize ?? policy.initialContentSize
            let restoredContentSize = PanelFramePolicy.restoredContentSize(
                savedWorkingContentSize: savedWorkingContentSize,
                restoredFrame: panel.frame,
                visibleFrames: visibleFrames,
                fallbackContentSize: fallbackContentSize,
                frameForContentRect: frameForContentRect,
                contentRectForFrameRect: contentRectForFrameRect
            )
            let placement = PanelFramePolicy.placement(
                preferredContentSize: restoredContentSize,
                anchoredTo: panel.frame,
                visibleFrames: visibleFrames,
                minimumContentSize: policy.minimumContentSize,
                frameForContentRect: frameForContentRect
            )
            panel.setFrame(placement.frame, display: false)
            initialPreferredContentSize = restoredContentSize
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
        let contentView = NSHostingView(
            rootView: PiPChromeView(
                webSession: webSession,
                pageSwitcherController: pageSwitcherController,
                commandModel: commandModel,
                panelSizeController: panelSizeController,
                quickCopyController: quickCopyController,
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
        panel.onClose = { [weak self] in
            _ = self?.stashOrRestoreCurrentPage()
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
        cornerSnapTask?.cancel()
    }

    func show(page: NotionPageReference) {
        show(page: page, restoration: nil)
    }

    func show(page: NotionPageReference, restoration: DurablePageRestoration?) {
        let hadPinnedPage = currentPage != nil
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
        currentPage = page
        panel.present()
        dismissStashHandle()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        pageLoader.reloadPinnedPage(page)
        if !hadPinnedPage {
            onPinnedPageAvailabilityChange?()
        }
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

    func performGlobalShortcutAction() -> Bool {
        guard currentPage != nil else { return false }
        if panel.isVisible, panel.isExpanded {
            panel.restoreFromExpandedState()
            logger.notice("Expanded panel restored to its floating size")
            return true
        }
        return stashOrRestoreCurrentPage()
    }

    func replace(page: NotionPageReference) {
        show(page: page)
    }

    func replace(page: NotionPageReference, restoration: DurablePageRestoration?) {
        show(page: page, restoration: restoration)
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
        presentStashHandle(stashHandle, placement: placement)
        panel.dismissForStash(toward: placement.side) { [weak self] in
            self?.pageLoader.panelDidHide()
        }
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
            let placement = preferredPlacement(
                anchoredTo: panel.frame,
                visibleFrames: visibleFrames
            )
            setPanelFrame(placement.frame, display: true)
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
        guard !panel.isExpanded else {
            logger.debug("Skipped expanded panel resize completion")
            return
        }
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
        let previousVisibleFrame = preferredVisibleFrame
        preferredVisibleFrame = visibleFrame
        preservedFrameAnchor = PanelFramePolicy.nearestAnchor(
            for: panel.frame,
            in: visibleFrame
        )
        scheduleCornerSnap()
        guard previousVisibleFrame != visibleFrame else { return }

        let placement = preferredPlacement(
            anchoredTo: panel.frame,
            visibleFrames: [visibleFrame]
        )
        guard placement.frame != panel.frame else { return }
        setPanelFrame(placement.frame, display: panel.isVisible)
    }

    private func scheduleCornerSnap() {
        cornerSnapTask?.cancel()
        cornerSnapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            guard NSEvent.pressedMouseButtons & 1 == 0 else {
                self?.scheduleCornerSnap()
                return
            }
            self?.snapPanelToCorner()
        }
    }

    func snapPanelToCorner() {
        let visibleFrames = visibleFramesProvider()
        let originalFrame = panel.frame
        let snappedFrame = PanelFramePolicy.cornerSnapped(
            originalFrame,
            visibleFrames: visibleFrames
        )
        guard snappedFrame != originalFrame else { return }
        guard let visibleFrame = PanelFramePolicy.targetVisibleFrame(
            for: originalFrame,
            from: visibleFrames
        ) else { return }
        let nearestAnchor = PanelFramePolicy.nearestAnchor(
            for: originalFrame,
            in: visibleFrame
        )
        preferredVisibleFrame = visibleFrame
        preservedFrameAnchor = PanelFrameAnchor(
            horizontalEdge: nearestAnchor.horizontalEdge,
            horizontalInset: PanelFramePolicy.cornerInset,
            verticalEdge: nearestAnchor.verticalEdge,
            verticalInset: PanelFramePolicy.cornerInset
        )
        setPanelFrame(snappedFrame, display: panel.isVisible, animate: true)
    }

    private func setPanelFrame(_ frame: CGRect, display: Bool, animate: Bool = false) {
        programmaticFrameChangeGeneration &+= 1
        let generation = programmaticFrameChangeGeneration
        isApplyingProgrammaticFrame = true
        panel.setFrame(frame, display: display, animate: animate)
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
    private static let stashNudge: CGFloat = 16
    private static let stashAnimationDuration: TimeInterval = 0.12

    var onClose: (@MainActor () -> Void)?

    var isExpanded: Bool {
        styleMask.contains(.fullScreen) || isZoomed
    }

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

    func restoreFromExpandedState() {
        if styleMask.contains(.fullScreen) {
            toggleFullScreen(nil)
        } else if isZoomed {
            performZoom(nil)
        }
    }

    override func setFrame(_ frame: CGRect, display: Bool, animate: Bool) {
        guard animate else {
            setFrame(frame, display: display)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: display)
        }
    }

    func dismissForStash(
        toward side: PanelStashSide,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            orderOut()
            completion()
            return
        }

        let originalFrame = frame
        let horizontalOffset = side == .left ? -Self.stashNudge : Self.stashNudge
        let targetFrame = originalFrame.offsetBy(dx: horizontalOffset, dy: 0)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.stashAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(targetFrame, display: true)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.setFrame(originalFrame, display: false)
                self.alphaValue = 1
                completion()
            }
        }
    }
}
