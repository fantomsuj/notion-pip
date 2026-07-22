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
enum PageURLInputWindowFactory {
    static func makeDefault(
        state: PageURLInputState,
        onSubmit: @escaping () -> Void
    ) -> any PageURLInputWindow {
        let window = KeyCapablePageURLInputWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pin Notion Page"
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: PageURLInputWindowContent(state: state, onSubmit: onSubmit)
        )
        return window
    }
}

@MainActor
final class PageURLInputPresenter: PageURLInputPresenting {
    private let window: any PageURLInputWindow
    private let requestFieldFocus: () -> Void

    convenience init(state: PageURLInputState, onSubmit: @escaping () -> Void) {
        self.init(
            window: PageURLInputWindowFactory.makeDefault(state: state, onSubmit: onSubmit),
            requestFieldFocus: state.requestFocus
        )
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

private final class KeyCapablePageURLInputWindow: NSWindow, PageURLInputWindow {
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
