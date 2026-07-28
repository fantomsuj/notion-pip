import AppKit

@MainActor
final class AppCommandActionRelay {
    weak var quickCapturePresenter: (any AppWindowPresenting)?
    weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    var reloadSavedPinAction: () -> Void = {}

    func showQuickCapture() {
        quickCapturePresenter?.show()
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
