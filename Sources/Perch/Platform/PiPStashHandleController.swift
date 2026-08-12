import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class PiPStashHandleController: PiPStashHandle {
    private let handlePanel: NSPanel
    private let shelfPanel: NSPanel
    private let visibleFramesProvider: @MainActor () -> [CGRect]
    private let recentPagesController: PiPRecentPagesShelfController?
    private let onSelectRecentPage: @MainActor (PiPRecentPageSelection) -> Void
    private let shelfDismissDelay: Duration
    private let activateApplication: @MainActor () -> Void
    private let animatesHandleEntrance: Bool

    private var currentPlacement: PanelStashPlacement?
    private var onRestore: (@MainActor () -> Void)?
    private var onPlacementChange: (@MainActor (PanelStashPlacement) -> Void)?
    private var onPullRevealChange: (@MainActor (CGFloat) -> Void)?
    private var onPullRevealEnd: (@MainActor (CGFloat) -> Bool)?
    private var shelfLoadTask: Task<Void, Never>?
    private var shelfDismissTask: Task<Void, Never>?
    private var handleTransitionTask: Task<Void, Never>?
    private var shelfRequestGeneration = 0
    private var handleTransitionGeneration = 0
    private var pendingShelfRequestsFocus = false
    private var isHandleHovered = false
    private var isShelfHovered = false

    var isVisible: Bool {
        handlePanel.isVisible
    }

    var isShelfVisible: Bool {
        shelfPanel.isVisible
    }

    init(
        visibleFramesProvider: @escaping @MainActor () -> [CGRect] = {
            NSScreen.screens.map(\.visibleFrame)
        },
        recentPagesController: PiPRecentPagesShelfController? = nil,
        onSelectRecentPage: @escaping @MainActor (PiPRecentPageSelection) -> Void = { _ in },
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
        self.shelfDismissDelay = shelfDismissDelay
        self.activateApplication = activateApplication
        animatesHandleEntrance = handlePanel == nil

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
        handleTransitionTask?.cancel()
        handleTransitionGeneration &+= 1
        let generation = handleTransitionGeneration
        cancelShelfWork()
        shelfPanel.orderOut(nil)
        isHandleHovered = false
        isShelfHovered = false
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
            handlePanel.alphaValue = 1
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
        if isHovering {
            cancelShelfDismissal()
            requestShelf(requestsFocus: false)
        } else {
            scheduleShelfDismissalIfNeeded()
        }
    }

    func showRecentPages() {
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
        dismissShelf()
        onSelectRecentPage(selection)
    }

    func dismissShelf() {
        cancelShelfWork()
        shelfPanel.orderOut(nil)
        isShelfHovered = false
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
    }

    private func installHandleContent(side: PanelStashSide) {
        handlePanel.contentView = NSHostingView(
            rootView: PiPStashHandleView(
                side: side,
                onRestore: { [weak self] in
                    self?.restoreCurrentPage()
                },
                onDragEnded: { [weak self] frame in
                    self?.finishDrag(frame: frame)
                },
                onDragStarted: { [weak self] in
                    self?.dismissShelf()
                },
                onPullRevealChanged: { [weak self] inwardDistance in
                    self?.updatePullReveal(inwardDistance: inwardDistance)
                },
                onPullRevealEnded: { [weak self] inwardDistance in
                    self?.finishPullReveal(inwardDistance: inwardDistance) ?? false
                },
                onHoverChanged: { [weak self] isHovering in
                    self?.handleHoverChanged(isHovering)
                },
                onShowRecentPages: { [weak self] in
                    self?.showRecentPages()
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
        dismissShelf()
        onRestore?()
    }

    private func requestShelf(requestsFocus: Bool) {
        guard handlePanel.isVisible,
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
        shelfPanel.alphaValue = 1
        if requestsFocus {
            activateApplication()
            shelfPanel.becomesKeyOnlyIfNeeded = true
            shelfPanel.makeKeyAndOrderFront(nil)
        } else {
            shelfPanel.orderFrontRegardless()
        }
    }

    private func scheduleShelfDismissalIfNeeded() {
        guard !isHandleHovered, !isShelfHovered else { return }
        cancelShelfDismissal()
        let delay = shelfDismissDelay
        shelfDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !self.isHandleHovered, !self.isShelfHovered else { return }
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
}
