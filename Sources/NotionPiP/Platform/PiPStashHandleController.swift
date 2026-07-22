import AppKit
import SwiftUI

@MainActor
final class PiPStashHandleController: PiPStashHandle {
    private let panel: NSPanel

    var isVisible: Bool {
        panel.isVisible
    }

    init() {
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
        onRestore: @escaping @MainActor () -> Void
    ) {
        panel.contentView = NSHostingView(
            rootView: PiPStashHandleView(
                side: placement.side,
                onRestore: onRestore
            )
        )
        panel.setFrame(placement.frame, display: true)
        panel.orderFrontRegardless()
    }

    func orderOut() {
        panel.orderOut(nil)
    }
}
