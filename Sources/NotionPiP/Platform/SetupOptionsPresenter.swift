import AppKit
import SwiftUI

@MainActor
protocol SetupOptionsPresenting: AnyObject {
    func show()
    func hide()
    func toggle()
}

@MainActor
protocol SetupOptionsPopover: AnyObject {
    var isShown: Bool { get }
    func show(relativeTo anchor: NSView)
    func close()
}

@MainActor
final class SetupOptionsPopoverPresenter: SetupOptionsPresenting {
    private let popover: any SetupOptionsPopover
    private weak var anchor: NSView?

    init(popover: any SetupOptionsPopover) {
        self.popover = popover
    }

    convenience init(
        runtime: AppRuntime,
        onQuickCapture: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuBarRootView(
                runtime: runtime,
                onQuickCapture: onQuickCapture,
                onQuit: onQuit
            )
        )
        self.init(popover: popover)
    }

    func attach(to anchor: NSView) {
        self.anchor = anchor
    }

    func show() {
        guard let anchor, !popover.isShown else { return }
        popover.show(relativeTo: anchor)
    }

    func hide() {
        guard popover.isShown else { return }
        popover.close()
    }

    func toggle() {
        popover.isShown ? hide() : show()
    }
}

extension NSPopover: SetupOptionsPopover {
    func show(relativeTo anchor: NSView) {
        show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func close() {
        performClose(nil)
    }
}
