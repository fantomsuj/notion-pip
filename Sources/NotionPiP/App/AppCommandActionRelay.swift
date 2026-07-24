import AppKit

@MainActor
final class AppCommandActionRelay {
    weak var quickCapturePresenter: (any AppWindowPresenting)?
    weak var setupOptionsPresenter: (any SetupOptionsPresenting)?
    weak var settingsPresenter: (any AppWindowPresenting)?

    func showQuickCapture() {
        quickCapturePresenter?.show()
    }

    func showSetupOptions() {
        setupOptionsPresenter?.show()
    }

    func showSettings() {
        settingsPresenter?.show()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
