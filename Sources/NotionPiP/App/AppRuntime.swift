import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?
    @Published private(set) var lastActivationSource: PageActivationSource?
    @Published private(set) var captureRecords: [CaptureRecordSummary] = []
    @Published private(set) var captureRecoveryMessage: String?
    @Published private(set) var serviceHealth: ServiceHealthState
    @Published private(set) var shortcutConfiguration: ShortcutConfiguration
    @Published private(set) var holdToPeekEnabled: Bool
    @Published private(set) var quickCapturePrefillsClipboard: Bool
    @Published private(set) var quickCaptureInsertsAtNotionCursor: Bool
    @Published private(set) var savedMenuBarIconVisibility: Bool
    @Published private(set) var effectiveMenuBarIconVisibility: Bool
    @Published private(set) var isMenuBarIconVisibilityForced: Bool

    var globalShortcut: GlobalShortcut { shortcutConfiguration.panel }
    var quickCaptureShortcut: GlobalShortcut { shortcutConfiguration.quickCapture }

    let pageURLInputState: PageURLInputState

    var pageURLText: String {
        get { pageURLInputState.text }
        set { pageURLInputState.text = newValue }
    }

    var validationMessage: String? { pageURLInputState.validationMessage }
    var validationFailed: Bool { pageURLInputState.validationFailed }
    var pageURLFocusRequest: Int { pageURLInputState.focusRequest }

    var connectionState: PersonalTokenConnectionState { connectionController.state }
    var searchResults: [NotionPageSearchResult] { connectionController.searchResults }
    var searchError: String? { connectionController.searchError }
    var isNotionConnected: Bool { connectionController.isConnected }
    var quickCaptureDestination: QuickCaptureDestination? { destinationController.destination }
    var destinationSearchResults: [NotionDestinationSearchResult] {
        destinationController.searchResults
    }
    var destinationSearchError: String? { destinationController.searchError }
    var isSearchingDestinations: Bool { destinationController.isSearching }
    var canLoadMoreDestinations: Bool { destinationController.canLoadMore }
    var isDestinationSearchCapped: Bool { destinationController.isSearchCapped }
    var pipPresentationState: PiPPresentationState { pinCoordinator.presentationState }

    var statusMenuContextCommand: StatusMenuContextCommand {
        StatusMenuContextCommand(presentationState: pipPresentationState)
    }

    let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "shortcut")
    let pinCoordinator: PinCoordinator
    let shortcutRegistrar: any GlobalShortcutRegistering
    let shortcutStore: GlobalShortcutStore
    let holdToPeekPreferenceStore: HoldToPeekPreferenceStore
    let peekFocusRestorer: any PeekFocusRestoring
    let performanceSignposter: any PerformanceSignposting
    let quickCaptureShortcutRegistrar: any GlobalShortcutRegistering
    let quickCaptureShortcutStore: QuickCaptureShortcutStore
    let trustedCapturePreferenceStore: TrustedCapturePreferenceStore
    let pasteboard: any PasteboardReading
    var quickCaptureAction: (_ prefill: String?, _ insertAtCursor: Bool) -> Void = { _, _ in }
    let menuBarIconPreferenceStore: MenuBarIconPreferenceStore
    let pageURLInputPresenter: any PageURLInputPresenting
    let pageRepository: (any PageWorkingSetPersisting)?
    let automaticSettingsPresentationAllowed: @MainActor () -> Bool
    private let captureRepository: CaptureRepository?
    private let deliveryScheduler: DeliveryScheduler?
    private let connectionController: NotionConnectionController
    private let destinationController: QuickCaptureDestinationController
    weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private var connectionObservation: AnyCancellable?
    private var destinationObservation: AnyCancellable?
    private var bootstrapTask: Task<Void, Never>?
    var restorePinnedPageTask: Task<Void, Never>?
    var persistPinnedPageTask: Task<Void, Never>?
    var firstPageHandoffTask: Task<Void, Never>?
    var isFirstPageHandoffPending = false
    var persistenceGeneration = 0
    var pageSelectionGeneration = 0
    let shortcutHoldDuration: Duration
    let shortcutGestureScheduler: any ShortcutGestureScheduling
    let accessibilityAnnouncementPoster: any AccessibilityAnnouncementPosting
    let shortcutLifecycleCoordinatorFactory:
        (@escaping @MainActor (ShortcutRecoveryTrigger) -> Void) -> ShortcutLifecycleCoordinator
    var shortcutLifecycleCoordinator: ShortcutLifecycleCoordinator?
    var shortcutConfigurationGeneration: UInt = 0
    var shortcutGestureTimer: (any ShortcutGestureTimer)?
    var shortcutGestureState = ShortcutPeekGestureState.idle
    var shortcutGestureGeneration: UInt = 0
    private var started = false

    init(
        panelCoordinator: (any PiPPanelCoordinating)? = nil,
        pasteboard: any PasteboardReading = SystemPasteboardReader(),
        shortcutRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        shortcutStore: GlobalShortcutStore = GlobalShortcutStore(),
        quickCaptureShortcutRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        quickCaptureShortcutStore: QuickCaptureShortcutStore = QuickCaptureShortcutStore(),
        trustedCapturePreferenceStore: TrustedCapturePreferenceStore = TrustedCapturePreferenceStore(),
        menuBarIconPreferenceStore: MenuBarIconPreferenceStore = MenuBarIconPreferenceStore(),
        holdToPeekPreferenceStore: HoldToPeekPreferenceStore = HoldToPeekPreferenceStore(),
        peekFocusRestorer: any PeekFocusRestoring = PeekFocusRestorer(),
        performanceSignposter: any PerformanceSignposting = AppPerformanceSignposter.shared,
        pageURLInputPresenter: (any PageURLInputPresenting)? = nil,
        pageRepository: (any PageWorkingSetPersisting)? = nil,
        destinationRepository: (any QuickCaptureDestinationPersisting)? = nil,
        captureRepository: CaptureRepository? = nil,
        deliveryScheduler: DeliveryScheduler? = nil,
        credentialVault: PersonalTokenCredentialVault = PersonalTokenCredentialVault(),
        notionClientFactory: @escaping (PersonalIntegrationToken) -> any NotionWorkspaceClient = { token in
            NotionAPIClient(token: token)
        },
        destinationSearchDebounceDuration: Duration = .milliseconds(300),
        shortcutHoldDuration: Duration = .milliseconds(300),
        shortcutGestureScheduler: any ShortcutGestureScheduling = TaskShortcutGestureScheduler(),
        accessibilityAnnouncementPoster: any AccessibilityAnnouncementPosting =
            AppAccessibilityAnnouncementPoster(),
        initialServiceHealth: ServiceHealthState = .healthy,
        automaticSettingsPresentationAllowed: @escaping @MainActor () -> Bool = { true },
        shortcutLifecycleCoordinatorFactory:
            @escaping (@escaping @MainActor (ShortcutRecoveryTrigger) -> Void) -> ShortcutLifecycleCoordinator = {
                ShortcutLifecycleCoordinator(onRecovery: $0)
            }
    ) {
        let inputState = PageURLInputState()
        let submissionRelay = PageURLInputSubmissionRelay()
        let inputPresenter = pageURLInputPresenter ?? PageURLInputPresenter(
            state: inputState,
            onSubmit: submissionRelay.submit
        )

        pageURLInputState = inputState
        self.pageURLInputPresenter = inputPresenter
        pinCoordinator = PinCoordinator(
            panelCoordinator: panelCoordinator ?? PiPPanelCoordinator(),
            pasteboard: pasteboard,
            requestPageURLFocus: inputPresenter.presentAndFocus
        )
        self.shortcutRegistrar = shortcutRegistrar
        self.shortcutStore = shortcutStore
        self.holdToPeekPreferenceStore = holdToPeekPreferenceStore
        self.peekFocusRestorer = peekFocusRestorer
        self.performanceSignposter = performanceSignposter
        self.quickCaptureShortcutRegistrar = quickCaptureShortcutRegistrar
        self.quickCaptureShortcutStore = quickCaptureShortcutStore
        self.trustedCapturePreferenceStore = trustedCapturePreferenceStore
        self.pasteboard = pasteboard
        self.menuBarIconPreferenceStore = menuBarIconPreferenceStore
        self.pageRepository = pageRepository
        self.automaticSettingsPresentationAllowed = automaticSettingsPresentationAllowed
        self.captureRepository = captureRepository
        self.deliveryScheduler = deliveryScheduler
        self.shortcutHoldDuration = shortcutHoldDuration
        self.shortcutGestureScheduler = shortcutGestureScheduler
        self.accessibilityAnnouncementPoster = accessibilityAnnouncementPoster
        self.shortcutLifecycleCoordinatorFactory = shortcutLifecycleCoordinatorFactory
        let connectionController = NotionConnectionController(
            credentialVault: credentialVault,
            notionClientFactory: notionClientFactory,
            onReconnect: {
                await deliveryScheduler?.trigger(reconnected: true)
            }
        )
        self.connectionController = connectionController
        destinationController = QuickCaptureDestinationController(
            connectionController: connectionController,
            repository: destinationRepository,
            searchDebounceDuration: destinationSearchDebounceDuration
        )
        serviceHealth = initialServiceHealth
        let panelShortcut = shortcutStore.load()
        let loadedQuickCaptureShortcut = quickCaptureShortcutStore.load()
        let quickCaptureShortcut = Self.distinctQuickCaptureShortcut(
            loadedQuickCaptureShortcut,
            panelShortcut: panelShortcut
        )
        shortcutConfiguration = ShortcutConfiguration(
            panel: panelShortcut,
            quickCapture: quickCaptureShortcut
        )
        holdToPeekEnabled = holdToPeekPreferenceStore.load()
        quickCapturePrefillsClipboard = trustedCapturePreferenceStore.prefillsClipboard
        quickCaptureInsertsAtNotionCursor = trustedCapturePreferenceStore.insertsAtNotionCursor
        let iconState = Self.menuBarIconState(
            store: menuBarIconPreferenceStore,
            serviceHealth: initialServiceHealth
        )
        savedMenuBarIconVisibility = iconState.saved
        effectiveMenuBarIconVisibility = iconState.effective
        isMenuBarIconVisibilityForced = iconState.forced
        observeControllers()
        pinCoordinator.onExternalPresentationAction = { [weak self] in
            self?.cancelShortcutGesture(restashTransientPanel: false)
        }
        submissionRelay.handler = { [weak self] in
            self?.validatePageURL()
        }
    }

    func start() {
        guard !started else {
            return
        }
        started = true

        registerGlobalShortcut()
        registerQuickCaptureShortcut()
        let shortcutLifecycleCoordinator = shortcutLifecycleCoordinatorFactory { [weak self] trigger in
            self?.recoverShortcuts(trigger: trigger)
        }
        self.shortcutLifecycleCoordinator = shortcutLifecycleCoordinator
        shortcutLifecycleCoordinator.start()
        bootstrapTask = Task { [weak self] in
            await self?.bootstrapPersonalTokenConnection()
        }
        Task { [weak self] in
            await self?.destinationController.loadSavedDestination()
            await self?.deliveryScheduler?.trigger()
        }
        restorePinnedPageFromRepository()
    }

    func bind(settingsWindowPresenter: any SettingsWindowPresenting) {
        self.settingsWindowPresenter = settingsWindowPresenter
    }

    func retryRecovery(for issue: ServiceHealthIssue) {
        switch issue {
        case .globalShortcutUnavailable:
            registerGlobalShortcut()
        case .quickCaptureShortcutUnavailable:
            registerQuickCaptureShortcut()
        case .pinnedPagePersistenceUnavailable:
            if let activePage {
                enqueuePersistence(of: activePage)
            } else {
                restorePinnedPageFromRepository()
            }
        case .persistentStoreUnavailable:
            break
        }
    }

    func connectPersonalToken(_ rawValue: String) async {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        await connectionController.connect(rawValue)
    }

    func bootstrapPersonalTokenConnection() async {
        await connectionController.bootstrapSavedToken()
    }

    func disconnectPersonalToken() {
        connectionController.disconnect()
        guard connectionController.state == .disconnected else { return }
        bootstrapTask?.cancel()
        bootstrapTask = nil
        destinationController.resetAfterDisconnect()
    }

    func searchNotionPages(query: String) async {
        await connectionController.searchPages(query: query)
    }

    func searchQuickCaptureDestinations(query: String) async {
        await destinationController.search(query: query)
    }

    func scheduleQuickCaptureDestinationSearch(query: String) {
        destinationController.scheduleSearch(query: query)
    }

    func loadMoreQuickCaptureDestinations() async {
        await destinationController.loadMore()
    }

    func selectQuickCaptureDestination(
        _ destination: QuickCaptureDestination
    ) async {
        await destinationController.select(destination)
    }

    func clearQuickCaptureDestination() async {
        await destinationController.clear()
    }

    func hasUsablePersonalToken() -> Bool {
        connectionController.hasUsableToken()
    }

    func publishActivation(
        page: NotionPageReference,
        source: PageActivationSource
    ) {
        activePage = page
        pendingPage = page
        lastActivationSource = source
    }

    func publishHoldToPeekEnabled(_ enabled: Bool) {
        holdToPeekEnabled = enabled
    }

    func publishShortcutConfiguration(_ configuration: ShortcutConfiguration) {
        shortcutConfiguration = configuration
    }

    func publishQuickCapturePrefillsClipboard(_ enabled: Bool) {
        quickCapturePrefillsClipboard = enabled
    }

    func publishQuickCaptureInsertsAtNotionCursor(_ enabled: Bool) {
        quickCaptureInsertsAtNotionCursor = enabled
    }

    func handleQuickCaptureShortcut() {
        let prefill = quickCapturePrefillsClipboard ? pasteboard.readString() : nil
        quickCaptureAction(prefill, quickCaptureInsertsAtNotionCursor)
    }

    func publishMenuBarIconVisibility(_ isVisible: Bool) {
        savedMenuBarIconVisibility = isVisible
        updateEffectiveMenuBarIconVisibility()
    }

    func reportServiceIssue(_ issue: ServiceHealthIssue) {
        serviceHealth.report(issue)
        if issue == .globalShortcutUnavailable {
            updateEffectiveMenuBarIconVisibility()
        }
    }

    func resolveServiceIssue(_ issue: ServiceHealthIssue) {
        serviceHealth.resolve(issue)
        if issue == .globalShortcutUnavailable {
            updateEffectiveMenuBarIconVisibility()
        }
    }

    private func updateEffectiveMenuBarIconVisibility() {
        let isForced = serviceHealth.issues.contains(.globalShortcutUnavailable)
            && !savedMenuBarIconVisibility
        isMenuBarIconVisibilityForced = isForced
        effectiveMenuBarIconVisibility = savedMenuBarIconVisibility || isForced
    }

    private func observeControllers() {
        connectionObservation = connectionController.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        destinationObservation = destinationController.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private static func menuBarIconState(
        store: MenuBarIconPreferenceStore,
        serviceHealth: ServiceHealthState
    ) -> MenuBarIconState {
        let saved = store.load()
        let forced = serviceHealth.issues.contains(.globalShortcutUnavailable) && !saved
        return MenuBarIconState(saved: saved, effective: saved || forced, forced: forced)
    }

    private static func distinctQuickCaptureShortcut(
        _ shortcut: GlobalShortcut,
        panelShortcut: GlobalShortcut
    ) -> GlobalShortcut {
        guard shortcut == panelShortcut else { return shortcut }
        return panelShortcut == .defaultQuickCapture ? .default : .defaultQuickCapture
    }

    isolated deinit {
        shortcutLifecycleCoordinator?.stop()
    }
}

extension AppRuntime {
    func refreshCaptureRecords() async {
        guard let captureRepository else { return }
        do {
            captureRecords = try await captureRepository.recentRecordSummaries(limit: 10)
            captureRecoveryMessage = nil
        } catch {
            captureRecoveryMessage = "Could not load Quick Capture delivery history."
        }
    }

    func openLocalCapture(recordID: String) async {
        guard let captureRepository else {
            captureRecoveryMessage = "Local capture recovery is unavailable."
            return
        }
        do {
            guard let record = try await captureRepository.record(id: recordID) else {
                captureRecoveryMessage = "The local capture could not be found."
                return
            }
            let markdown = try CaptureExport.markdown(records: [record], drafts: [])
            let safeID = record.id.filter { $0.isLetter || $0.isNumber }.prefix(24)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("NotionPiP-Recovery-\(safeID).md")
            try Data(markdown.utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
            captureRecoveryMessage = nil
        } catch {
            captureRecoveryMessage = "Could not open the local capture export."
        }
    }
}

private struct MenuBarIconState {
    let saved: Bool
    let effective: Bool
    let forced: Bool
}

@MainActor
private final class PageURLInputSubmissionRelay {
    var handler: () -> Void = {}

    func submit() {
        handler()
    }
}
