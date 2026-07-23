import AppKit

@MainActor
final class AppCommandActionRelay {
    weak var quickCapturePresenter: (any AppWindowPresenting)?
    weak var setupOptionsPresenter: (any SetupOptionsPresenting)?

    func showQuickCapture() {
        quickCapturePresenter?.show()
    }

    func showSetupOptions() {
        setupOptionsPresenter?.show()
    }

    func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
