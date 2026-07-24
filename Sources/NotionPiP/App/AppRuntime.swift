import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?
    @Published private(set) var lastActivationSource: PageActivationSource?
    @Published private(set) var connectionState: PersonalTokenConnectionState = .disconnected
    @Published private(set) var searchResults: [NotionPageSearchResult] = []
    @Published private(set) var searchError: String?
    @Published private(set) var quickCaptureDestination: QuickCaptureDestination?
    @Published private(set) var destinationSearchResults: [NotionDestinationSearchResult] = []
    @Published private(set) var destinationSearchError: String?
    @Published private(set) var isSearchingDestinations = false
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

    var isNotionConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
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
    private let credentialVault: PersonalTokenCredentialVault
    private let legacyCacheCleaner: any LegacyNativePageCacheCleaning
    private let legacyCacheDirectory: URL
    private let notionClientFactory: (PersonalIntegrationToken) -> any NotionWorkspaceClient
    private weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private var searchTask: Task<Void, Never>?
    private var destinationSearchTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var restorePinnedPageTask: Task<Void, Never>?
    private var persistPinnedPageTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var pageSelectionGeneration = 0
    private var connectionGeneration = 0
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
        self.credentialVault = credentialVault
        self.legacyCacheCleaner = legacyCacheCleaner
        self.legacyCacheDirectory = legacyCacheDirectory
        self.notionClientFactory = notionClientFactory
        serviceHealth = initialServiceHealth
        globalShortcut = shortcutStore.load()
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

    func activate(page: NotionPageReference, source: PageActivationSource) {
        activate(page: page, source: source, persist: true)
    }

    private func activate(
        page: NotionPageReference,
        source: PageActivationSource,
        persist: Bool
    ) {
        pageSelectionGeneration &+= 1
        if persist {
            restorePinnedPageTask?.cancel()
            restorePinnedPageTask = nil
        }
        pinCoordinator.pin(page: page)
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
        connectionGeneration &+= 1
        let generation = connectionGeneration

        do {
            let token = try PersonalIntegrationToken(validating: rawValue)
            connectionState = .connecting
            let connection = try await notionClientFactory(token).validateConnection()
            guard isCurrentConnectionAttempt(generation) else { return }
            try credentialVault.save(token)
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .connected(workspaceName: connection.workspaceName)
            await deliveryScheduler?.trigger(reconnected: true)
        } catch let error as PersonalIntegrationTokenError {
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .failed(error == .missing ? "Enter your Notion personal access token." : "Use a Notion personal access token that starts with ntn_.")
        } catch let error as NotionAPIClientError {
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .failed(Self.connectionMessage(for: error))
        } catch {
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .failed("Could not connect to Notion. Check your network and try again.")
        }
    }

    func bootstrapPersonalTokenConnection() async {
        let generation = connectionGeneration

        do {
            guard let token = try credentialVault.load() else {
                guard isCurrentConnectionAttempt(generation) else { return }
                connectionState = .disconnected
                return
            }
            connectionState = .connecting
            let connection = try await notionClientFactory(token).validateConnection()
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .connected(workspaceName: connection.workspaceName)
            await deliveryScheduler?.trigger(reconnected: true)
        } catch let error as NotionAPIClientError {
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .failed(Self.reconnectMessage(for: error))
        } catch {
            guard isCurrentConnectionAttempt(generation) else { return }
            connectionState = .failed("Saved Notion access needs to be reconnected.")
        }
    }

    func disconnectPersonalToken() {
        do {
            try credentialVault.disconnect()
            connectionGeneration &+= 1
            bootstrapTask?.cancel()
            bootstrapTask = nil
            searchTask?.cancel()
            searchTask = nil
            destinationSearchTask?.cancel()
            destinationSearchTask = nil
            connectionState = .disconnected
            searchResults = []
            searchError = nil
            destinationSearchResults = []
            destinationSearchError = nil
        } catch {
            connectionState = .failed("Could not remove the saved token.")
            return
        }

        do {
            try legacyCacheCleaner.removeLegacyCache(at: legacyCacheDirectory)
        } catch {
            logger.error("Legacy native preview cache cleanup failed; personal token was removed category=legacy-preview-cache-cleanup")
        }
    }

    func searchNotionPages(query: String) async {
        searchTask?.cancel()
        let generation = connectionGeneration
        searchTask = Task { [weak self] in
            await self?.loadNotionSearchResults(query: query, connectionGeneration: generation)
        }
        await searchTask?.value
    }

    func searchQuickCaptureDestinations(query: String) async {
        destinationSearchTask?.cancel()
        let generation = connectionGeneration
        isSearchingDestinations = true
        destinationSearchTask = Task { [weak self] in
            await self?.loadDestinationSearchResults(
                query: query,
                connectionGeneration: generation
            )
        }
        await destinationSearchTask?.value
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
        guard isNotionConnected else { return false }
        return (try? credentialVault.load()) != nil
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

    private func loadNotionSearchResults(query: String, connectionGeneration: Int) async {
        do {
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            guard isNotionConnected else {
                searchResults = []
                searchError = "Reconnect to Notion to search your workspace."
                return
            }
            guard let token = try credentialVault.load() else {
                guard isCurrentConnectionAttempt(connectionGeneration) else { return }
                searchResults = []
                searchError = "Connect a Notion personal access token first."
                return
            }
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            searchError = nil
            let results = try await notionClientFactory(token).searchPages(query: query)
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            searchResults = results
        } catch {
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            searchResults = []
            searchError = "Could not search Notion. Check the token, permissions, and network."
        }
    }

    private func loadDestinationSearchResults(
        query: String,
        connectionGeneration: Int
    ) async {
        defer {
            if isCurrentConnectionAttempt(connectionGeneration) {
                isSearchingDestinations = false
            }
        }
        do {
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            guard isNotionConnected else {
                destinationSearchResults = []
                destinationSearchError = "Reconnect to Notion to search destinations."
                return
            }
            guard let token = try credentialVault.load() else {
                destinationSearchResults = []
                destinationSearchError = "Connect a Notion personal access token first."
                return
            }
            destinationSearchError = nil
            let results = try await notionClientFactory(token)
                .searchDestinations(query: query)
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            destinationSearchResults = results
        } catch {
            guard isCurrentConnectionAttempt(connectionGeneration) else { return }
            destinationSearchResults = []
            destinationSearchError = "Could not search Notion destinations."
        }
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

    private func isCurrentConnectionAttempt(_ generation: Int) -> Bool {
        generation == connectionGeneration && !Task.isCancelled
    }

    private func restorePinnedPage(
        _ page: NotionPageReference,
        expectedGeneration: Int
    ) {
        guard expectedGeneration == pageSelectionGeneration, !Task.isCancelled else { return }
        activate(page: page, source: .restored, persist: false)
    }

    private func restorePinnedPageFromRepository() {
        let expectedGeneration = pageSelectionGeneration
        let pageRepository = pageRepository
        let logger = logger
        restorePinnedPageTask?.cancel()
        restorePinnedPageTask = Task { [weak self] in
            guard !Task.isCancelled, let pageRepository else { return }
            do {
                let storedPage = try await pageRepository.currentPinnedPage()
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
                self?.restorePinnedPage(page, expectedGeneration: expectedGeneration)
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

    private static func connectionMessage(for error: NotionAPIClientError) -> String {
        switch error {
        case .unauthorized:
            "Notion did not accept this token."
        case .accessDenied:
            "This token does not have the Notion API capability."
        case .apiError(let details) where details.statusCode == 401:
            "Notion did not accept this token."
        case .apiError(let details) where details.statusCode == 403:
            "This token does not have the Notion API capability."
        default:
            "Could not connect to Notion. Check your network and try again."
        }
    }

    private static func reconnectMessage(for error: NotionAPIClientError) -> String {
        switch error {
        case .unauthorized:
            "Notion did not accept this token. Reconnect to continue."
        case .accessDenied:
            "This token does not have the Notion API capability. Reconnect to continue."
        case .apiError(let details) where details.statusCode == 401:
            "Notion did not accept this token. Reconnect to continue."
        case .apiError(let details) where details.statusCode == 403:
            "This token does not have the Notion API capability. Reconnect to continue."
        default:
            "Saved Notion access needs to be reconnected."
        }
    }
}

struct ServiceHealthState: Equatable, Sendable {
    static let healthy = ServiceHealthState()

    private(set) var issues: [ServiceHealthIssue]

    var isHealthy: Bool {
        issues.isEmpty
    }

    init(issues: Set<ServiceHealthIssue> = []) {
        self.issues = issues.sorted()
    }

    mutating func report(_ issue: ServiceHealthIssue) {
        guard !issues.contains(issue) else { return }
        issues.append(issue)
        issues.sort()
    }

    mutating func resolve(_ issue: ServiceHealthIssue) {
        issues.removeAll { $0 == issue }
    }
}

enum ServiceHealthIssue: String, Comparable, Identifiable, Sendable {
    case persistentStoreUnavailable
    case pinnedPagePersistenceUnavailable
    case globalShortcutUnavailable

    var id: String {
        rawValue
    }

    static func < (lhs: ServiceHealthIssue, rhs: ServiceHealthIssue) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PageActivationSource: Equatable, Sendable {
    case restored
    case typedURL
    case clipboard
    case externalRoute(ExternalURLSource)
    case notionSearch
    case notionWebSession
    case pagePicker
}

enum PersonalTokenConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(workspaceName: String)
    case failed(String)
}

@MainActor
private final class PageURLInputSubmissionRelay {
    var handler: () -> Void = {}

    func submit() {
        handler()
    }
}
