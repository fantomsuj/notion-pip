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
    func presentFromStash(
        placement: PanelStashPlacement,
        completion: @escaping @MainActor () -> Void
    )
    func presentForPullReveal(at frame: CGRect)
    func pulseLocateHalo()
    func orderOut()
    func dismissForStash(
        toward placement: PanelStashPlacement,
        completion: @escaping @MainActor () -> Void
    )
    func cancelPendingStashDismissal()
    func restoreFromExpandedState()
    func setFrame(_ frame: CGRect, display: Bool)
    func setFrame(_ frame: CGRect, display: Bool, animate: Bool)
}

extension PiPPanelWindow {
    func cancelPendingStashDismissal() {}

    func presentForPullReveal(at frame: CGRect) {
        setFrame(frame, display: false)
        present()
    }

    func pulseLocateHalo() {}

    func presentFromStash(
        placement: PanelStashPlacement,
        completion: @escaping @MainActor () -> Void
    ) {
        present()
        completion()
    }

    func setFrame(_ frame: CGRect, display: Bool, animate: Bool) {
        setFrame(frame, display: display)
    }
}

extension PiPPanelWindow {
    func dismissForStash(
        toward placement: PanelStashPlacement,
        completion: @escaping @MainActor () -> Void
    ) {
        orderOut()
        completion()
    }
}

@MainActor
protocol PiPStashHandle: AnyObject {
    var isVisible: Bool { get }
    func configurePullRevealTravel(_ travel: CGFloat)
    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    )
    func present(
        placement: PanelStashPlacement,
        entrance: PiPStashHandleEntrance,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    )
    func dismissForRestore()
    func orderOut()
}

enum PiPStashHandleEntrance: Equatable, Sendable {
    case immediate
    case coordinated
}

extension PiPStashHandle {
    func configurePullRevealTravel(_ travel: CGFloat) {}

    func present(
        placement: PanelStashPlacement,
        entrance: PiPStashHandleEntrance,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        present(
            placement: placement,
            onRestore: onRestore,
            onPlacementChange: onPlacementChange,
            onPullRevealChange: onPullRevealChange,
            onPullRevealEnd: onPullRevealEnd
        )
    }

    func dismissForRestore() {
        orderOut()
    }
}

enum PanelStashTransition {
    static let duration: TimeInterval = 0.24
    static let handleSettleDuration: TimeInterval = 0.10
    static let handleSettleDelay: Duration = .milliseconds(140)
    static let handleSettleOffset: CGFloat = 12

    private static let horizontalCompression: CGFloat = 0.88
    private static let verticalCompression: CGFloat = 0.94
    private static let outwardTravel: CGFloat = 48

    static func panelTargetFrame(
        from frame: CGRect,
        toward placement: PanelStashPlacement
    ) -> CGRect {
        let anchor = CGPoint(x: placement.frame.midX, y: placement.frame.midY)
        let outwardOffset = placement.side == .left ? -outwardTravel : outwardTravel
        return CGRect(
            x: anchor.x + (frame.minX - anchor.x) * horizontalCompression + outwardOffset,
            y: anchor.y + (frame.minY - anchor.y) * verticalCompression,
            width: frame.width * horizontalCompression,
            height: frame.height * verticalCompression
        )
    }

    static func unsettledHandleFrame(for placement: PanelStashPlacement) -> CGRect {
        placement.frame.offsetBy(
            dx: placement.side == .left ? -handleSettleOffset : handleSettleOffset,
            dy: 0
        )
    }

    static func timingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
    }
}

enum PiPPresentationState: Equatable, Sendable {
    case unavailable
    case visible
    case stashed
}

@MainActor
protocol PiPPanelCoordinating: AnyObject {
    var onExternalPresentationAction: (@MainActor () -> Void)? { get set }
    var onPresentationStateChange: (@MainActor () -> Void)? { get set }
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

