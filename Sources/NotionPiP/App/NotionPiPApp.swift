import AppKit
import OSLog

@main
enum NotionPiPApp {
    static func main() {
        let coldLaunchToken = AppPerformanceSignposter.shared.begin(.coldLaunchToReady)
        let composition = AppComposition()
        let appDelegate = AppDelegate()
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.mainMenu = AppMainMenuFactory.make()
        AppStartup.start(
            runtime: composition.runtime,
            appDelegate: appDelegate,
            coldLaunchToken: coldLaunchToken,
            terminationParticipantProvider: {
                composition.quickCaptureTerminationParticipant
            }
        )
        withExtendedLifetime(composition) {
            application.run()
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
        terminationParticipantProvider:
            @escaping @MainActor () -> (
                any ApplicationTerminationParticipating
            )? = { nil }
    ) {
        runtime.start()
        appDelegate.bind(
            coldLaunchToken: coldLaunchToken,
            performanceSignposter: performanceSignposter
        )
        appDelegate.bind {
            let shouldTerminate =
                await terminationParticipantProvider()?
                .prepareForTermination() ?? true
            await runtime.prepareForTermination()
            return shouldTerminate
        }
        appDelegate.bind(urlHandler: runtime)
    }
}

@MainActor
private final class AppComposition {
    let runtime: AppRuntime
    private let quickCapturePresenter: LazyAppWindowPresenter
    private let quickCaptureReleaseRelay: QuickCaptureReleaseRelay
    private let settingsWindowPresenter: SettingsWindowPresenter
    private let statusItemController: StatusItemController
    private let panelSizeController: PanelSizeController

