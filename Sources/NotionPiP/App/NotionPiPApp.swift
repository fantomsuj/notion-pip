import OSLog
import SwiftUI

@main
struct NotionPiPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime: AppRuntime
    private let composition: AppComposition

    init() {
        let coldLaunchToken = AppPerformanceSignposter.shared.begin(.coldLaunchToStatusItem)
        let composition = AppComposition()
        self.composition = composition
        _runtime = StateObject(wrappedValue: composition.runtime)
        AppStartup.start(
            runtime: composition.runtime,
            appDelegate: appDelegate,
            coldLaunchToken: coldLaunchToken
        )
    }

    var body: some Scene {
        Settings {
            SettingsView(runtime: runtime)
        }
    }
}

@MainActor
enum AppStartup {
    static func start(
        runtime: AppRuntime,
        appDelegate: AppDelegate,
        coldLaunchToken: PerformanceIntervalToken? = nil,
        performanceSignposter: any PerformanceSignposting = AppPerformanceSignposter.shared
    ) {
        runtime.start()
        appDelegate.bind(
            coldLaunchToken: coldLaunchToken,
            performanceSignposter: performanceSignposter
        )
        appDelegate.bind {
            await runtime.prepareForTermination()
        }
        appDelegate.bind(urlHandler: runtime)
    }
}

@MainActor
private final class AppComposition {
    let runtime: AppRuntime
    private let quickCapturePresenter: any AppWindowPresenting
    private let settingsPresenter: AppWindowPresenter
    private let setupOptionsPresenter: SetupOptionsPopoverPresenter
    private let statusItemController: StatusItemController

    init() {
        let actionRelay = AppCommandActionRelay()
        let webSession = NotionWebSession()
        let pageRepository: PageRepository?
        let captureRepository: CaptureRepository?

        do {
            let container = try NotionPiPPersistence.makeContainer()
            pageRepository = PageRepository(container: container)
            captureRepository = CaptureRepository(container: container)
        } catch {
            Logger(subsystem: "com.fantomsuj.NotionPiP", category: "persistence")
                .error("Persistent store unavailable")
            pageRepository = nil
            captureRepository = nil
        }

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
            nativePageDocument: nativePageDocument,
            pageRepository: pageRepository
        )
        webSession.onPageResolved = { [weak runtime] page in
            runtime?.activate(page: page, source: .notionWebSession)
        }
        let quickCapturePresenter: any AppWindowPresenting = LazyAppWindowPresenter(
            makePresenter: {
                AppWindowFactory.makeQuickCapture(
                    repository: captureRepository
                ) { [weak runtime] in
                    guard let page = runtime?.activePage else { return }
                    NSWorkspace.shared.open(page.canonicalURL)
                }
            },
            performanceSignposter: AppPerformanceSignposter.shared,
            firstPresentationOperation: .firstQuickCapturePresentation
        )
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
