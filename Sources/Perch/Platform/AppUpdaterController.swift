import Sparkle

/// Owns Sparkle's standard user interface and update lifecycle for Perch.
@MainActor
final class AppUpdaterController {
    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = false) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    func start() {
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
