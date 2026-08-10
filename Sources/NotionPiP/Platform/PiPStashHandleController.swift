import AppKit
import SwiftUI

@MainActor
final class PiPStashHandleController: PiPStashHandle {
    private static let entranceOffset: CGFloat = 12
    private static let entranceAnimationDuration: TimeInterval = 0.10

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
    private var shelfLoadTask: Task<Void, Never>?
    private var shelfDismissTask: Task<Void, Never>?
    private var shelfRequestGeneration = 0
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
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void
    ) {
        cancelShelfWork()
        shelfPanel.orderOut(nil)
        isHandleHovered = false
        isShelfHovered = false

        let shouldAnimateEntrance = animatesHandleEntrance
            && !handlePanel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        currentPlacement = placement
        self.onRestore = onRestore
        self.onPlacementChange = onPlacementChange
        installHandleContent(side: placement.side)

        guard shouldAnimateEntrance else {
            handlePanel.alphaValue = 1
            handlePanel.setFrame(placement.frame, display: true)
            handlePanel.orderFrontRegardless()
            return
        }

        let initialFrame = placement.frame.offsetBy(
            dx: placement.side == .left ? -Self.entranceOffset : Self.entranceOffset,
            dy: 0
        )
        handlePanel.alphaValue = 0
        handlePanel.setFrame(initialFrame, display: false)
        handlePanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.entranceAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            handlePanel.animator().setFrame(placement.frame, display: true)
            handlePanel.animator().alphaValue = 1
        }
    }

    func orderOut() {
        cancelShelfWork()
        shelfPanel.orderOut(nil)
        handlePanel.orderOut(nil)
        currentPlacement = nil
        onRestore = nil
        onPlacementChange = nil
        isHandleHovered = false
        isShelfHovered = false
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
        shelfLoadTask?.cancel()
        shelfLoadTask = nil
        cancelShelfDismissal()
    }
}
