import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?
    @Published private(set) var lastActivationSource: PageActivationSource?
    @Published private(set) var quickCaptureDestination: QuickCaptureDestination?
    @Published private(set) var destinationSearchResults: [NotionDestinationSearchResult] = []
    @Published private(set) var destinationSearchError: String?
    @Published private(set) var isSearchingDestinations = false
    @Published private(set) var canLoadMoreDestinations = false
    @Published private(set) var isDestinationSearchCapped = false
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

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "shortcut")
    private let pinCoordinator: PinCoordinator
    private let shortcutRegistrar: any GlobalShortcutRegistering
    private let shortcutStore: GlobalShortcutStore
    private let pageURLInputPresenter: any PageURLInputPresenting
    private let pageRepository: (any PinnedPagePersisting)?
    private let destinationRepository: (any QuickCaptureDestinationPersisting)?
    private let captureRepository: CaptureRepository?
    private let deliveryScheduler: DeliveryScheduler?
    private let connectionController: NotionConnectionController
    private let destinationSearchDebounceDuration: Duration
    private weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private var connectionObservation: AnyCancellable?
    private var destinationSearchTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var restorePinnedPageTask: Task<Void, Never>?
    private var persistPinnedPageTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var pageSelectionGeneration = 0
    private var destinationSearchGeneration = 0
    private var activeDestinationSearchQuery: String?
    private var destinationSearchNextCursor: String?
    private var destinationSearchRequestedCursors: Set<String> = []
    private var destinationSearchReturnedCursors: Set<String> = []
    private var destinationSearchPageCount = 0
    private var destinationSearchDisplayedResultCount = 0
    private var started = false

    private static let destinationSearchMinimumQueryLength = 2
    private static let maximumDestinationSearchPages = 4
    private static let maximumDestinationSearchResults = 100

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
        self.destinationRepository = destinationRepository
        self.captureRepository = captureRepository
        self.deliveryScheduler = deliveryScheduler
        connectionController = NotionConnectionController(
            credentialVault: credentialVault,
            legacyCacheCleaner: legacyCacheCleaner,
            legacyCacheDirectory: legacyCacheDirectory,
            notionClientFactory: notionClientFactory,
            onReconnect: {
                await deliveryScheduler?.trigger(reconnected: true)
            }
        )
        self.destinationSearchDebounceDuration = destinationSearchDebounceDuration
        serviceHealth = initialServiceHealth
        globalShortcut = shortcutStore.load()
        connectionObservation = connectionController.objectWillChange.sink { [weak self] in
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
            await self?.loadQuickCaptureDestination()
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
        cancelDestinationSearch()
    }

    func searchNotionPages(query: String) async {
        await connectionController.searchPages(query: query)
    }

    func searchQuickCaptureDestinations(query: String) async {
        beginDestinationSearch(query: query, debounced: false)
        await destinationSearchTask?.value
    }

    func scheduleQuickCaptureDestinationSearch(query: String) {
        beginDestinationSearch(query: query, debounced: true)
    }

    func loadMoreQuickCaptureDestinations() async {
        guard let query = activeDestinationSearchQuery,
              let cursor = destinationSearchNextCursor,
              !isSearchingDestinations,
              !isDestinationSearchCapped
        else {
            return
        }

        guard destinationSearchRequestedCursors.insert(cursor).inserted else {
            stopDestinationSearchForInvalidContinuation()
            return
        }

        let connectionGeneration = connectionController.generation
        let searchGeneration = destinationSearchGeneration
        isSearchingDestinations = true
        destinationSearchTask = Task { [weak self] in
            await self?.loadDestinationSearchResults(
                query: query,
                startCursor: cursor,
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration,
                appendingResults: true
            )
        }
        await destinationSearchTask?.value
    }

    private func beginDestinationSearch(query: String, debounced: Bool) {
        destinationSearchTask?.cancel()
        destinationSearchTask = nil
        destinationSearchGeneration &+= 1
        resetDestinationSearchState()

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= Self.destinationSearchMinimumQueryLength else {
            return
        }

        let connectionGeneration = connectionController.generation
        let searchGeneration = destinationSearchGeneration
        activeDestinationSearchQuery = normalizedQuery
        isSearchingDestinations = true
        destinationSearchTask = Task { [weak self] in
            guard let self else { return }
            if debounced {
                do {
                    try await Task.sleep(for: self.destinationSearchDebounceDuration)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self.loadDestinationSearchResults(
                query: normalizedQuery,
                startCursor: nil,
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration,
                appendingResults: false
            )
        }
    }

    func selectQuickCaptureDestination(
        _ destination: QuickCaptureDestination
    ) async {
        guard let destinationRepository else {
            destinationSearchError = "Quick Capture settings are unavailable."
            return
        }
        do {
            try await destinationRepository.replaceDefault(with: destination)
            quickCaptureDestination = destination
            destinationSearchError = nil
        } catch {
            destinationSearchError = "Could not save the Quick Capture destination."
        }
    }

    func clearQuickCaptureDestination() async {
        guard let destinationRepository else {
            destinationSearchError = "Quick Capture settings are unavailable."
            return
        }
        do {
            try await destinationRepository.clearDefault()
            quickCaptureDestination = nil
            destinationSearchError = nil
        } catch {
            destinationSearchError = "Could not clear the Quick Capture destination."
        }
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

    private func loadDestinationSearchResults(
        query: String,
        startCursor: String?,
        connectionGeneration: Int,
        searchGeneration: Int,
        appendingResults: Bool
    ) async {
        defer {
            if isCurrentDestinationSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) {
                isSearchingDestinations = false
            }
        }
        do {
            guard isCurrentDestinationSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return }
            guard isNotionConnected else {
                destinationSearchResults = []
                destinationSearchError = "Reconnect to Notion to search destinations."
                canLoadMoreDestinations = false
                return
            }
            guard let lease = try connectionController.workspaceClientLease() else {
                destinationSearchResults = []
                destinationSearchError = "Connect a Notion personal access token first."
                canLoadMoreDestinations = false
                return
            }
            guard lease.generation == connectionGeneration else { return }
            destinationSearchError = nil
            let page = try await lease.client.searchDestinations(
                query: query,
                startCursor: startCursor
            )
            guard isCurrentDestinationSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return }
            applyDestinationSearchPage(page, appendingResults: appendingResults)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentDestinationSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return }
            if !appendingResults {
                destinationSearchResults = []
            }
            destinationSearchError = "Could not search Notion destinations."
            destinationSearchNextCursor = nil
            canLoadMoreDestinations = false
        }
    }

    private func applyDestinationSearchPage(
        _ page: NotionDestinationSearchPage,
        appendingResults: Bool
    ) {
        let results: [NotionDestinationSearchResult]
        if appendingResults {
            var knownDestinations = Set(destinationSearchResults.map(destinationIdentifier))
            results = destinationSearchResults + page.results.filter {
                knownDestinations.insert(destinationIdentifier($0)).inserted
            }
        } else {
            var knownDestinations: Set<String> = []
            results = page.results.filter {
                knownDestinations.insert(destinationIdentifier($0)).inserted
            }
        }
        destinationSearchResults = Array(results.prefix(Self.maximumDestinationSearchResults))
        destinationSearchPageCount += 1
        destinationSearchDisplayedResultCount = destinationSearchResults.count

        guard let nextCursor = page.nextCursor else {
            destinationSearchNextCursor = nil
            canLoadMoreDestinations = false
            return
        }

        if destinationSearchReturnedCursors.contains(nextCursor) {
            stopDestinationSearchForInvalidContinuation()
            return
        }
        destinationSearchReturnedCursors.insert(nextCursor)

        if destinationSearchPageCount >= Self.maximumDestinationSearchPages
            || destinationSearchDisplayedResultCount >= Self.maximumDestinationSearchResults {
            isDestinationSearchCapped = true
            destinationSearchNextCursor = nil
            canLoadMoreDestinations = false
            return
        }

        destinationSearchNextCursor = nextCursor
        canLoadMoreDestinations = true
    }

    private func destinationIdentifier(_ result: NotionDestinationSearchResult) -> String {
        "\(result.destination.rawKind):\(result.destination.identifier)"
    }

    private func stopDestinationSearchForInvalidContinuation() {
        destinationSearchNextCursor = nil
        canLoadMoreDestinations = false
        destinationSearchError = "Could not search Notion destinations."
    }

    private func cancelDestinationSearch() {
        destinationSearchGeneration &+= 1
        destinationSearchTask?.cancel()
        destinationSearchTask = nil
        resetDestinationSearchState()
    }

    private func resetDestinationSearchState() {
        activeDestinationSearchQuery = nil
        destinationSearchNextCursor = nil
        destinationSearchRequestedCursors = []
        destinationSearchReturnedCursors = []
        destinationSearchPageCount = 0
        destinationSearchDisplayedResultCount = 0
        destinationSearchResults = []
        destinationSearchError = nil
        isSearchingDestinations = false
        canLoadMoreDestinations = false
        isDestinationSearchCapped = false
    }

    private func isCurrentDestinationSearch(
        connectionGeneration: Int,
        searchGeneration: Int
    ) -> Bool {
        connectionController.isCurrent(generation: connectionGeneration)
            && searchGeneration == destinationSearchGeneration
    }

    private func loadQuickCaptureDestination() async {
        guard let destinationRepository else { return }
        do {
            quickCaptureDestination = try await destinationRepository.defaultDestination()
        } catch {
            destinationSearchError = "Could not load the Quick Capture destination."
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
