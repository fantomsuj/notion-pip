import AppKit
import Combine
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
                            composition.applicationDidFinishLaunching()
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
        applicationDidFinishLaunching: @escaping @MainActor () -> Void = {}
    ) {
        runtime.start()
        appDelegate.bind(
            coldLaunchToken: coldLaunchToken,
            performanceSignposter: performanceSignposter
        )
        appDelegate.bind(applicationDidFinishLaunching: applicationDidFinishLaunching)
        appDelegate.bind {
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
    let startupRecoveryCoordinator: StartupRecoveryCoordinator

    private let settingsWindowPresenter: SettingsWindowPresenter
    private let recoveryGuardedSettingsWindowPresenter:
        RecoveryGuardedSettingsWindowPresenter
    private let storageRecoveryController: StorageRecoveryController?
    private let storageRecoveryPresenter: (any AppWindowPresenting)?
    private let statusItemController: StatusItemController
    private let updaterController: AppUpdaterController
    private let panelSizeController: PanelSizeController
    private let panelPositionController: PanelPositionController
    private let launchAtLoginService: LaunchAtLoginService
    private let contextSuggestionController: ContextSuggestionController
    private let contextSuggestionPanelController: ContextSuggestionPanelController
    private var statusItemAppearanceCancellable: AnyCancellable?
    private var contextSuggestionActivePageCancellable: AnyCancellable?

    func applicationDidFinishLaunching() {
        updaterController.start()
        startupRecoveryCoordinator.applicationDidFinishLaunching()
    }

    init() {
        let actionRelay = AppCommandActionRelay()
        let onboardingPreferenceStore = OnboardingPreferenceStore()
        let webSession = NotionWebSession()

        do {
            try LegacyPersonalTokenRemover().remove()
        } catch let LegacyPersonalTokenRemovalError.unexpectedStatus(status) {
            Logger(subsystem: "com.fantomsuj.Perch", category: "cleanup")
                .error("Legacy personal-token cleanup failed status=\(status, privacy: .public)")
        } catch {
            Logger(subsystem: "com.fantomsuj.Perch", category: "cleanup")
                .error("Legacy personal-token cleanup failed")
        }

        let persistenceResult = PersistenceBootstrapper.live().bootstrap()
        let pageRepository = persistenceResult.pageRepository
        let recoveryContext = persistenceResult.recoveryContext
        if recoveryContext != nil {
            Logger(subsystem: "com.fantomsuj.Perch", category: "persistence")
                .error("Persistent store unavailable")
        }
        let startupPresentationGate = StartupPresentationGate(
            recoveryRequired: recoveryContext != nil
        )

        let pageLauncher = NotionDesktopPageLauncher()
        let panelSizeController = PanelSizeController()
        let panelPositionController = PanelPositionController()
        let launchAtLoginService = LaunchAtLoginService()
        let updaterController = AppUpdaterController()
        let commandModel = AppCommandModel(
            newNotionPage: { actionRelay.openNewNotionPage() },
            settings: { actionRelay.showSettings() },
            gettingStarted: { actionRelay.showGettingStarted() },
            canCheckForUpdates: { [weak updaterController] in
                updaterController?.canCheckForUpdates ?? false
            },
            checkForUpdates: { [weak updaterController] in
                updaterController?.checkForUpdates()
            },
            quit: { actionRelay.quit() }
        )
        let pageSwitcherController = PageSwitcherController(store: pageRepository)
        let pageSwitcherRelay = PageSwitcherSelectionRelay()
        let recentPageSelectionRelay = PiPRecentPageSelectionRelay()
        let recentPagesController = PiPRecentPagesShelfController(
            store: pageRepository,
            currentPageProvider: recentPageSelectionRelay.currentPage
        )
        let stashHandle = PiPStashHandleController(
            recentPagesController: recentPagesController,
            onSelectRecentPage: recentPageSelectionRelay.perform
        )
        let panelCoordinator = PiPPanelCoordinator(
            webSession: webSession,
            pageSwitcherController: pageSwitcherController,
            commandModel: commandModel,
            onReloadSavedPin: { actionRelay.reloadSavedPin() },
            panelSizeController: panelSizeController,
            panelPositionController: panelPositionController,
            onPageSwitcherSelection: pageSwitcherRelay.perform,
            stashHandle: stashHandle
        )
        let runtime = AppRuntime(
            panelCoordinator: panelCoordinator,
            pageRepository: pageRepository,
            initialServiceHealth: persistenceResult.initialServiceHealth,
            automaticSettingsPresentationAllowed: {
                startupPresentationGate.allowsCompetingPresentation
                    && !onboardingPreferenceStore.shouldPresent(
                    version: OnboardingCoordinator.currentVersion
                )
            }
        )
        let contextSuggestionController = ContextSuggestionController(
            monitor: AccessibilityContextMonitor(),
            store: pageRepository,
            preferenceStore: ContextSuggestionPreferenceStore(),
            activePageID: { [weak runtime] in runtime?.activePage?.pageID },
            onActivate: { [weak runtime] page, restoration in
                runtime?.activate(
                    page: page,
                    source: .contextSuggestion,
                    restoration: restoration
                )
            }
        )
        let contextSuggestionPanelController = ContextSuggestionPanelController(
            controller: contextSuggestionController
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
            runtime?.activateRecentPage(selection)
        }
        recentPageSelectionRelay.currentPageProvider = { [weak runtime] in
            runtime?.activePage
        }

        let settingsWindowPresenter = SettingsWindowPresenter { closeHandler in
            AppWindowFactory.makeSettings(
                runtime: runtime,
                panelSizeController: panelSizeController,
                launchAtLoginService: launchAtLoginService,
                contextSuggestionController: contextSuggestionController,
                closeRequestHandler: closeHandler
            )
        }
        let recoveryGuardedSettingsWindowPresenter =
            RecoveryGuardedSettingsWindowPresenter(
                presenter: settingsWindowPresenter,
                gate: startupPresentationGate
            )
        let onboardingCoordinator = OnboardingCoordinator(
            preferenceStore: onboardingPreferenceStore,
            settingsWindowPresenter: recoveryGuardedSettingsWindowPresenter,
            openCurrentPage: runtime.validatePageURL,
            onFinish: runtime.suppressAutomaticCurrentPageSetup,
            makeWindowPresenter: { openPage, completion, openSettings in
                AppWindowFactory.makeOnboarding(
                    globalShortcut: runtime.globalShortcut,
                    pageURLInputState: runtime.pageURLInputState,
                    onPinPage: openPage,
                    onComplete: completion,
                    onOpenSettings: openSettings
                )
            }
        )
        let startupRecoveryActionRelay = StartupRecoveryActionRelay()
        let storageRecoveryController: StorageRecoveryController?
        let storageRecoveryPresenter: (any AppWindowPresenting)?
        if let recoveryContext {
            let controller = StorageRecoveryController(
                context: recoveryContext,
                continueWithoutSaving: startupRecoveryActionRelay.continueWithoutSaving,
                requestTermination: { NSApp.terminate(nil) }
            )
            storageRecoveryController = controller
            storageRecoveryPresenter = AppWindowFactory.makeStorageRecovery(
                controller: controller,
                closeRequestHandler: controller.continueWithoutSaving
            )
        } else {
            storageRecoveryController = nil
            storageRecoveryPresenter = nil
        }
        let startupRecoveryCoordinator = StartupRecoveryCoordinator(
            recoveryRequired: recoveryContext != nil,
            gate: startupPresentationGate,
            recoveryPresenter: storageRecoveryPresenter,
            showOnboardingIfNeeded: onboardingCoordinator.showIfNeeded,
            showCurrentPageSetup: runtime.presentCurrentPageSetup
        )
        startupRecoveryActionRelay.handler =
            startupRecoveryCoordinator.continueWithoutSaving
        let statusItemController = StatusItemController(
            runtime: runtime,
            commandModel: commandModel,
            panelSizeController: panelSizeController
        )
        runtime.publishStatusItemSession(
            sessionState: webSession.state,
            loginState: webSession.browserLoginState
        )
        statusItemAppearanceCancellable = webSession.objectWillChange.sink {
            [weak runtime, weak webSession] in
            Task { @MainActor in
                guard let runtime, let webSession else { return }
                runtime.publishStatusItemSession(
                    sessionState: webSession.state,
                    loginState: webSession.browserLoginState
                )
            }
        }
        contextSuggestionActivePageCancellable = runtime.$activePage
            .dropFirst()
            .sink { [weak contextSuggestionController] _ in
                Task { @MainActor in
                    contextSuggestionController?.activePageDidChange()
                }
            }

        actionRelay.settingsWindowPresenter = recoveryGuardedSettingsWindowPresenter
        actionRelay.gettingStartedAction = { [weak onboardingCoordinator] in
            onboardingCoordinator?.show()
        }
        runtime.bind(settingsWindowPresenter: recoveryGuardedSettingsWindowPresenter)
        runtime.bindPersistentStoreRecoveryAction(
            startupRecoveryCoordinator.showRecoveryOptions
        )
        panelSizeController.onManagePanelSizes = {
            actionRelay.showSettings()
        }
        contextSuggestionController.start()

        self.runtime = runtime
        self.onboardingCoordinator = onboardingCoordinator
        self.startupRecoveryCoordinator = startupRecoveryCoordinator
        self.settingsWindowPresenter = settingsWindowPresenter
        self.recoveryGuardedSettingsWindowPresenter =
            recoveryGuardedSettingsWindowPresenter
        self.storageRecoveryController = storageRecoveryController
        self.storageRecoveryPresenter = storageRecoveryPresenter
        self.statusItemController = statusItemController
        self.updaterController = updaterController
        self.panelSizeController = panelSizeController
        self.panelPositionController = panelPositionController
        self.launchAtLoginService = launchAtLoginService
        self.contextSuggestionController = contextSuggestionController
        self.contextSuggestionPanelController = contextSuggestionPanelController
    }
}

@MainActor
private final class StartupRecoveryActionRelay {
    var handler: @MainActor () -> Void = {}

    func continueWithoutSaving() {
        handler()
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
    var currentPageProvider: () -> NotionPageReference? = { nil }

    func perform(_ selection: PiPRecentPageSelection) {
        handler(selection)
    }

    func currentPage() -> NotionPageReference? {
        currentPageProvider()
    }
}
