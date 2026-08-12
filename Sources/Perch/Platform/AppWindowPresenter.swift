import AppKit

@MainActor
protocol AppWindow: AnyObject {
    var isVisible: Bool { get }
    func presentAsKey()
    func orderOut()
    func installCloseRequestHandler(_ handler: @escaping @MainActor () -> Void)
}

@MainActor
protocol AppWindowPresenting: AnyObject {
    func show()
    func hide()
}

@MainActor
final class AppWindowPresenter: AppWindowPresenting {
    private let window: any AppWindow

    init(
        window: any AppWindow,
        closeRequestHandler: (@MainActor () -> Void)? = nil
    ) {
        self.window = window
        if let closeRequestHandler {
            window.installCloseRequestHandler { [weak self] in
                guard let self else { return }
                self.hide()
                closeRequestHandler()
            }
        }
    }

    func show() {
        window.presentAsKey()
    }

    func hide() {
        window.orderOut()
    }

}

final class KeyCapableAppWindow: NSWindow, AppWindow {
    var closeRequestHandler: (@MainActor () -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override func close() {
        if let closeRequestHandler {
            closeRequestHandler()
        } else {
            orderOut(nil)
        }
    }

    func presentAsKey() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }

    func installCloseRequestHandler(_ handler: @escaping @MainActor () -> Void) {
        closeRequestHandler = handler
    }
}
