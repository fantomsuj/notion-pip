import AppKit

@MainActor
final class AppCommandActionRelay {
    weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    var reloadSavedPinAction: () -> Void = {}
    var returnToNotionPageAction: () -> Void = {}
    var newNotionPageAction: () -> Void = {}
    var gettingStartedAction: () -> Void = {}

    func openNewNotionPage() {
        newNotionPageAction()
    }

    func showSettings() {
        settingsWindowPresenter?.show()
    }

    func showGettingStarted() {
        gettingStartedAction()
    }

    func reloadSavedPin() {
        reloadSavedPinAction()
    }

    func returnToNotionPage() {
        returnToNotionPageAction()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
