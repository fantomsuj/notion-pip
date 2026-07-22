import SwiftUI

@main
struct NotionPiPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime: AppRuntime
    private let composition: AppComposition

    init() {
        let composition = AppComposition()
        self.composition = composition
        _runtime = StateObject(wrappedValue: composition.runtime)
        appDelegate.bind(urlHandler: composition.runtime)
        composition.runtime.start()
    }

    var body: some Scene {
        Settings {
            SettingsView(runtime: runtime)
        }
    }
}

@MainActor
private final class AppComposition {
    let runtime: AppRuntime
    private let quickCapturePresenter: AppWindowPresenter
    private let settingsPresenter: AppWindowPresenter
    private let setupOptionsPresenter: SetupOptionsPopoverPresenter
    private let statusItemController: StatusItemController

    init() {
        let actionRelay = AppCommandActionRelay()
        let webSession = NotionWebSession()
        let commandModel = AppCommandModel(
            newNotionPage: { webSession.createNewPage() },
            isNewNotionPageEnabled: { !webSession.isCreatingNewPage },
            quickCapture: { actionRelay.showQuickCapture() },
            changePinnedPage: { actionRelay.showSetupOptions() },
            settings: { actionRelay.showSettings() },
            quit: { actionRelay.quit() }
        )
        let nativePageDocument = NativePageDocument()
        let panelCoordinator = PiPPanelCoordinator(
            webSession: webSession,
            nativePageDocument: nativePageDocument,
            commandModel: commandModel
        )
        let runtime = AppRuntime(
            panelCoordinator: panelCoordinator,
            nativePageDocument: nativePageDocument
        )
        webSession.onPageResolved = { [weak runtime] page in
            runtime?.activate(page: page, source: .notionWebSession)
        }
        let quickCapturePresenter = AppWindowFactory.makeQuickCapture { [weak runtime] in
            guard let page = runtime?.activePage else { return }
            NSWorkspace.shared.open(page.canonicalURL)
        }
        let settingsPresenter = AppWindowFactory.makeSettings(runtime: runtime)
        let setupOptionsPresenter = SetupOptionsPopoverPresenter(
            runtime: runtime,
            onQuickCapture: { [weak quickCapturePresenter] in
                quickCapturePresenter?.show()
            },
            onSettings: { [weak settingsPresenter] in
                settingsPresenter?.show()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        let statusItemController = StatusItemController(
            runtime: runtime,
            commandModel: commandModel,
            setupOptionsPresenter: setupOptionsPresenter
        )

        actionRelay.quickCapturePresenter = quickCapturePresenter
        actionRelay.setupOptionsPresenter = setupOptionsPresenter
        actionRelay.settingsPresenter = settingsPresenter
        runtime.bind(setupOptionsPresenter: setupOptionsPresenter)

        self.runtime = runtime
        self.quickCapturePresenter = quickCapturePresenter
        self.settingsPresenter = settingsPresenter
        self.setupOptionsPresenter = setupOptionsPresenter
        self.statusItemController = statusItemController
    }
}
