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
        guard let window = WindowRole.pinPage.makeWindow() as? KeyCapableAppWindow else {
            preconditionFailure("Pin Page role must create KeyCapableAppWindow")
        }
        window.title = "Pin Notion Page"
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

extension KeyCapableAppWindow: PageURLInputWindow {}
