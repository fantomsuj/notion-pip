import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class PiPStashHandleController: PiPStashHandle {
    private static let dropTransitionDuration: TimeInterval = 0.12
    private let handlePanel: NSPanel
    private let shelfPanel: NSPanel
    private let visibleFramesProvider: @MainActor () -> [CGRect]
    private let recentPagesController: PiPRecentPagesShelfController?
    private let onSelectRecentPage: @MainActor (PiPRecentPageSelection) -> Void
    private let dropTitleProvider: (any NotionPageDropTitleProviding)?
    private let onDropNotionPage: @MainActor (NotionPageDrop) -> Void
    private let shelfDismissDelay: Duration
    private let activateApplication: @MainActor () -> Void
    private let animatesHandleEntrance: Bool
    private let animatesDropTransition: Bool
    private let dropTargetModel = PiPStashHandleDropTargetModel()
    private let ownsHandlePanel: Bool
    private let ownsShelfPanel: Bool

    private var currentPlacement: PanelStashPlacement?
    private var onRestore: (@MainActor () -> Void)?
    private var onPlacementChange: (@MainActor (PanelStashPlacement) -> Void)?
    private var onPullRevealChange: (@MainActor (CGFloat) -> Void)?
    private var onPullRevealEnd: (@MainActor (CGFloat) -> Bool)?
    private var pullRevealTravel: CGFloat = 150
    private var shelfLoadTask: Task<Void, Never>?
    private var shelfDismissTask: Task<Void, Never>?
    private var dropTitleTask: Task<Void, Never>?
    private var handleTransitionTask: Task<Void, Never>?
    private var shelfRequestGeneration = 0
    private var handleTransitionGeneration = 0
    private var pendingShelfRequestsFocus = false
    private var isHandleHovered = false
    private var isShelfHovered = false
    private var activeDrop: NotionPageDrop?
    private var performableDrop: NotionPageDrop?
    private var didForwardPerformableDrop = false
    private var dropGeneration = 0
    private var presentationGeneration = 0
    private var isShelfFocusOwned = false
    private lazy var shelfPanelDelegate = StashShelfPanelDelegate { [weak self] in
        self?.shelfDidResignKey()
    }

    var isVisible: Bool {
        handlePanel.isVisible
    }

    var isShelfVisible: Bool {
        shelfPanel.isVisible
    }

    var onShelfFocusChange: (@MainActor (Bool) -> Void)?

    func configurePullRevealTravel(_ travel: CGFloat) {
        pullRevealTravel = max(travel, 1)
    }

    init(
        visibleFramesProvider: @escaping @MainActor () -> [CGRect] = {
            NSScreen.screens.map(\.visibleFrame)
        },
        recentPagesController: PiPRecentPagesShelfController? = nil,
        onSelectRecentPage: @escaping @MainActor (PiPRecentPageSelection) -> Void = { _ in },
        dropTitleProvider: (any NotionPageDropTitleProviding)? = nil,
        onDropNotionPage: @escaping @MainActor (NotionPageDrop) -> Void = { _ in },
        handlePanel: NSPanel? = nil,
        shelfPanel: NSPanel? = nil,
        shelfDismissDelay: Duration = .milliseconds(140),
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.visibleFramesProvider = visibleFramesProvider
        self.recentPagesController = recentPagesController
        self.onSelectRecentPage = onSelectRecentPage
        self.dropTitleProvider = dropTitleProvider
        self.onDropNotionPage = onDropNotionPage
        self.shelfDismissDelay = shelfDismissDelay
        self.activateApplication = activateApplication
        ownsHandlePanel = handlePanel == nil
        ownsShelfPanel = shelfPanel == nil
        animatesHandleEntrance = ownsHandlePanel
        animatesDropTransition = ownsHandlePanel

        if let handlePanel {
            self.handlePanel = handlePanel
        } else {
            guard let panel = WindowRole.stashHandle.makeWindow() as? NSPanel else {
                preconditionFailure("Stash Handle role must create NSPanel")
            }
            self.handlePanel = panel
        }
        if let shelfPanel {
            self.shelfPanel = shelfPanel
        } else {
            guard let panel = WindowRole.stashShelf.makeWindow() as? NSPanel else {
                preconditionFailure("Stash Shelf role must create NSPanel")
            }
            self.shelfPanel = panel
        }

        configurePanels()
    }

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool = { _ in false }
    ) {
        present(
            placement: placement,
            entrance: .immediate,
            onRestore: onRestore,
            onPlacementChange: onPlacementChange,
            onPullRevealChange: onPullRevealChange,
            onPullRevealEnd: onPullRevealEnd
        )
    }

    func present(
        placement: PanelStashPlacement,
        entrance: PiPStashHandleEntrance,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        presentationGeneration &+= 1
        resetDropTarget()
        let didOwnShelfFocus = isShelfFocusOwned
        handleTransitionTask?.cancel()
        handleTransitionGeneration &+= 1
        let generation = handleTransitionGeneration
        cancelShelfWork()
        shelfPanel.orderOut(nil)
        isHandleHovered = false
        isShelfHovered = false
        isShelfFocusOwned = false
        if didOwnShelfFocus {
            onShelfFocusChange?(false)
        }
        handlePanel.ignoresMouseEvents = false

        let shouldAnimateEntrance = animatesHandleEntrance
            && !handlePanel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        currentPlacement = placement
        self.onRestore = onRestore
        self.onPlacementChange = onPlacementChange
        self.onPullRevealChange = onPullRevealChange
        self.onPullRevealEnd = onPullRevealEnd
        installHandleContent(side: placement.side)

        guard shouldAnimateEntrance else {
            if ownsHandlePanel {
                handlePanel.alphaValue = 1
            }
            handlePanel.setFrame(placement.frame, display: true)
            handlePanel.orderFrontRegardless()
            return
        }

        let initialFrame = PanelStashTransition.unsettledHandleFrame(for: placement)
        handlePanel.alphaValue = 0
        handlePanel.ignoresMouseEvents = true
        handlePanel.setFrame(initialFrame, display: false)
        handlePanel.orderFrontRegardless()

        handleTransitionTask = Task { @MainActor [weak self] in
            if case .coordinated = entrance {
                try? await Task.sleep(for: PanelStashTransition.handleSettleDelay)
            }
            guard let self,
                !Task.isCancelled,
                handleTransitionGeneration == generation
            else {
                return
            }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelStashTransition.handleSettleDuration
                context.timingFunction = PanelStashTransition.timingFunction()
                handlePanel.animator().setFrame(placement.frame, display: true)
                handlePanel.animator().alphaValue = 1
            }
            guard !Task.isCancelled,
                handleTransitionGeneration == generation
            else {
                return
            }
            handlePanel.ignoresMouseEvents = false
            handleTransitionTask = nil
        }
    }

    func orderOut() {
        presentationGeneration &+= 1
        resetDropTarget()
        let didOwnShelfFocus = isShelfFocusOwned
        handleTransitionGeneration &+= 1
        handleTransitionTask?.cancel()
        handleTransitionTask = nil
        cancelShelfWork()
        shelfPanel.orderOut(nil)
        handlePanel.orderOut(nil)
        handlePanel.alphaValue = 1
        handlePanel.ignoresMouseEvents = false
        currentPlacement = nil
        onRestore = nil
        onPlacementChange = nil
        onPullRevealChange = nil
        onPullRevealEnd = nil
        isHandleHovered = false
        isShelfHovered = false
        isShelfFocusOwned = false
        if didOwnShelfFocus {
            onShelfFocusChange?(false)
        }
    }

    func dismissForRestore() {
        handleTransitionTask?.cancel()
        handleTransitionGeneration &+= 1
        let generation = handleTransitionGeneration
        guard animatesHandleEntrance,
            handlePanel.isVisible,
            let currentPlacement,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            orderOut()
            return
        }

        handlePanel.ignoresMouseEvents = true
        let unsettledFrame = PanelStashTransition.unsettledHandleFrame(for: currentPlacement)
        handleTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelStashTransition.handleSettleDuration
                context.timingFunction = PanelStashTransition.timingFunction()
                handlePanel.animator().setFrame(unsettledFrame, display: true)
                handlePanel.animator().alphaValue = 0
            }
            guard !Task.isCancelled,
                handleTransitionGeneration == generation
            else {
                return
            }
            orderOut()
        }
    }

    func handleHoverChanged(_ isHovering: Bool) {
        isHandleHovered = isHovering
        guard activeDrop == nil else { return }
        if isHovering {
            cancelShelfDismissal()
            requestShelf(requestsFocus: false)
        } else {
            scheduleShelfDismissalIfNeeded()
        }
    }

    func showRecentPages() {
        guard activeDrop == nil else { return }
        cancelShelfDismissal()
        requestShelf(requestsFocus: true)
    }

    func shelfHoverChanged(_ isHovering: Bool) {
        isShelfHovered = isHovering
        if isHovering {
            cancelShelfDismissal()
        } else {
            scheduleShelfDismissalIfNeeded()
        }
    }

    func finishDrag(frame: CGRect) {
        dismissShelf()
        guard let currentPlacement else { return }
        guard let placement = PanelStashPolicy.snappedPlacement(
            for: frame,
            visibleFrames: visibleFramesProvider()
        ) else {
            handlePanel.setFrame(currentPlacement.frame, display: true)
            return
        }

        self.currentPlacement = placement
        handlePanel.setFrame(placement.frame, display: true)
        installHandleContent(side: placement.side)
        onPlacementChange?(placement)
    }

    func updatePullReveal(inwardDistance: CGFloat) {
        dismissShelf()
        onPullRevealChange?(inwardDistance)
        handlePanel.orderFrontRegardless()
    }

    @discardableResult
    func finishPullReveal(inwardDistance: CGFloat) -> Bool {
        dismissShelf()
        let didRestore = onPullRevealEnd?(inwardDistance) ?? false
        guard !didRestore, let currentPlacement else { return didRestore }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            handlePanel.setFrame(currentPlacement.frame, display: true)
            return false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                1,
                0.36,
                1
            )
            handlePanel.animator().setFrame(currentPlacement.frame, display: true)
        }
        return false
    }

    func selectRecentPage(id: String) {
        guard let selection = recentPagesController?.selection(for: id) else { return }
        switch selection {
        case .restoreCurrent:
            restoreCurrentPage()
        case .activate:
            dismissShelf()
            onSelectRecentPage(selection)
        }
    }

    func dismissShelf() {
        dismissShelf(notifyingFocusEnd: true)
    }

    private func dismissShelf(notifyingFocusEnd: Bool) {
        let didOwnShelfFocus = isShelfFocusOwned
        cancelShelfWork()
        isShelfFocusOwned = false
        shelfPanel.orderOut(nil)
        isShelfHovered = false
        if notifyingFocusEnd, didOwnShelfFocus {
            onShelfFocusChange?(false)
        }
    }

    func shelfDidResignKey() {
        guard isShelfFocusOwned, shelfPanel.isVisible else { return }
        dismissShelf()
    }

    private func configurePanels() {
        handlePanel.isMovable = false
        handlePanel.isOpaque = false
        handlePanel.backgroundColor = .clear
        handlePanel.hasShadow = true

        shelfPanel.isMovable = false
        shelfPanel.isOpaque = false
        shelfPanel.backgroundColor = .clear
        shelfPanel.hasShadow = true
        shelfPanel.hidesOnDeactivate = false
        shelfPanel.isReleasedWhenClosed = false
        shelfPanel.delegate = shelfPanelDelegate
    }

    private func installHandleContent(side: PanelStashSide) {
        let generation = presentationGeneration
        handlePanel.contentView = NSHostingView(
            rootView: PiPStashHandleView(
                side: side,
                dropTargetModel: dropTargetModel,
                pullRevealTravel: pullRevealTravel,
                onRestore: { [weak self] in
                    guard self?.presentationGeneration == generation else { return }
                    self?.restoreCurrentPage()
                },
                onDragEnded: { [weak self] frame in
                    guard self?.presentationGeneration == generation else { return }
                    self?.finishDrag(frame: frame)
                },
                onDragStarted: { [weak self] in
                    guard self?.presentationGeneration == generation else { return }
                    self?.dismissShelf()
                },
                onPullRevealChanged: { [weak self] inwardDistance in
                    guard self?.presentationGeneration == generation else { return }
                    self?.updatePullReveal(inwardDistance: inwardDistance)
                },
                onPullRevealEnded: { [weak self] inwardDistance in
                    guard self?.presentationGeneration == generation else { return false }
                    return self?.finishPullReveal(inwardDistance: inwardDistance) ?? false
                },
                onHoverChanged: { [weak self] isHovering in
                    guard self?.presentationGeneration == generation else { return }
                    self?.handleHoverChanged(isHovering)
                },
                onShowRecentPages: { [weak self] in
                    guard self?.presentationGeneration == generation else { return }
                    self?.showRecentPages()
                },
                onDropCandidateChanged: { [weak self] drop in
                    guard self?.presentationGeneration == generation else { return }
                    self?.handleDropCandidateChanged(drop)
                },
                onDropPerformed: { [weak self] drop in
                    guard self?.presentationGeneration == generation else { return }
                    self?.performDrop(drop)
                }
            )
        )
    }

    private func installShelfContent() {
        guard let recentPagesController else { return }
        shelfPanel.contentView = NSHostingView(
            rootView: PiPRecentPagesShelfView(
                controller: recentPagesController,
                onSelect: { [weak self] pageID in
                    self?.selectRecentPage(id: pageID)
                },
                onHoverChanged: { [weak self] isHovering in
                    self?.shelfHoverChanged(isHovering)
                },
                onDismiss: { [weak self] in
                    self?.dismissShelf()
                }
            )
        )
    }

    private func restoreCurrentPage() {
        let didOwnShelfFocus = isShelfFocusOwned
        dismissShelf(notifyingFocusEnd: false)
        onRestore?()
        if didOwnShelfFocus {
            onShelfFocusChange?(false)
        }
    }

    private func requestShelf(requestsFocus: Bool) {
        guard handlePanel.isVisible,
              activeDrop == nil,
              let recentPagesController
        else {
            return
        }

        pendingShelfRequestsFocus = pendingShelfRequestsFocus || requestsFocus
        shelfLoadTask?.cancel()
        shelfRequestGeneration &+= 1
        let generation = shelfRequestGeneration
        shelfLoadTask = Task { @MainActor [weak self, recentPagesController] in
            await recentPagesController.load()
            guard let self,
                  !Task.isCancelled,
                  generation == self.shelfRequestGeneration,
                  self.handlePanel.isVisible
            else {
                return
            }
            guard recentPagesController.isAvailable,
                  recentPagesController.items.count > 1
            else {
                self.dismissShelf()
                return
            }
            let requestsFocus = self.pendingShelfRequestsFocus
            self.pendingShelfRequestsFocus = false
            self.presentShelf(requestsFocus: requestsFocus)
            if generation == self.shelfRequestGeneration {
                self.shelfLoadTask = nil
            }
        }
    }

    private func presentShelf(requestsFocus: Bool) {
        guard let placement = currentPlacement,
              let recentPagesController,
              let frame = PanelStashShelfPolicy.frame(
                attachedTo: placement,
                itemCount: recentPagesController.items.count,
                visibleFrames: visibleFramesProvider()
              )
        else {
            dismissShelf()
            return
        }

        installShelfContent()
        shelfPanel.setFrame(frame, display: true)
        if ownsShelfPanel {
            shelfPanel.alphaValue = 1
        }
        let shouldActivateApplication = requestsFocus && !isShelfFocusOwned
        isShelfFocusOwned = isShelfFocusOwned || requestsFocus
        if isShelfFocusOwned {
            if shouldActivateApplication {
                onShelfFocusChange?(true)
                activateApplication()
            }
            shelfPanel.becomesKeyOnlyIfNeeded = true
            shelfPanel.makeKeyAndOrderFront(nil)
        } else {
            shelfPanel.orderFrontRegardless()
        }
    }

    private func scheduleShelfDismissalIfNeeded() {
        guard !isHandleHovered,
              !isShelfHovered,
              !pendingShelfRequestsFocus,
              !isShelfFocusOwned
        else {
            return
        }
        cancelShelfDismissal()
        let delay = shelfDismissDelay
        shelfDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self,
                  !self.isHandleHovered,
                  !self.isShelfHovered,
                  !self.pendingShelfRequestsFocus,
                  !self.isShelfFocusOwned
            else {
                return
            }
            self.dismissShelf()
        }
    }

    private func cancelShelfDismissal() {
        shelfDismissTask?.cancel()
        shelfDismissTask = nil
    }

    private func cancelShelfWork() {
        shelfRequestGeneration &+= 1
        pendingShelfRequestsFocus = false
        shelfLoadTask?.cancel()
        shelfLoadTask = nil
        cancelShelfDismissal()
    }

    private func handleDropCandidateChanged(_ drop: NotionPageDrop?) {
        guard let drop else {
            clearDropPreview()
            return
        }

        dismissShelf()
        isHandleHovered = false
        activeDrop = drop
        performableDrop = drop
        didForwardPerformableDrop = false
        dropGeneration &+= 1
        let generation = dropGeneration
        dropTargetModel.show(label: drop.displayLabel(localTitle: nil))
        if let placement = currentPlacement,
           let expandedFrame = StashHandleDropTargetPolicy.expandedFrame(
               for: placement,
               visibleFrames: visibleFramesProvider()
           ) {
            updateHandleFrame(expandedFrame)
        }

        dropTitleTask?.cancel()
        guard let dropTitleProvider else { return }
        dropTitleTask = Task { @MainActor [weak self, dropTitleProvider] in
            let localTitle = await dropTitleProvider.displayTitle(for: drop.page.pageID)
            guard let self,
                  !Task.isCancelled,
                  generation == self.dropGeneration,
                  self.activeDrop?.page.pageID == drop.page.pageID,
                  self.activeDrop == drop,
                  self.performableDrop == drop
            else {
                return
            }
            self.dropTargetModel.show(label: drop.displayLabel(localTitle: localTitle))
            self.dropTitleTask = nil
        }
    }

    private func performDrop(_ drop: NotionPageDrop) {
        guard performableDrop == drop, !didForwardPerformableDrop else { return }
        clearDropPreview()
        didForwardPerformableDrop = true
        onDropNotionPage(drop)
    }

    private func clearDropPreview() {
        dropGeneration &+= 1
        dropTitleTask?.cancel()
        dropTitleTask = nil
        activeDrop = nil
        dropTargetModel.clear()
        if let currentPlacement {
            updateHandleFrame(currentPlacement.frame)
        }
    }

    private func resetDropTarget() {
        clearDropPreview()
        performableDrop = nil
        didForwardPerformableDrop = false
    }

    private func updateHandleFrame(_ frame: CGRect) {
        guard animatesDropTransition,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else {
            handlePanel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.dropTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            handlePanel.animator().setFrame(frame, display: true)
        }
    }
}

@MainActor
private final class StashShelfPanelDelegate: NSObject, NSWindowDelegate {
    private let onResignKey: @MainActor () -> Void

    init(onResignKey: @escaping @MainActor () -> Void) {
        self.onResignKey = onResignKey
    }

    func windowDidResignKey(_ notification: Notification) {
        onResignKey()
    }
}
