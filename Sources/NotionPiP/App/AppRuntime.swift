import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?
    @Published private(set) var lastActivationSource: PageActivationSource?
    @Published private(set) var captureRecords: [CaptureRecordSnapshot] = []
    @Published private(set) var captureRecoveryMessage: String?
    @Published private(set) var serviceHealth: ServiceHealthState
    @Published private(set) var globalShortcut: GlobalShortcut

    let pageURLInputState: PageURLInputState

    var pageURLText: String {
        get { pageURLInputState.text }
        set { pageURLInputState.text = newValue }
    }

    var validationMessage: String? {
        pageURLInputState.validationMessage
    }

    var validationFailed: Bool {
        pageURLInputState.validationFailed
    }

    var pageURLFocusRequest: Int {
        pageURLInputState.focusRequest
    }

    var connectionState: PersonalTokenConnectionState {
        connectionController.state
    }

    var searchResults: [NotionPageSearchResult] {
        connectionController.searchResults
    }

    var searchError: String? {
        connectionController.searchError
    }

    var isNotionConnected: Bool {
        connectionController.isConnected
    }

    var quickCaptureDestination: QuickCaptureDestination? {
        destinationController.destination
    }

    var destinationSearchResults: [NotionDestinationSearchResult] {
        destinationController.searchResults
    }

    var destinationSearchError: String? {
        destinationController.searchError
    }

    var isSearchingDestinations: Bool {
        destinationController.isSearching
    }

    var canLoadMoreDestinations: Bool {
        destinationController.canLoadMore
    }

    var isDestinationSearchCapped: Bool {
        destinationController.isSearchCapped
    }

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "shortcut")
    private let pinCoordinator: PinCoordinator
    private let shortcutRegistrar: any GlobalShortcutRegistering
    private let shortcutStore: GlobalShortcutStore
    private let pageURLInputPresenter: any PageURLInputPresenting
    private let pageRepository: (any PinnedPagePersisting)?
    private let captureRepository: CaptureRepository?
    private let deliveryScheduler: DeliveryScheduler?
    private let connectionController: NotionConnectionController
    private let destinationController: QuickCaptureDestinationController
    private weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private var connectionObservation: AnyCancellable?
    private var destinationObservation: AnyCancellable?
    private var bootstrapTask: Task<Void, Never>?
    private var restorePinnedPageTask: Task<Void, Never>?
    private var persistPinnedPageTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var pageSelectionGeneration = 0
    private var started = false

    init(
        panelCoordinator: (any PiPPanelCoordinating)? = nil,
        pasteboard: any PasteboardReading = SystemPasteboardReader(),
        shortcutRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        shortcutStore: GlobalShortcutStore = GlobalShortcutStore(),
        pageURLInputPresenter: (any PageURLInputPresenting)? = nil,
        pageRepository: (any PinnedPagePersisting)? = nil,
        destinationRepository: (any QuickCaptureDestinationPersisting)? = nil,
        captureRepository: CaptureRepository? = nil,
        deliveryScheduler: DeliveryScheduler? = nil,
        credentialVault: PersonalTokenCredentialVault = PersonalTokenCredentialVault(),
        legacyCacheCleaner: any LegacyNativePageCacheCleaning = NoOpLegacyNativePageCacheCleaner(),
        legacyCacheDirectory: URL = FileSystemLegacyNativePageCacheCleaner.defaultDirectoryURL,
        notionClientFactory: @escaping (PersonalIntegrationToken) -> any NotionWorkspaceClient = { token in
            NotionAPIClient(token: token)
        },
        destinationSearchDebounceDuration: Duration = .milliseconds(300),
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
        self.pageRepository = pageRepository
        self.captureRepository = captureRepository
        self.deliveryScheduler = deliveryScheduler
        let connectionController = NotionConnectionController(
            credentialVault: credentialVault,
            legacyCacheCleaner: legacyCacheCleaner,
            legacyCacheDirectory: legacyCacheDirectory,
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
        connectionObservation = connectionController.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        destinationObservation = destinationController.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
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

        bootstrapTask = Task { [weak self] in
            await self?.bootstrapPersonalTokenConnection()
        }
        Task { [weak self] in
            await self?.destinationController.loadSavedDestination()
            await self?.deliveryScheduler?.trigger()
            await self?.refreshCaptureRecords()
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

    @discardableResult
    func applyGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        do {
            try shortcutRegistrar.register(shortcut: shortcut) { [weak self] in
                self?.handleGlobalShortcut()
            }
            globalShortcut = shortcut
            shortcutStore.save(shortcut)
            resolveServiceIssue(.globalShortcutUnavailable)
            return true
        } catch {
            logger.error("Global shortcut registration failed")
            reportServiceIssue(.globalShortcutUnavailable)
            return false
        }
    }

    func resetGlobalShortcut() {
        _ = applyGlobalShortcut(.default)
    }

    func prepareForTermination() async {
        while let persistenceTask = persistPinnedPageTask {
            let expectedGeneration = persistenceGeneration
            await persistenceTask.value
            guard expectedGeneration != persistenceGeneration else { return }
        }
    }

    func handleMenuBarActivation() {
        guard pinCoordinator.toggleCurrentPage() else {
            settingsWindowPresenter?.show()
            return
        }
    }

    func validatePageURL() {
        switch pinCoordinator.page(from: pageURLText) {
        case let .success(page):
            activate(page: page, source: .typedURL)
            pageURLInputState.showPinned(page: page)
            pageURLInputPresenter.hide()
        case .failure:
            showValidationFailure("Use an HTTPS Notion page URL with a page ID.")
        }
    }

    func pin(page: NotionPageReference) {
        activate(page: page, source: .pagePicker)
    }

    func reloadSavedPin() {
        guard let activePage else { return }
        pinCoordinator.reloadPinnedPage(activePage)
    }

    func activate(page: NotionPageReference, source: PageActivationSource) {
        activate(page: page, source: source, restoration: nil)
    }

    func activate(
        page: NotionPageReference,
        source: PageActivationSource,
        restoration: DurablePageRestoration?
    ) {
        activate(page: page, source: source, persist: true, restoration: restoration)
    }

    private func activate(
        page: NotionPageReference,
        source: PageActivationSource,
        persist: Bool,
        restoration: DurablePageRestoration? = nil
    ) {
        pageSelectionGeneration &+= 1
        if persist {
            restorePinnedPageTask?.cancel()
            restorePinnedPageTask = nil
        }
        pinCoordinator.pin(page: page, restoration: restoration)
        activePage = page
        pendingPage = page
        lastActivationSource = source

        if persist {
            enqueuePersistence(of: page)
        }
    }

    func handleOpenURLs(_ urls: [URL]) {
        for (page, source) in pinCoordinator.externalPages(from: urls) {
            activate(page: page, source: .externalRoute(source))
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

    func refreshCaptureRecords() async {
        guard let captureRepository else { return }
        do {
            captureRecords = try await captureRepository.records()
                .sorted { $0.updatedAt > $1.updatedAt }
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

    private func handleGlobalShortcut() {
        guard pinCoordinator.stashOrRestoreCurrentPage() else {
            pageURLInputPresenter.presentAndFocus()
            return
        }
    }

    private func registerGlobalShortcut() {
        _ = applyGlobalShortcut(globalShortcut)
    }

    private func showValidationFailure(_ message: String) {
        pageURLInputState.showValidationFailure(message)
    }

    private func restorePinnedPage(
        _ page: NotionPageReference,
        restoration: DurablePageRestoration?,
        expectedGeneration: Int
    ) {
        guard expectedGeneration == pageSelectionGeneration, !Task.isCancelled else { return }
        activate(
            page: page,
            source: .restored,
            persist: false,
            restoration: restoration
        )
    }

    private func restorePinnedPageFromRepository() {
        let expectedGeneration = pageSelectionGeneration
        let pageRepository = pageRepository
        let logger = logger
        restorePinnedPageTask?.cancel()
        restorePinnedPageTask = Task { [weak self] in
            guard !Task.isCancelled, let pageRepository else { return }
            do {
                let workingSet = try await (pageRepository as? any PageWorkingSetPersisting)?
                    .workingSet()
                let storedPage = if let workingSet {
                    workingSet.activePage
                } else {
                    try await pageRepository.currentPinnedPage()
                }
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
                guard let storedPage else { return }
                guard let page = try? NotionPageReference(validating: storedPage.canonicalURL),
                      page.canonicalURL == storedPage.canonicalURL,
                      page.pageID == storedPage.pageID
                else {
                    logger.error("Pinned page restore skipped page_id=\(storedPage.pageID, privacy: .private) category=invalid-stored-value")
                    return
                }
                guard !Task.isCancelled else { return }
                self?.restorePinnedPage(
                    page,
                    restoration: workingSet?.restoration(for: page.pageID),
                    expectedGeneration: expectedGeneration
                )
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Pinned page restore failed category=repository-read")
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
            }
        }
    }

    private func enqueuePersistence(of page: NotionPageReference) {
        guard let pageRepository else { return }
        let previousTask = persistPinnedPageTask
        let logger = logger
        persistenceGeneration &+= 1
        persistPinnedPageTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                _ = try await pageRepository.replaceCurrent(with: page)
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Pinned page save failed page_id=\(page.pageID, privacy: .private) category=repository-write")
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
            }
        }
    }

    private func reportServiceIssue(_ issue: ServiceHealthIssue) {
        serviceHealth.report(issue)
    }

    private func resolveServiceIssue(_ issue: ServiceHealthIssue) {
        serviceHealth.resolve(issue)
    }

}

@MainActor
private final class PageURLInputSubmissionRelay {
    var handler: () -> Void = {}

    func submit() {
        handler()
    }
}