    var onPresentationStateChange: (@MainActor () -> Void)? {
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
final class PiPPanelCoordinator: PiPPanelCoordinating, PanelSizing, PanelPositioning {
    private static let autosaveName = "PerchPanel"

    private let logger = Logger(subsystem: "com.fantomsuj.Perch", category: "panel")
    private let panel: any PiPPanelWindow
    private let pageLoader: any NotionPageLoading
    private let stashHandle: (any PiPStashHandle)?
    private let performanceSignposter: (any PerformanceSignposting)?
    private let displayTopologyObserver: (any DisplayTopologyObserving)?
    private let displayTopologyProvider: @MainActor () -> DisplayTopology
    private let snapTargetPresenter: (any PanelSnapTargetPresenting)?
    private let isPrimaryMouseButtonPressed: @MainActor () -> Bool
    private let reducesMotion: @MainActor () -> Bool
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
    private var pullRevealState: PullRevealState?

    private struct PullRevealState {
        let side: PanelStashSide
        let hiddenFrame: CGRect
        let visibleFrame: CGRect
        let pageLifecycleWasHidden: Bool
    }

    var onManualResizeCompletion: (@MainActor (CGSize) -> Void)?
    var onPinnedPageAvailabilityChange: (@MainActor () -> Void)?
    var onGeometryPersistenceFailure: (@MainActor () -> Void)?
    var onExternalPresentationAction: (@MainActor () -> Void)?
    var onPresentationStateChange: (@MainActor () -> Void)?
    var onPanelPositionChange: (@MainActor () -> Void)?

    var presentationState: PiPPresentationState {
        guard currentPage != nil else { return .unavailable }
        return panel.isVisible ? .visible : .stashed
    }

    var hasPinnedPage: Bool {
        currentPage != nil
    }

    var canPositionPanel: Bool {
        currentPage != nil
    }

    var selectedCorner: PanelCorner? {
        guard canPositionPanel else { return nil }
        return PanelFramePolicy.corner(
            for: panel.frame,
            visibleFrames: currentTopology().visibleFrames
        )
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
        panelPositionController: PanelPositionController? = nil,
        onPageSwitcherSelection: @escaping (PageSwitcherSelection) -> Void = { _ in },
        stashHandle: (any PiPStashHandle)? = nil,
        performanceSignposter: (any PerformanceSignposting)? = AppPerformanceSignposter.shared
    ) {
        let stashHandle = stashHandle ?? PiPStashHandleController()
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
        panel.title = "Perch"

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
            snapTargetPresenter: PanelSnapTargetOverlayController(),
            visibleFramesProvider: { displayTopologyObserver.currentTopology.visibleFrames },
            initialFrameProvider: initialFrameProvider,
            initialGeometry: initialGeometry,
            geometryStore: geometryStore,
            frameForContentRect: frameForContentRect,
            contentRectForFrameRect: contentRectForFrameRect
        )
        panelSizeController?.bind(to: self)
        panelPositionController?.bind(to: self)
        let contentView = NSHostingView(
            rootView: PiPChromeView(
                webSession: webSession,
                pageSwitcherController: pageSwitcherController,
                commandModel: commandModel,
                panelSizeController: panelSizeController,
                panelPositionController: panelPositionController,
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
        snapTargetPresenter: (any PanelSnapTargetPresenting)? = nil,
        isPrimaryMouseButtonPressed: @escaping @MainActor () -> Bool = {
            NSEvent.pressedMouseButtons & 1 != 0
        },
        reducesMotion: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
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
        self.snapTargetPresenter = snapTargetPresenter
        self.isPrimaryMouseButtonPressed = isPrimaryMouseButtonPressed
        self.reducesMotion = reducesMotion
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
        presentPanel()
        endFirstPresentation(measurement)
        notifyPanelDidShow()
        if !hadPinnedPage {
            onPinnedPageAvailabilityChange?()
        }
        onPanelPositionChange?()
        logger.notice("Panel show requested")
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        let hadPinnedPage = currentPage != nil
        let measurement = beginFirstPresentation()
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        restoreCommittedPanelFrame()
        currentPage = page
        presentPanel()
        endFirstPresentation(measurement)
        notifyPanelDidShow()
        pageLoader.reloadPinnedPage(page)
        if !hadPinnedPage {
            onPinnedPageAvailabilityChange?()
        }
        onPanelPositionChange?()
        logger.notice("Pinned page reload requested")
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        let measurement = beginFirstPresentation()
        cancelPendingStashDismissal()
        prepareInitialFrameIfNeeded()
        restoreCommittedPanelFrame()
        presentPanel()
        endFirstPresentation(measurement)
        notifyPanelDidShow()
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
        presentPanel()
        panel.pulseLocateHalo()
        measurement.signposter.end(
            measurement.requestToken,
            outcome: .success,
            metadata: PerformanceMetadata(webViewRetention: retention)
        )
        endFirstPresentation(firstPresentationMeasurement)
        notifyPanelDidShow()
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
            panel.pulseLocateHalo()
            logger.notice("Expanded panel restored to its floating size")
            return true
        }
        if panel.isVisible {
            return stashOrRestoreCurrentPage()
        }
        let restored = showCurrentPage()
        if restored {
            panel.pulseLocateHalo()
        }
        return restored
    }

    func replace(page: NotionPageReference) {
        show(page: page)
    }

    func replace(page: NotionPageReference, restoration: DurablePageRestoration?) {
        show(page: page, restoration: restoration)
    }

    @discardableResult
    func movePanel(to corner: PanelCorner) -> Bool {
        onExternalPresentationAction?()
        guard currentPage != nil else { return false }

        let topology = currentTopology()
        let desiredContentSize = committedGeometry?.desiredContentSize.cgSize
            ?? currentPanelContentSize
        guard let placement = PanelFramePolicy.cornerPlacement(
            preferredContentSize: desiredContentSize,
            at: corner,
            relativeTo: panel.frame,
            visibleFrames: topology.visibleFrames,
            minimumContentSize: WindowRole.pictureInPicture.policy.minimumContentSize,
            frameForContentRect: frameForContentRect
        ) else {
            return false
        }

        setPanelFrame(placement.frame, display: panel.isVisible, animate: true)
        commitCurrentGeometry(
            desiredContentSize: desiredContentSize,
            anchor: placement.anchor,
            topology: topology
        )
        logger.notice("Panel moved to explicit corner")
        return true
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

        if !wasVisible {
            presentPanel()
            notifyPanelDidShow()
        } else {
            dismissStashHandle()
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
        presentStashHandle(
            stashHandle,
            placement: placement,
            entrance: .coordinated
        )
        isStashDismissalActive = true
        panel.dismissForStash(toward: placement) { [weak self] in
            guard let self else { return }
            isStashDismissalActive = false
            notifyPanelDidHide()
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
        notifyPanelDidHide()
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
        presentPanel()
        endFirstPresentation(measurement)
        notifyPanelDidShow()
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
        onPanelPositionChange?()
    }

    private func notifyPanelDidShow() {
        pageLoader.panelDidShow()
        onPresentationStateChange?()
    }

    private func notifyPanelDidHide() {
        pageLoader.panelDidHide()
        onPresentationStateChange?()
    }

    private func presentPanel() {
        guard let placement = activeStashPlacement,
            stashHandle?.isVisible == true
        else {
            panel.present()
            dismissStashHandle()
            return
        }

        isStashDismissalActive = true
        panel.presentFromStash(placement: placement) { [weak self] in
            self?.isStashDismissalActive = false
        }
        dismissStashHandle(forRestore: true)
    }

    private func dismissStashHandle(forRestore: Bool = false) {
        pullRevealState = nil
        activeStashPlacement = nil
        activeStashIntent = nil
        guard stashHandle?.isVisible == true else { return }
        if forRestore {
            stashHandle?.dismissForRestore()
        } else {
            stashHandle?.orderOut()
        }
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
        placement: PanelStashPlacement,
        entrance: PiPStashHandleEntrance = .immediate
    ) {
        activeStashPlacement = placement
        stashHandle.configurePullRevealTravel(
            PanelPullRevealPolicy.revealTravel(forPanelWidth: panel.frame.width)
        )
        stashHandle.present(
            placement: placement,
            entrance: entrance,
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
            },
            onPullRevealChange: { [weak self] inwardDistance in
                self?.updatePullReveal(inwardDistance: inwardDistance)
            },
            onPullRevealEnd: { [weak self] inwardDistance in
                self?.finishPullReveal(inwardDistance: inwardDistance) ?? false
            }
        )
    }

    private func updatePullReveal(inwardDistance: CGFloat) {
        guard let placement = activeStashPlacement else { return }
        if pullRevealState == nil {
            let pageLifecycleWasHidden = !isStashDismissalActive
            cancelPendingStashDismissal()
            restoreCommittedPanelFrame()
            guard let displayFrame = PanelFramePolicy.targetVisibleFrame(
                for: placement.frame,
                from: currentTopology().visibleFrames
            ) else {
                return
            }
            let visibleFrame = panel.frame
            let hiddenFrame = PanelPullRevealPolicy.hiddenFrame(
                for: visibleFrame,
                beyond: placement.side,
                displayFrame: displayFrame
            )
            pullRevealState = PullRevealState(
                side: placement.side,
                hiddenFrame: hiddenFrame,
                visibleFrame: visibleFrame,
                pageLifecycleWasHidden: pageLifecycleWasHidden
            )
            panel.presentForPullReveal(at: hiddenFrame)
        }
        guard let pullRevealState else { return }
        let rawProgress = PanelPullRevealPolicy.progress(
            forInwardDistance: inwardDistance,
            panelWidth: pullRevealState.visibleFrame.width
        )
        let progress = PanelPullRevealPolicy.interactiveProgress(
            forRawProgress: rawProgress,
            reducesMotion: reducesMotion()
        )
        setPanelFrame(
            PanelPullRevealPolicy.interpolatedFrame(
                from: pullRevealState.hiddenFrame,
                to: pullRevealState.visibleFrame,
                progress: progress
            ),
            display: true
        )
    }

    private func finishPullReveal(inwardDistance: CGFloat) -> Bool {
        guard let pullRevealState,
            let activeStashPlacement
        else {
            return false
        }
        self.pullRevealState = nil
        let progress = PanelPullRevealPolicy.progress(
            forInwardDistance: inwardDistance,
            panelWidth: pullRevealState.visibleFrame.width
        )
        guard PanelPullRevealPolicy.shouldRestore(progress: progress) else {
            isStashDismissalActive = true
            panel.dismissForStash(toward: activeStashPlacement) { [weak self] in
                guard let self else { return }
                isStashDismissalActive = false
                if !pullRevealState.pageLifecycleWasHidden {
                    pageLoader.panelDidHide()
                }
                onPresentationStateChange?()
            }
            return false
        }

        panel.present()
        setPanelFrame(pullRevealState.visibleFrame, display: true, animate: true)
        dismissStashHandle()
        if pullRevealState.pageLifecycleWasHidden {
            pageLoader.panelDidShow()
        }
        onPresentationStateChange?()
        onPanelPositionChange?()
        logger.notice("Panel restored by pulling its edge handle")
        return true
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
        onPanelPositionChange?()
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
        updateSnapTargetVisibility()
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
            guard self?.isPrimaryMouseButtonPressed() == false else {
                self?.scheduleCornerSnap()
                return
            }
            self?.snapPanelToCorner()
        }
    }

    func snapPanelToCorner() {
        snapTargetPresenter?.dismiss()
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

    private func updateSnapTargetVisibility() {
        guard isPrimaryMouseButtonPressed() else {
            snapTargetPresenter?.dismiss()
            return
        }
        guard let target = PanelFramePolicy.cornerSnapTarget(
            for: panel.frame,
            visibleFrames: currentTopology().visibleFrames
        ) else {
            snapTargetPresenter?.dismiss()
            return
        }
        snapTargetPresenter?.present(target)
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
    static let stashCloseButtonLabel = "Stash Perch to Side"
    static let stashCloseButtonHelp = "Move Perch to the nearest screen edge"
    private static let springAnimationDuration: TimeInterval = 0.34
    private var stashAnimationGeneration = 0
    private var pendingStashOriginalFrame: CGRect?
    private var frameAnimationTask: Task<Void, Never>?
    private var locateHaloTask: Task<Void, Never>?
    private var locateHaloPanel: NSPanel?

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
        toward placement: PanelStashPlacement
    ) -> CGRect {
        PanelStashTransition.panelTargetFrame(from: frame, toward: placement)
    }

    static func criticallyDampedSpringProgress(_ elapsedFraction: CGFloat) -> CGFloat {
        let fraction = min(max(elapsedFraction, 0), 1)
        let scaledTime = 7.2 * fraction
        return min(1 - (1 + scaledTime) * exp(-scaledTime), 1)
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func presentFromStash(
        placement: PanelStashPlacement,
        completion: @escaping @MainActor () -> Void
    ) {
        frameAnimationTask?.cancel()
        stashAnimationGeneration &+= 1
        let generation = stashAnimationGeneration
        let restoredFrame = frame
        let transitionFrame = Self.stashAnimationTargetFrame(
            from: restoredFrame,
            toward: placement
        )
        pendingStashOriginalFrame = restoredFrame
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            pendingStashOriginalFrame = nil
            present()
            completion()
            return
        }

        setFrame(transitionFrame, display: false)
        alphaValue = 0
        present()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelStashTransition.duration
            context.timingFunction = PanelStashTransition.timingFunction()
            animator().setFrame(restoredFrame, display: true)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                    stashAnimationGeneration == generation
                else {
                    return
                }
                pendingStashOriginalFrame = nil
                setFrame(restoredFrame, display: false)
                alphaValue = 1
                completion()
            }
        }
    }

    func presentForPullReveal(at frame: CGRect) {
        cancelPendingStashDismissal()
        frameAnimationTask?.cancel()
        setFrame(frame, display: false)
        alphaValue = 1
        orderFrontRegardless()
    }

    func pulseLocateHalo() {
        locateHaloTask?.cancel()
        removeLocateHalo()

        let haloInset: CGFloat = 11
        let haloPanel = NSPanel(
            contentRect: frame.insetBy(dx: -haloInset, dy: -haloInset),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        haloPanel.isOpaque = false
        haloPanel.backgroundColor = .clear
        haloPanel.hasShadow = false
        haloPanel.ignoresMouseEvents = true
        haloPanel.hidesOnDeactivate = false
        haloPanel.isReleasedWhenClosed = false
        haloPanel.collectionBehavior = collectionBehavior
        haloPanel.contentView = NSHostingView(rootView: LocateHaloView())
        haloPanel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        addChildWindow(haloPanel, ordered: .above)
        locateHaloPanel = haloPanel

        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        locateHaloTask = Task { @MainActor [weak self, weak haloPanel] in
            guard let self, let haloPanel else { return }
            if reducesMotion {
                try? await Task.sleep(for: .milliseconds(180))
            } else {
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    haloPanel.animator().alphaValue = 1
                }
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { return }
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.17
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    haloPanel.animator().alphaValue = 0
                }
            }
            guard !Task.isCancelled else { return }
            self.removeLocateHalo()
        }
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
        frameAnimationTask?.cancel()
        guard animate,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            frame != self.frame
        else {
            setFrame(frame, display: display)
            return
        }

        let startFrame = self.frame
        let startTime = CACurrentMediaTime()
        frameAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let elapsedFraction = CGFloat(elapsed / Self.springAnimationDuration)
                guard elapsedFraction < 1 else { break }
                let progress = Self.criticallyDampedSpringProgress(elapsedFraction)
                setFrame(
                    Self.interpolatedFrame(from: startFrame, to: frame, progress: progress),
                    display: display
                )
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            setFrame(frame, display: display)
            frameAnimationTask = nil
        }
    }

    private static func interpolatedFrame(
        from start: CGRect,
        to end: CGRect,
        progress: CGFloat
    ) -> CGRect {
        CGRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    private func removeLocateHalo() {
        guard let locateHaloPanel else { return }
        if childWindows?.contains(where: { $0 === locateHaloPanel }) == true {
            removeChildWindow(locateHaloPanel)
        }
        locateHaloPanel.orderOut(nil)
        self.locateHaloPanel = nil
    }

    func dismissForStash(
        toward placement: PanelStashPlacement,
        completion: @escaping @MainActor () -> Void
    ) {
        frameAnimationTask?.cancel()
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
            context.duration = PanelStashTransition.duration
            context.timingFunction = PanelStashTransition.timingFunction()
            animator().setFrame(
                Self.stashAnimationTargetFrame(from: originalFrame, toward: placement),
                display: true
            )
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard stashAnimationGeneration == generation else {
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

private struct LocateHaloView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            .shadow(color: Color.primary.opacity(0.24), radius: 7)
            .padding(10)
            .accessibilityHidden(true)
    }
}
