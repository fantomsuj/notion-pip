import AppKit
import SwiftUI

@MainActor
final class PiPStashHandleController: PiPStashHandle {
    private static let entranceOffset: CGFloat = 12
    private static let entranceAnimationDuration: TimeInterval = 0.10

    private let panel: NSPanel
    private let visibleFramesProvider: @MainActor () -> [CGRect]
    private var currentPlacement: PanelStashPlacement?
    private var onRestore: (@MainActor () -> Void)?
    private var onPlacementChange: (@MainActor (PanelStashPlacement) -> Void)?

    var isVisible: Bool {
        panel.isVisible
    }

    init(
        visibleFramesProvider: @escaping @MainActor () -> [CGRect] = {
            NSScreen.screens.map(\.visibleFrame)
        }
    ) {
        self.visibleFramesProvider = visibleFramesProvider
        guard let panel = WindowRole.stashHandle.makeWindow() as? NSPanel else {
            preconditionFailure("Stash Handle role must create NSPanel")
        }
        self.panel = panel
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
    }

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void
    ) {
        let shouldAnimateEntrance = !panel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        currentPlacement = placement
        self.onRestore = onRestore
        self.onPlacementChange = onPlacementChange
        installContent(side: placement.side)

        guard shouldAnimateEntrance else {
            panel.alphaValue = 1
            panel.setFrame(placement.frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        let initialFrame = placement.frame.offsetBy(
            dx: placement.side == .left ? -Self.entranceOffset : Self.entranceOffset,
            dy: 0
        )
        panel.alphaValue = 0
        panel.setFrame(initialFrame, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.entranceAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(placement.frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func orderOut() {
        panel.orderOut(nil)
        currentPlacement = nil
        onRestore = nil
        onPlacementChange = nil
    }

    private func installContent(side: PanelStashSide) {
        panel.contentView = NSHostingView(
            rootView: PiPStashHandleView(
                side: side,
                onRestore: { [weak self] in
                    self?.onRestore?()
                },
                onDragEnded: { [weak self] frame in
                    self?.finishDrag(frame: frame)
                }
            )
        )
    }

    private func finishDrag(frame: CGRect) {
        guard let currentPlacement else { return }
        guard let placement = PanelStashPolicy.snappedPlacement(
            for: frame,
            visibleFrames: visibleFramesProvider()
        ) else {
            panel.setFrame(currentPlacement.frame, display: true)
            return
        }

        self.currentPlacement = placement
        panel.setFrame(placement.frame, display: true)
        installContent(side: placement.side)
        onPlacementChange?(placement)
    }
}
