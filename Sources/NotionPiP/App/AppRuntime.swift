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
    @Published private(set) var globalShortcut: GlobalShortcut
    @Published private(set) var quickCaptureShortcut: GlobalShortcut
    @Published private(set) var quickCapturePrefillsClipboard: Bool
    @Published private(set) var quickCaptureInsertsAtNotionCursor: Bool
    @Published private(set) var savedMenuBarIconVisibility: Bool
    @Published private(set) var effectiveMenuBarIconVisibility: Bool
    @Published private(set) var isMenuBarIconVisibilityForced: Bool

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
    let quickCaptureShortcutRegistrar: any GlobalShortcutRegistering
    let quickCaptureShortcutStore: QuickCaptureShortcutStore
    let trustedCapturePreferenceStore: TrustedCapturePreferenceStore
    let pasteboard: any PasteboardReading
    var quickCaptureAction: (_ prefill: String?, _ insertAtCursor: Bool) -> Void = { _, _ in }
    let menuBarIconPreferenceStore: MenuBarIconPreferenceStore
    let pageURLInputPresenter: any PageURLInputPresenting
    let pageRepository: (any PageWorkingSetPersisting)?
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
    var persistenceGeneration = 0
    var pageSelectionGeneration = 0
    let shortcutHoldDuration: Duration
    var shortcutHoldTask: Task<Void, Never>?
    var shortcutHoldTriggered = false
    var shortcutPeekRestoredPanel = false
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
        initialServiceHealth: ServiceHealthState = .healthy
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
        self.quickCaptureShortcutRegistrar = quickCaptureShortcutRegistrar
        self.quickCaptureShortcutStore = quickCaptureShortcutStore
        self.trustedCapturePreferenceStore = trustedCapturePreferenceStore
        self.pasteboard = pasteboard
        self.menuBarIconPreferenceStore = menuBarIconPreferenceStore
        self.pageRepository = pageRepository
        self.captureRepository = captureRepository
        self.deliveryScheduler = deliveryScheduler
        self.shortcutHoldDuration = shortcutHoldDuration
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
        globalShortcut = shortcutStore.load()
        quickCaptureShortcut = quickCaptureShortcutStore.load()
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

    func publishGlobalShortcut(_ shortcut: GlobalShortcut) {
        globalShortcut = shortcut
    }

    func publishQuickCaptureShortcut(_ shortcut: GlobalShortcut) {
        quickCaptureShortcut = shortcut
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
