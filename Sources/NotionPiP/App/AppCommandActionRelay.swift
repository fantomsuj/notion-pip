import AppKit

@MainActor
final class AppCommandActionRelay {
    weak var quickCapturePresenter: (any AppWindowPresenting)?
    weak var settingsWindowPresenter: (any SettingsWindowPresenting)?

    func showQuickCapture() {
        quickCapturePresenter?.show()
    }

    func showSettings() {
        settingsWindowPresenter?.show()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
