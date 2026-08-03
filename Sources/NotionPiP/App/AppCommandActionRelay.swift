import AppKit

@MainActor
final class AppCommandActionRelay {
    weak var quickCapturePresenter: (any AppWindowPresenting)?
    weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    var reloadSavedPinAction: () -> Void = {}
    var quickCapturePrefillAction: (String) -> Void = { _ in }

    func showQuickCapture() {
        quickCapturePresenter?.show()
    }

    func showQuickCapture(prefill: String?) {
        quickCapturePresenter?.show()
        if let prefill, !prefill.isEmpty { quickCapturePrefillAction(prefill) }
    }

    func showSettings() {
        settingsWindowPresenter?.show()
    }

    func reloadSavedPin() {
        reloadSavedPinAction()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
