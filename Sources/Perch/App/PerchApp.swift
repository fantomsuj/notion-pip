import AppKit
import OSLog

@main
enum PerchApp {
    static func main() {
        do {
            try ApplicationLaunch.run(
                claimInstance: {
                    try ApplicationInstanceCoordinator().claim()
                },
                prepareApplication: {
                    let coldLaunchToken = AppPerformanceSignposter.shared.begin(
                        .coldLaunchToReady
                    )
                    return (AppComposition(), coldLaunchToken)
                },
                runApplication: { preparedApplication, _ in
                    let (composition, coldLaunchToken) = preparedApplication
                    let appDelegate = AppDelegate()
                    let application = NSApplication.shared
                    application.delegate = appDelegate
                    application.mainMenu = AppMainMenuFactory.make()
                    AppStartup.start(
                        runtime: composition.runtime,
                        appDelegate: appDelegate,
                        coldLaunchToken: coldLaunchToken,
                        applicationDidFinishLaunching: {
                            composition.onboardingCoordinator.showIfNeeded()
                        },
                        quickCopyTerminationAction: {
                            composition.quickCopyController.prepareForTermination()
                        }
                    )
                    application.run()
                }
            )
        } catch {
            Logger(subsystem: "com.fantomsuj.Perch", category: "lifecycle")
                .fault("Unable to claim the application instance lock")
        }
    }
}

@MainActor
enum AppStartup {
    static func start(
        runtime: AppRuntime,
        appDelegate: AppDelegate,
        coldLaunchToken: PerformanceIntervalToken? = nil,
        performanceSignposter: any PerformanceSignposting = AppPerformanceSignposter.shared,
        applicationDidFinishLaunching: @escaping @MainActor () -> Void = {},
        quickCopyTerminationAction: @escaping @MainActor () -> Void = {}
    ) {
        runtime.start()
        appDelegate.bind(
            coldLaunchToken: coldLaunchToken,
            performanceSignposter: performanceSignposter
        )
        appDelegate.bind(applicationDidFinishLaunching: applicationDidFinishLaunching)
        appDelegate.bind {
            quickCopyTerminationAction()
            await runtime.prepareForTermination()
            return true
        }
        appDelegate.bind(urlHandler: runtime)
    }
}

@MainActor
private final class AppComposition {
    let runtime: AppRuntime
    let onboardingCoordinator: OnboardingCoordinator
    let quickCopyController: QuickCopyController

    private let settingsWindowPresenter: SettingsWindowPresenter
    private let statusItemController: StatusItemController
    private let panelSizeController: PanelSizeController
    private let panelPositionController: PanelPositionController
    private let launchAtLoginService: LaunchAtLoginService

