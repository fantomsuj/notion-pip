import AppKit
import SwiftUI

@MainActor
protocol PageURLInputPresenting: AnyObject {
    func presentAndFocus()
    func hide()
}

@MainActor
protocol PageURLInputWindow: AnyObject {
    func presentAsKey()
    func orderOut()
}

@MainActor
final class PageURLInputPresenter: PageURLInputPresenting {
    private let window: any PageURLInputWindow
    private let requestFieldFocus: () -> Void

    convenience init(state: PageURLInputState, onSubmit: @escaping () -> Void) {
        let panel = KeyCapablePageURLInputPanel(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pin Notion Page"
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = NSHostingView(
            rootView: PageURLInputPanelContent(state: state, onSubmit: onSubmit)
        )

        self.init(window: panel, requestFieldFocus: state.requestFocus)
    }

    init(window: any PageURLInputWindow, requestFieldFocus: @escaping () -> Void) {
        self.window = window
        self.requestFieldFocus = requestFieldFocus
    }

    func presentAndFocus() {
        window.presentAsKey()
        requestFieldFocus()
    }

    func hide() {
        window.orderOut()
    }
}

private final class KeyCapablePageURLInputPanel: NSPanel, PageURLInputWindow {
    override var canBecomeKey: Bool {
        true
    }

    override func close() {
        orderOut(nil)
    }

    func presentAsKey() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }
}
