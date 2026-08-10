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
    func cancelPendingStashDismissal()
    func restoreFromExpandedState()
    func setFrame(_ frame: CGRect, display: Bool)
    func setFrame(_ frame: CGRect, display: Bool, animate: Bool)
}

extension PiPPanelWindow {
    func cancelPendingStashDismissal() {}

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
    var onExternalPresentationAction: (@MainActor () -> Void)? { get set }
    var currentPage: NotionPageReference? { get }
    var presentationState: PiPPresentationState { get }
    func show(page: NotionPageReference)
    func show(page: NotionPageReference, restoration: DurablePageRestoration?)
    func reloadPinnedPage(_ page: NotionPageReference)
    func showCurrentPage() -> Bool
    func showCurrentPageFromShortcut(
        measurement: ShortcutPresentationMeasurement
    ) -> Bool
    func stashCurrentPageImmediately() -> Bool
    func stashOrRestoreCurrentPage() -> Bool
    func performGlobalShortcutAction() -> Bool
    func replace(page: NotionPageReference)
    func replace(page: NotionPageReference, restoration: DurablePageRestoration?)
}

extension PiPPanelCoordinating {
    var onExternalPresentationAction: (@MainActor () -> Void)? {
        get { nil }
        set {}
    }

    func show(page: NotionPageReference, restoration: DurablePageRestoration?) {
        show(page: page)
    }

    func replace(page: NotionPageReference, restoration: DurablePageRestoration?) {
        replace(page: page)
    }

    func performGlobalShortcutAction() -> Bool {
        stashOrRestoreCurrentPage()
    }

    func showCurrentPageFromShortcut(
        measurement: ShortcutPresentationMeasurement
    ) -> Bool {
        let result = showCurrentPage()
        let outcome: PerformanceOutcome = result ? .success : .failure
        let metadata = PerformanceMetadata(webViewRetention: .unknown)
        measurement.signposter.end(
            measurement.requestToken,
            outcome: outcome,
            metadata: metadata
        )
        measurement.signposter.end(
            measurement.usefulContentToken,
            outcome: outcome,
            metadata: metadata
        )
        return result
    }