    init() {
        let actionRelay = AppCommandActionRelay()
        let webSession = NotionWebSession()
        let credentialVault = PersonalTokenCredentialVault()
        let pageRepository: PageRepository?
        let captureRepository: CaptureRepository?
        let destinationRepository: QuickCaptureDestinationRepository?
        let deliveryScheduler: DeliveryScheduler?
        let initialServiceHealth: ServiceHealthState

        do {
            let container = try NotionPiPPersistence.makeContainer()
            let captures = CaptureRepository(container: container)
            let destinations = QuickCaptureDestinationRepository(container: container)
            let captureAPI = PersonalTokenNotionCaptureAPI(
                credentialVault: credentialVault
            )
            let deliveryService = NotionCaptureDeliveryService(
                repository: captures,
                api: captureAPI
            )
            let engine = DeliveryEngine(
                repository: captures,
                transport: deliveryService
            )
            let scheduler = DeliveryScheduler(
                repository: captures,
                engine: engine
            )
            pageRepository = PageRepository(container: container)
            captureRepository = captures
            destinationRepository = destinations
            deliveryScheduler = scheduler
            initialServiceHealth = .healthy
        } catch {
            Logger(subsystem: "com.fantomsuj.NotionPiP", category: "persistence")
                .error("Persistent store unavailable")
            pageRepository = nil
            captureRepository = nil
            destinationRepository = nil
            deliveryScheduler = nil
            initialServiceHealth = ServiceHealthState(issues: [.persistentStoreUnavailable])
        }

        let panelSizeController = PanelSizeController()
        let commandModel = AppCommandModel(
            quickCapture: { actionRelay.showQuickCapture() },
            settings: { actionRelay.showSettings() },
            quit: { actionRelay.quit() }
        )
        let pageSwitcherController = PageSwitcherController(store: pageRepository)
        let pageSwitcherRelay = PageSwitcherSelectionRelay()
        let panelCoordinator = PiPPanelCoordinator(
            webSession: webSession,
            pageSwitcherController: pageSwitcherController,
            commandModel: commandModel,
            onReloadSavedPin: { actionRelay.reloadSavedPin() },
            panelSizeController: panelSizeController,
            onPageSwitcherSelection: pageSwitcherRelay.perform
        )
        let runtime = AppRuntime(
            panelCoordinator: panelCoordinator,
            pageRepository: pageRepository,
            destinationRepository: destinationRepository,
            captureRepository: captureRepository,
            deliveryScheduler: deliveryScheduler,
            credentialVault: credentialVault,
            initialServiceHealth: initialServiceHealth
        )
        actionRelay.reloadSavedPinAction = { [weak runtime] in
            runtime?.reloadSavedPin()
        }
        let captureLifecycle: QuickCaptureLifecycleCoordinator?
        if let captureRepository, let destinationRepository, let deliveryScheduler {
            captureLifecycle = QuickCaptureLifecycleCoordinator(
                repository: captureRepository,
                destinations: destinationRepository,
                hasUsableToken: { [weak runtime] in
                    await MainActor.run {
                        runtime?.hasUsablePersonalToken() == true
                    }
                },
                onEnqueued: { _ in
                    Task {
                        await deliveryScheduler.trigger()
                    }
                }
            )
        } else {
            captureLifecycle = nil
        }
        webSession.onPageResolved = { [weak runtime] page in
            runtime?.activate(page: page, source: .notionWebSession)
        }
        let quickCaptureReleaseRelay = QuickCaptureReleaseRelay()
        let quickCapturePrefillRelay = QuickCapturePrefillRelay()
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
        let quickCapturePresenter = LazyAppWindowPresenter(
            makePresenter: {
                let presenter = AppWindowFactory.makeQuickCapture(
                    repository: captureRepository,
                    lifecycle: captureLifecycle,
                    onSessionCreated: { session in
                        quickCapturePrefillRelay.bind(session)
                    },
                    onNeedsConfiguration: { _ in
                        actionRelay.showSettings()
                    },
                    onSuccessfulClose: { [weak quickCaptureReleaseRelay] in
                        quickCaptureReleaseRelay?.scheduleReleaseAfterSuccessfulClose()
                    }
                ) { [weak runtime] in
                    guard let page = runtime?.activePage else { return }
                    NSWorkspace.shared.open(page.canonicalURL)
                }
                return presenter
            },
            performanceSignposter: AppPerformanceSignposter.shared,
            firstPresentationOperation: .firstQuickCapturePresentation
        )
        quickCaptureReleaseRelay.presenter = quickCapturePresenter
        let settingsWindowPresenter = SettingsWindowPresenter(
            windowPresenter: AppWindowFactory.makeSettings(
                runtime: runtime,
                panelSizeController: panelSizeController
            )
        )
        let statusItemController = StatusItemController(
            runtime: runtime,
            commandModel: commandModel,
            panelSizeController: panelSizeController
        )

        actionRelay.quickCapturePresenter = quickCapturePresenter
        actionRelay.quickCapturePrefillAction = { text in
            quickCapturePrefillRelay.prefill(text)
        }
        runtime.quickCaptureAction = { [weak webSession] prefill, insertAtCursor in
            guard insertAtCursor, let prefill, let webSession else {
                actionRelay.showQuickCapture(prefill: prefill)
                return
            }
            webSession.insertAtSavedEditorCursor(prefill) { inserted in
                if !inserted { actionRelay.showQuickCapture(prefill: prefill) }
            }
        }
        actionRelay.settingsWindowPresenter = settingsWindowPresenter
        runtime.bind(settingsWindowPresenter: settingsWindowPresenter)
        panelSizeController.onManagePanelSizes = {
            actionRelay.showSettings()
        }

        self.runtime = runtime
        self.quickCapturePresenter = quickCapturePresenter
        self.quickCaptureReleaseRelay = quickCaptureReleaseRelay
        self.settingsWindowPresenter = settingsWindowPresenter
        self.statusItemController = statusItemController
        self.panelSizeController = panelSizeController
    }

    var quickCaptureTerminationParticipant:
        (
            any ApplicationTerminationParticipating
        )?
    {
        quickCapturePresenter.terminationParticipant
    }
}

@MainActor
private final class QuickCapturePrefillRelay {
    weak var session: CaptureEditorSession?
    private var pending: String?

    func bind(_ session: CaptureEditorSession) {
        self.session = session
        if let pending { self.pending = nil; prefill(pending) }
    }

    func prefill(_ text: String) {
        guard let session else { pending = text; return }
        Task { @MainActor in
            if !(await session.prefill(text)) { self.pending = text }
        }
    }
}

@MainActor
private final class QuickCaptureReleaseRelay {
    weak var presenter: LazyAppWindowPresenter?

    func scheduleReleaseAfterSuccessfulClose() {
        presenter?.scheduleReleaseAfterSuccessfulClose()
    }
}

@MainActor
private final class PageSwitcherSelectionRelay {
    var handler: (PageSwitcherSelection) -> Void = { _ in }

    func perform(_ selection: PageSwitcherSelection) {
        handler(selection)
    }
}
