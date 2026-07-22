import AppKit
import SwiftUI

@MainActor
final class PiPStashHandleController: PiPStashHandle {
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
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
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
        currentPlacement = placement
        self.onRestore = onRestore
        self.onPlacementChange = onPlacementChange
        installContent(side: placement.side)
        panel.setFrame(placement.frame, display: true)
        panel.orderFrontRegardless()
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