    init() {
        let actionRelay = AppCommandActionRelay()
        let onboardingPreferenceStore = OnboardingPreferenceStore()
        let webSession = NotionWebSession()
        let pageRepository: PageRepository?
        let initialServiceHealth: ServiceHealthState

        do {
            try LegacyPersonalTokenRemover().remove()
        } catch let LegacyPersonalTokenRemovalError.unexpectedStatus(status) {
            Logger(subsystem: "com.fantomsuj.Perch", category: "cleanup")
                .error("Legacy personal-token cleanup failed status=\(status, privacy: .public)")
        } catch {
            Logger(subsystem: "com.fantomsuj.Perch", category: "cleanup")
                .error("Legacy personal-token cleanup failed")
        }

        do {
            let container = try PerchPersistence.makeContainer()
            pageRepository = PageRepository(container: container)
            initialServiceHealth = .healthy
        } catch {
            Logger(subsystem: "com.fantomsuj.Perch", category: "persistence")
                .error("Persistent store unavailable")
            pageRepository = nil
            initialServiceHealth = ServiceHealthState(issues: [.persistentStoreUnavailable])
        }

        let pageLauncher = NotionDesktopPageLauncher()
        let panelSizeController = PanelSizeController()
        let panelPositionController = PanelPositionController()
        let launchAtLoginService = LaunchAtLoginService()
        let commandModel = AppCommandModel(
            newNotionPage: { actionRelay.openNewNotionPage() },
            settings: { actionRelay.showSettings() },
            gettingStarted: { actionRelay.showGettingStarted() },
            quit: { actionRelay.quit() }
        )
        let pageSwitcherController = PageSwitcherController(store: pageRepository)
        let pageSwitcherRelay = PageSwitcherSelectionRelay()
        let recentPagesController = PiPRecentPagesShelfController(store: pageRepository)
        let recentPageSelectionRelay = PiPRecentPageSelectionRelay()
        let notionPageDropComposition = NotionPageDropComposition(
            recentPagesController: recentPagesController,
            onSelectRecentPage: recentPageSelectionRelay.perform,
            dropTitleProvider: pageRepository
        )
        let stashHandle = notionPageDropComposition.stashHandle
        let quickCopyController = QuickCopyController(
            monitor: AccessibilitySelectionMonitor(),
            target: webSession
        )
        let panelCoordinator = PiPPanelCoordinator(
            webSession: webSession,
            pageSwitcherController: pageSwitcherController,
            commandModel: commandModel,
            quickCopyController: quickCopyController,
            onReloadSavedPin: { actionRelay.reloadSavedPin() },
            panelSizeController: panelSizeController,
            panelPositionController: panelPositionController,
            onPageSwitcherSelection: pageSwitcherRelay.perform,
            stashHandle: stashHandle
        )
        let runtime = AppRuntime(
            panelCoordinator: panelCoordinator,
            pageRepository: pageRepository,
            initialServiceHealth: initialServiceHealth,
            automaticSettingsPresentationAllowed: {
                !onboardingPreferenceStore.shouldPresent(
                    version: OnboardingCoordinator.currentVersion
                )
            }
        )

        actionRelay.reloadSavedPinAction = { [weak runtime] in
            runtime?.reloadSavedPin()
        }
        actionRelay.newNotionPageAction = {
            _ = pageLauncher.openNewPage()
        }
        webSession.onPageResolved = { [weak runtime] page in
            runtime?.activate(page: page, source: .notionWebSession)
        }
        webSession.onRestorationCaptured = { restoration in
            guard let pageRepository else { return }
            Task {
                _ = try? await pageRepository.saveRestoration(restoration)
            }
        }
        pageSwitcherController.onWorkingSetChanged = { [weak webSession] snapshot in
            let pageIDs = Set(
                (snapshot.pinnedPages + snapshot.recentPages).map(\.pageID)
            )
            webSession?.evictInteractionSnapshots(retaining: pageIDs)
        }
        pageSwitcherRelay.handler = { [weak runtime] selection in
            guard case let .activate(page, restoration) = selection else { return }
            runtime?.activate(
                page: page,
                source: .pageSwitcher,
                restoration: restoration
            )
        }
        recentPageSelectionRelay.handler = { [weak runtime] selection in
            runtime?.activate(
                page: selection.page,
                source: .pageSwitcher,
                restoration: selection.restoration
            )
        }
        notionPageDropComposition.bind(to: runtime)

        let settingsWindowPresenter = SettingsWindowPresenter { closeHandler in
            AppWindowFactory.makeSettings(
                runtime: runtime,
                panelSizeController: panelSizeController,
                launchAtLoginService: launchAtLoginService,
                closeRequestHandler: closeHandler
            )
        }
        let onboardingCoordinator = OnboardingCoordinator(
            preferenceStore: onboardingPreferenceStore,
            settingsWindowPresenter: settingsWindowPresenter,
            firstPageHandoff: { [weak runtime] in
                runtime?.presentPageURLInputAfterRestoreIfNeeded()
            },
            makeWindowPresenter: { completion, openSettings in
                AppWindowFactory.makeOnboarding(
                    globalShortcut: runtime.globalShortcut,
                    pageURLInputState: runtime.pageURLInputState,
                    onPinPage: runtime.validatePageURL,
                    onComplete: completion,
                    onOpenSettings: openSettings
                )
            }
        )
        let statusItemController = StatusItemController(
            runtime: runtime,
            commandModel: commandModel,
            panelSizeController: panelSizeController
        )

        actionRelay.settingsWindowPresenter = settingsWindowPresenter
        actionRelay.gettingStartedAction = { [weak onboardingCoordinator] in
            onboardingCoordinator?.show()
        }
        runtime.bind(settingsWindowPresenter: settingsWindowPresenter)
        panelSizeController.onManagePanelSizes = {
            actionRelay.showSettings()
        }

        self.runtime = runtime
        self.onboardingCoordinator = onboardingCoordinator
        self.quickCopyController = quickCopyController
        self.settingsWindowPresenter = settingsWindowPresenter
        self.statusItemController = statusItemController
        self.panelSizeController = panelSizeController
        self.panelPositionController = panelPositionController
        self.launchAtLoginService = launchAtLoginService
    }
}

@MainActor
private final class PageSwitcherSelectionRelay {
    var handler: (PageSwitcherSelection) -> Void = { _ in }

    func perform(_ selection: PageSwitcherSelection) {
        handler(selection)
    }
}

@MainActor
private final class PiPRecentPageSelectionRelay {
    var handler: (PiPRecentPageSelection) -> Void = { _ in }

    func perform(_ selection: PiPRecentPageSelection) {
        handler(selection)
    }
}

@MainActor
final class NotionPageDropRelay {
    var handler: (NotionPageDrop) -> Void = { _ in }

    func perform(_ drop: NotionPageDrop) {
        handler(drop)
    }
}

@MainActor
final class NotionPageDropComposition {
    let stashHandle: PiPStashHandleController

    private let relay = NotionPageDropRelay()

    init(
        recentPagesController: PiPRecentPagesShelfController? = nil,
        onSelectRecentPage: @escaping @MainActor (PiPRecentPageSelection) -> Void = { _ in },
        dropTitleProvider: (any NotionPageDropTitleProviding)? = nil,
        makeStashHandle: (
            (
                (any NotionPageDropTitleProviding)?,
                @escaping @MainActor (NotionPageDrop) -> Void
            ) -> PiPStashHandleController
        )? = nil
    ) {
        if let makeStashHandle {
            stashHandle = makeStashHandle(dropTitleProvider, relay.perform)
        } else {
            stashHandle = PiPStashHandleController(
                recentPagesController: recentPagesController,
                onSelectRecentPage: onSelectRecentPage,
                dropTitleProvider: dropTitleProvider,
                onDropNotionPage: relay.perform
            )
        }
    }

    func bind(to runtime: AppRuntime) {
        relay.handler = { [weak runtime] drop in
            runtime?.activate(page: drop.page, source: .edgeHandleDrop)
        }
    }
}