    func stashCurrentPageImmediately() -> Bool {
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
    private let displayTopologyObserver: (any DisplayTopologyObserving)?
    private let displayTopologyProvider: @MainActor () -> DisplayTopology
    private let frameForContentRect: @MainActor (CGRect) -> CGRect
    private let contentRectForFrameRect: @MainActor (CGRect) -> CGRect
    private let geometryStore: any PanelGeometryPersisting
    private(set) var currentPage: NotionPageReference?
    private var liveResizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var cornerSnapTask: Task<Void, Never>?
    private var initialFrameProvider: (@MainActor () -> CGRect?)?
    private var activeStashPlacement: PanelStashPlacement?
    private var activeStashIntent: PanelStashIntent?
    private var latestTopology: DisplayTopology
    private var lastAcceptedTopologyRevision: UInt64
    private var didAttemptFirstPresentation = false
    private var committedGeometry: PanelGeometry?
    private var isStashDismissalActive = false
    private var programmaticFrameChangeGeneration = 0
    private var isApplyingProgrammaticFrame = false

    var onManualResizeCompletion: (@MainActor (CGSize) -> Void)?
    var onPinnedPageAvailabilityChange: (@MainActor () -> Void)?
    var onGeometryPersistenceFailure: (@MainActor () -> Void)?
    var onExternalPresentationAction: (@MainActor () -> Void)?

    var presentationState: PiPPresentationState {
        guard currentPage != nil else { return .unavailable }
        return panel.isVisible ? .visible : .stashed
    }

    var hasPinnedPage: Bool {
        currentPage != nil
    }

    var currentPanelContentSize: CGSize {
        PanelFramePolicy.contentSize(
            forFrame: panel.frame,
            contentRectForFrameRect: contentRectForFrameRect
        )
    }

    var sizingScreenSize: CGSize {
        if let committedGeometry {
            return committedGeometry.visibleFrame.size
        }
        return PanelFramePolicy.targetVisibleFrame(
            for: panel.frame,
            from: currentTopology().visibleFrames
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
        let displayTopologyObserver = AppKitDisplayTopologyObserver()
        let initialTopology = displayTopologyObserver.currentTopology
        let visibleFrames = initialTopology.visibleFrames
        let policy = WindowRole.pictureInPicture.policy
        guard let panel = WindowRole.pictureInPicture.makeWindow() as? KeyCapablePiPPanel else {
            preconditionFailure("PiP role must create KeyCapablePiPPanel")
        }
        panel.title = "Notion PiP"

        let geometryStore = PanelGeometryStore()
        let storedGeometry = geometryStore.load()
        let didRestoreAutosavedFrame: Bool
        if storedGeometry == nil {
            didRestoreAutosavedFrame = panel.setFrameUsingName(Self.autosaveName)
            _ = panel.setFrameAutosaveName(Self.autosaveName)
        } else {
            didRestoreAutosavedFrame = false
            _ = panel.setFrameAutosaveName("")
        }
        let frameForContentRect: @MainActor (CGRect) -> CGRect = {
            panel.frameRect(forContentRect: $0)
        }
        let contentRectForFrameRect: @MainActor (CGRect) -> CGRect = {
            panel.contentRect(forFrameRect: $0)
        }
        let savedWorkingContentSize = panelSizeController?
            .preferences.lastExplicitWorkingContentSize?.cgSize
        var initialGeometry = storedGeometry
        if let storedGeometry {
            panel.setFrame(
                PanelGeometryPolicy.resolvedFrame(
                    for: storedGeometry,
                    visibleFrames: visibleFrames,
                    minimumContentSize: policy.minimumContentSize,
                    frameForContentRect: frameForContentRect
                ),
                display: false
            )
        } else if didRestoreAutosavedFrame {
            initialGeometry = PanelGeometryPolicy.capture(
                frame: panel.frame,
                visibleFrames: visibleFrames,
                contentRectForFrameRect: contentRectForFrameRect
            )
            if let initialGeometry {
                try? geometryStore.save(initialGeometry)
            }
        }
        let initialFrameProvider: (@MainActor () -> CGRect?)?
        if didRestoreAutosavedFrame {
            initialFrameProvider = nil
        } else {
            initialFrameProvider = {
                let screens = displayTopologyObserver.currentTopology.displays.map {
                    ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
                }
                let targetScreen =
                    screens.first {
                        $0.frame.contains(NSEvent.mouseLocation)
                    } ?? screens.first
                let contentSize =
                    savedWorkingContentSize
                    ?? BuiltInPanelSizePreset.vertical.contentSize(
                        forScreenSize: targetScreen?.visibleFrame.size
                            ?? CGSize(width: 1_440, height: 900)
                    ).cgSize
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
            displayTopologyObserver: displayTopologyObserver,
            displayTopologyProvider: { displayTopologyObserver.currentTopology },
            visibleFramesProvider: { displayTopologyObserver.currentTopology.visibleFrames },
            initialFrameProvider: initialFrameProvider,
            initialGeometry: initialGeometry,
            geometryStore: geometryStore,
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
                    self?.onExternalPresentationAction?()
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
        displayTopologyObserver: (any DisplayTopologyObserving)? = nil,
        displayTopologyProvider: (@MainActor () -> DisplayTopology)? = nil,
        visibleFramesProvider: @escaping @MainActor () -> [CGRect] = {
            NSScreen.screens.map(\.visibleFrame)
        },
        initialFrameProvider: (@MainActor () -> CGRect?)? = nil,
        initialPreferredContentSize: CGSize? = nil,
        initialGeometry: PanelGeometry? = nil,
        geometryStore: any PanelGeometryPersisting = TransientPanelGeometryStore(),
        frameForContentRect: @escaping @MainActor (CGRect) -> CGRect = { $0 },
        contentRectForFrameRect: @escaping @MainActor (CGRect) -> CGRect = { $0 }
    ) {
        self.panel = panel
        self.pageLoader = pageLoader
        self.stashHandle = stashHandle
        self.performanceSignposter = performanceSignposter
        self.displayTopologyObserver = displayTopologyObserver
        let initialTopology = displayTopologyProvider?()
            ?? Self.syntheticTopology(
                visibleFrames: visibleFramesProvider(),
                revision: 0
            )
        self.displayTopologyProvider = displayTopologyProvider
            ?? {
                Self.syntheticTopology(
                    visibleFrames: visibleFramesProvider(),
                    revision: 0
                )
            }
        latestTopology = initialTopology
        lastAcceptedTopologyRevision = initialTopology.revision
        self.initialFrameProvider = initialFrameProvider
        self.geometryStore = geometryStore
        self.frameForContentRect = frameForContentRect
        self.contentRectForFrameRect = contentRectForFrameRect
        let actualContentSize = PanelFramePolicy.contentSize(
            forFrame: panel.frame,
            contentRectForFrameRect: contentRectForFrameRect
        )
        let initialDesiredContentSize = initialPreferredContentSize == actualContentSize
            ? initialPreferredContentSize
            : nil
        committedGeometry = initialGeometry
            ?? geometryStore.load()
            ?? PanelGeometryPolicy.capture(
                frame: panel.frame,
                topology: initialTopology,
                desiredContentSize: initialDesiredContentSize,
                contentRectForFrameRect: contentRectForFrameRect
            )
        displayTopologyObserver?.start { [weak self] topology in
            self?.applyDisplayTopology(topology)
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
            self?.onExternalPresentationAction?()
            _ = self?.stashOrRestoreCurrentPage()
        }
    }

    isolated deinit {
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
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        if currentPage?.canonicalURL != page.canonicalURL {
            pageLoader.activate(page: page, restoration: restoration)
            currentPage = page
        } else {
            pageLoader.reselect(page: page)
        }
        restoreCommittedPanelFrame()
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
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        restoreCommittedPanelFrame()
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
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        restoreCommittedPanelFrame()
        panel.present()
        dismissStashHandle()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        logger.notice("Existing panel show requested")
        return true
    }

    func showCurrentPageFromShortcut(
        measurement: ShortcutPresentationMeasurement
    ) -> Bool {
        guard currentPage != nil else {
            measurement.signposter.end(measurement.requestToken, outcome: .failure)
            measurement.signposter.end(measurement.usefulContentToken, outcome: .failure)
            return false
        }
        let retention = pageLoader.webViewRetention
        pageLoader.beginShortcutPresentationMeasurement(
            signposter: measurement.signposter,
            token: measurement.usefulContentToken,
            retention: retention
        )
        let firstPresentationMeasurement = beginFirstPresentation()
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        restoreCommittedPanelFrame()
        panel.present()
        measurement.signposter.end(
            measurement.requestToken,
            outcome: .success,
            metadata: PerformanceMetadata(webViewRetention: retention)
        )
        dismissStashHandle()
        endFirstPresentation(firstPresentationMeasurement)
        pageLoader.panelDidShow()
        logger.notice("Existing panel show requested from shortcut")
        return true
    }

    func stashOrRestoreCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        switch presentationState {
        case .unavailable:
            return false
        case .visible:
            _ = stash(topology: currentTopology())
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
        onExternalPresentationAction?()
        guard currentPage != nil else { return false }

        cancelPendingStashDismissal()
        let wasVisible = panel.isVisible
        let topology = currentTopology()
        let visibleFrames = topology.visibleFrames
        let logicalFrame = committedGeometry?.frame ?? panel.frame
        let anchor = committedGeometry?.anchor
            ?? PanelFramePolicy.targetVisibleFrame(for: logicalFrame, from: visibleFrames)
                .map { PanelFramePolicy.nearestAnchor(for: logicalFrame, in: $0) }
        let placement = PanelFramePolicy.placement(
            preferredContentSize: contentSize,
            anchoredTo: logicalFrame,
            visibleFrames: visibleFrames,
            minimumContentSize: WindowRole.pictureInPicture.policy.minimumContentSize,
            preserving: anchor,
            frameForContentRect: frameForContentRect
        )
        setPanelFrame(placement.frame, display: wasVisible)
        commitCurrentGeometry(desiredContentSize: contentSize, topology: topology)
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
        let revision = max(lastAcceptedTopologyRevision, latestTopology.revision) &+ 1
        return stash(
            topology: Self.syntheticTopology(
                visibleFrames: visibleFrames,
                revision: revision
            )
        )
    }

    func stashCurrentPageImmediately() -> Bool {
        let token = performanceSignposter?.begin(.peekRestash)
        let result = stashImmediately(topology: currentTopology())
        performanceSignposter?.end(token, outcome: result ? .success : .failure)
        return result
    }

    @discardableResult
    private func stash(topology: DisplayTopology) -> Bool {
        guard currentPage != nil,
            let stashHandle,
            let placement = PanelStashPolicy.placement(
                for: panel.frame,
                visibleFrames: topology.visibleFrames
            )
        else {
            return false
        }

        latestTopology = topology
        commitCurrentGeometry(
            desiredContentSize: committedGeometry?.desiredContentSize.cgSize,
            topology: topology
        )
        activeStashIntent = PanelStashPolicy.intent(for: placement, topology: topology)
        presentStashHandle(stashHandle, placement: placement)
        isStashDismissalActive = true
        panel.dismissForStash(toward: placement.side) { [weak self] in
            guard let self else { return }
            isStashDismissalActive = false
            pageLoader.panelDidHide()
        }
        logger.notice("Panel stashed to screen edge")
        return true
    }

    private func stashImmediately(topology: DisplayTopology) -> Bool {
        guard currentPage != nil,
            let stashHandle,
            let placement = PanelStashPolicy.placement(
                for: panel.frame,
                visibleFrames: topology.visibleFrames
            )
        else {
            return false
        }

        latestTopology = topology
        commitCurrentGeometry(
            desiredContentSize: committedGeometry?.desiredContentSize.cgSize,
            topology: topology
        )
        activeStashIntent = PanelStashPolicy.intent(for: placement, topology: topology)
        presentStashHandle(stashHandle, placement: placement)
        cancelPendingStashDismissal()
        panel.orderOut()
        pageLoader.panelDidHide()
        logger.notice("Temporary peek stashed immediately")
        return true
    }

    func restoreFromStash() {
        onExternalPresentationAction?()
        guard currentPage != nil else {
            dismissStashHandle()
            return
        }
        let measurement = beginFirstPresentation()
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        restoreCommittedPanelFrame()
        panel.present()
        dismissStashHandle()
        endFirstPresentation(measurement)
        pageLoader.panelDidShow()
        logger.notice("Panel restored from screen edge")
    }

    func reclampPanelFrame(visibleFrames: [CGRect]) {
        let revision = max(lastAcceptedTopologyRevision, latestTopology.revision) &+ 1
        applyDisplayTopology(
            Self.syntheticTopology(
                visibleFrames: visibleFrames,
                revision: revision
            )
        )
    }

    func applyDisplayTopology(_ topology: DisplayTopology) {
        let presentation: PanelTopologyPresentation
        if panel.isVisible, panel.isExpanded {
            presentation = .expanded
        } else if panel.isVisible {
            presentation = .visible
        } else if stashHandle?.isVisible == true, let activeStashIntent {
            presentation = .stashed(activeStashIntent)
        } else {
            presentation = .hidden
        }

        guard let decision = PanelTopologyPolicy.resolve(
            committedGeometry: committedGeometry,
            currentPanelFrame: panel.frame,
            fallbackContentSize: currentPanelContentSize,
            presentation: presentation,
            lastAcceptedRevision: lastAcceptedTopologyRevision,
            topology: topology,
            minimumContentSize: WindowRole.pictureInPicture.policy.minimumContentSize,
            frameForContentRect: frameForContentRect
        ) else {
            return
        }

        latestTopology = topology
        lastAcceptedTopologyRevision = decision.acceptedRevision
        if let frame = decision.panelFrame, frame != panel.frame {
            setPanelFrame(frame, display: decision.panelFrameShouldDisplay)
        }
        if let placement = decision.stashPlacement, let stashHandle {
            presentStashHandle(stashHandle, placement: placement)
        }
    }

    private func dismissStashHandle() {
        activeStashPlacement = nil
        activeStashIntent = nil
        guard stashHandle?.isVisible == true else { return }
        stashHandle?.orderOut()
    }

    private func cancelPendingStashDismissal() {
        panel.cancelPendingStashDismissal()
        isStashDismissalActive = false
    }

    private func prepareInitialFrameIfNeeded() {
        guard let initialFrameProvider else { return }
        self.initialFrameProvider = nil
        guard let frame = initialFrameProvider() else { return }
        setPanelFrame(frame, display: false)
        commitCurrentGeometry()
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
                guard let self else { return }
                activeStashPlacement = placement
                activeStashIntent = PanelStashPolicy.intent(
                    for: placement,
                    topology: currentTopology()
                )
            }
        )
    }

    private func restoreCommittedPanelFrame() {
        guard let committedGeometry else { return }
        let frame = PanelGeometryPolicy.resolvedFrame(
            for: committedGeometry,
            topology: currentTopology(),
            minimumContentSize: WindowRole.pictureInPicture.policy.minimumContentSize,
            frameForContentRect: frameForContentRect
        )
        if frame != panel.frame {
            setPanelFrame(frame, display: false)
        }
    }

    private func commitCurrentGeometry(
        desiredContentSize: CGSize? = nil,
        anchor: PanelFrameAnchor? = nil,
        topology: DisplayTopology? = nil
    ) {
        guard let geometry = PanelGeometryPolicy.capture(
            frame: panel.frame,
            topology: topology ?? currentTopology(),
            desiredContentSize: desiredContentSize,
            anchor: anchor,
            contentRectForFrameRect: contentRectForFrameRect
        ) else {
            return
        }
        committedGeometry = geometry
        do {
            try geometryStore.save(geometry)
        } catch {
            logger.error("Failed to save panel geometry: \(error.localizedDescription, privacy: .public)")
            onGeometryPersistenceFailure?()
        }
    }

    private func recordManualResizeCompletion() {
        guard !panel.isExpanded else {
            logger.debug("Skipped expanded panel resize completion")
            return
        }
        let contentSize = currentPanelContentSize
        commitCurrentGeometry(desiredContentSize: contentSize)
        onManualResizeCompletion?(contentSize)
    }

    func recordPanelMove() {
        guard !isApplyingProgrammaticFrame,
            !isStashDismissalActive,
            let visibleFrame = PanelFramePolicy.targetVisibleFrame(
                for: panel.frame,
                from: currentTopology().visibleFrames
            )
        else {
            return
        }
        let previousVisibleFrame = committedGeometry?.visibleFrame
        let desiredContentSize = committedGeometry?.desiredContentSize.cgSize
            ?? currentPanelContentSize
        let anchor = PanelFramePolicy.nearestAnchor(
            for: panel.frame,
            in: visibleFrame
        )
        scheduleCornerSnap()
        if previousVisibleFrame != visibleFrame {
            let placement = PanelFramePolicy.placement(
                preferredContentSize: desiredContentSize,
                anchoredTo: panel.frame,
                visibleFrames: [visibleFrame],
                minimumContentSize: WindowRole.pictureInPicture.policy.minimumContentSize,
                preserving: anchor,
                frameForContentRect: frameForContentRect
            )
            if placement.frame != panel.frame {
                setPanelFrame(placement.frame, display: panel.isVisible)
            }
        }
        commitCurrentGeometry(desiredContentSize: desiredContentSize)
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
        let visibleFrames = currentTopology().visibleFrames
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
        let cornerAnchor = PanelFrameAnchor(
            horizontalEdge: nearestAnchor.horizontalEdge,
            horizontalInset: PanelFramePolicy.cornerInset,
            verticalEdge: nearestAnchor.verticalEdge,
            verticalInset: PanelFramePolicy.cornerInset
        )
        setPanelFrame(snappedFrame, display: panel.isVisible, animate: true)
        commitCurrentGeometry(
            desiredContentSize: committedGeometry?.desiredContentSize.cgSize,
            anchor: cornerAnchor
        )
    }

    private func currentTopology() -> DisplayTopology {
        let providedTopology = displayTopologyProvider()
        if providedTopology.revision >= latestTopology.revision {
            latestTopology = providedTopology
        }
        return latestTopology
    }

    private static func syntheticTopology(
        visibleFrames: [CGRect],
        revision: UInt64
    ) -> DisplayTopology {
        DisplayTopology(
            revision: revision,
            displays: visibleFrames.enumerated().map { index, visibleFrame in
                DisplayDescriptor(
                    identifier: nil,
                    frame: visibleFrame,
                    visibleFrame: visibleFrame,
                    backingScaleFactor: 1,
                    isPrimary: index == 0
                )
            }
        )
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
    static let stashCloseButtonLabel = "Stash Notion PiP to Side"
    static let stashCloseButtonHelp = "Move the Notion PiP to the nearest screen edge"
    private static let stashAnimationDuration: TimeInterval = 0.16
    private static let stashAnimationTravel: CGFloat = 48
    private var stashAnimationGeneration = 0
    private var pendingStashOriginalFrame: CGRect?

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

    func configureCloseButtonForStash() {
        guard let closeButton = standardWindowButton(.closeButton) else { return }
        closeButton.toolTip = Self.stashCloseButtonLabel
        closeButton.setAccessibilityLabel(Self.stashCloseButtonLabel)
        closeButton.setAccessibilityHelp(Self.stashCloseButtonHelp)
    }

    static func stashAnimationTargetFrame(
        from frame: CGRect,
        toward side: PanelStashSide
    ) -> CGRect {
        let horizontalTravel = switch side {
        case .left:
            -stashAnimationTravel
        case .right:
            stashAnimationTravel
        }
        return frame.offsetBy(dx: horizontalTravel, dy: 0)
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

    func cancelPendingStashDismissal() {
        stashAnimationGeneration &+= 1
        guard let pendingStashOriginalFrame else {
            alphaValue = 1
            return
        }
        self.pendingStashOriginalFrame = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().setFrame(pendingStashOriginalFrame, display: true)
            animator().alphaValue = 1
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
        stashAnimationGeneration &+= 1
        let generation = stashAnimationGeneration
        let originalFrame = frame
        pendingStashOriginalFrame = originalFrame
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            pendingStashOriginalFrame = nil
            orderOut()
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.stashAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(
                Self.stashAnimationTargetFrame(from: originalFrame, toward: side),
                display: true
            )
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard stashAnimationGeneration == generation else {
                    self.alphaValue = 1
                    return
                }
                self.pendingStashOriginalFrame = nil
                self.orderOut(nil)
                self.setFrame(originalFrame, display: false)
                self.alphaValue = 1
                completion()
            }
        }
    }
}
