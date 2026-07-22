import AppKit

@MainActor
protocol AppWindow: AnyObject {
    var isVisible: Bool { get }
    func presentAsKey()
    func orderOut()
}

@MainActor
protocol AppWindowPresenting: AnyObject {
    func show()
    func hide()
}

@MainActor
final class AppWindowPresenter: AppWindowPresenting {
    private let window: any AppWindow

    init(window: any AppWindow) {
        self.window = window
    }

    func show() {
        window.presentAsKey()
    }

    func hide() {
        window.orderOut()
    }
}

final class KeyCapableAppWindow: NSWindow, AppWindow {
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
