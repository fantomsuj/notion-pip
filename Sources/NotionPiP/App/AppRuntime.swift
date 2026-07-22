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
    private let pageURLInputPresenter: any PageURLInputPresenting
    private let pageRepository: (any PinnedPagePersisting)?
    private let credentialVault: PersonalTokenCredentialVault
    private let legacyCacheCleaner: any LegacyNativePageCacheCleaning
    private let legacyCacheDirectory: URL
    private let notionClientFactory: (PersonalIntegrationToken) -> any NotionWorkspaceClient
    private weak var setupOptionsPresenter: (any SetupOptionsPresenting)?
    private var searchTask: Task<Void, Never>?
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
        pageURLInputPresenter: (any PageURLInputPresenting)? = nil,
        pageRepository: (any PinnedPagePersisting)? = nil,
        credentialVault: PersonalTokenCredentialVault = PersonalTokenCredentialVault(),
        legacyCacheCleaner: any LegacyNativePageCacheCleaning = NoOpLegacyNativePageCacheCleaner(),
        legacyCacheDirectory: URL = FileSystemLegacyNativePageCacheCleaner.defaultDirectoryURL,
        notionClientFactory: @escaping (PersonalIntegrationToken) -> any NotionWorkspaceClient = { token in
            NotionAPIClient(token: token)
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
        self.pageRepository = pageRepository
        self.credentialVault = credentialVault
        self.legacyCacheCleaner = legacyCacheCleaner
        self.legacyCacheDirectory = legacyCacheDirectory
        self.notionClientFactory = notionClientFactory
        submissionRelay.handler = { [weak self] in
            self?.validatePageURL()
        }
    }

    func start() {
        guard !started else {
            return
        }
        started = true

        do {
            try shortcutRegistrar.register { [weak self] in
                self?.handleGlobalShortcut()
            }
        } catch {
            logger.error("Global shortcut registration failed")
        }

        bootstrapTask = Task { [weak self] in
            await self?.bootstrapPersonalTokenConnection()
        }
        let expectedGeneration = pageSelectionGeneration
        let pageRepository = pageRepository
        let logger = logger
        restorePinnedPageTask = Task { [weak self] in
            guard !Task.isCancelled, let pageRepository else { return }
            do {
                guard let storedPage = try await pageRepository.currentPinnedPage() else { return }
                guard !Task.isCancelled else { return }
                guard let page = try? NotionPageReference(validating: storedPage.canonicalURL),
                      page.canonicalURL == storedPage.canonicalURL,
                      page.pageID == storedPage.pageID
                else {
                    logger.error("Pinned page restore skipped page_id=\(storedPage.pageID, privacy: .public) category=invalid-stored-value")
                    return
                }
                guard !Task.isCancelled else { return }
                self?.restorePinnedPage(page, expectedGeneration: expectedGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Pinned page restore failed category=repository-read")
            }
        }
    }

    func bind(setupOptionsPresenter: any SetupOptionsPresenting) {
        self.setupOptionsPresenter = setupOptionsPresenter
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
            setupOptionsPresenter?.show()
            return
        }
        setupOptionsPresenter?.hide()
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
        setupOptionsPresenter?.hide()
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
            connectionState = .disconnected
            searchResults = []
            searchError = nil
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

    private func handleGlobalShortcut() {
        guard pinCoordinator.stashOrRestoreCurrentPage() else {
            pageURLInputPresenter.presentAndFocus()
            return
        }
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

    private func enqueuePersistence(of page: NotionPageReference) {
        guard let pageRepository else { return }
        let previousTask = persistPinnedPageTask
        let logger = logger
        persistenceGeneration &+= 1
        persistPinnedPageTask = Task {
            await previousTask?.value
            do {
                _ = try await pageRepository.replaceCurrent(with: page)
            } catch {
                logger.error("Pinned page save failed page_id=\(page.pageID, privacy: .public) category=repository-write")
            }
        }
    }

    private static func connectionMessage(for error: NotionAPIClientError) -> String {
        switch error {
        case .unauthorized:
            "Notion did not accept this token."
        case .accessDenied:
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
        default:
            "Saved Notion access needs to be reconnected."
        }
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
