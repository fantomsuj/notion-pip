import Foundation
import XCTest
@testable import NotionPiP

let firstPageID = "0123456789abcdef0123456789abcdef"
let secondPageID = "fedcba9876543210fedcba9876543210"

@MainActor
func makeRuntime(
    panel: RuntimePanelCoordinator,
    pasteboard: any PasteboardReading = RuntimePasteboard(value: nil),
    shortcutRegistrar: any GlobalShortcutRegistering = RuntimeShortcutRegistrar(),
    pageURLInputPresenter: RuntimePageURLInputPresenter = RuntimePageURLInputPresenter(),
    pageRepository: (any PageWorkingSetPersisting)? = nil,
    client: any NotionWorkspaceClient = RuntimeNotionClient(),
    destinationSearchDebounceDuration: Duration = .milliseconds(300),
    shortcutHoldDuration: Duration = .milliseconds(300),
    holdToPeekPreferenceStore: HoldToPeekPreferenceStore? = nil,
    peekFocusRestorer: any PeekFocusRestoring = PeekFocusRestorer(),
    initialServiceHealth: ServiceHealthState = .healthy,
    menuBarIconPreferenceStore: MenuBarIconPreferenceStore? = nil,
    automaticSettingsPresentationAllowed: @escaping @MainActor () -> Bool = { true }
) -> AppRuntime {
    let store = RuntimeSecretStore()
    let vault = PersonalTokenCredentialVault(store: store)
    try! vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
    let preferenceStore = menuBarIconPreferenceStore ?? MenuBarIconPreferenceStore(
        defaults: UserDefaults(
            suiteName: "AppRuntimeTests.\(UUID().uuidString)"
        )!
    )
    let holdPreferenceStore = holdToPeekPreferenceStore ?? HoldToPeekPreferenceStore(
        defaults: UserDefaults(
            suiteName: "AppRuntimeHoldPreferenceTests.\(UUID().uuidString)"
        )!
    )
    return AppRuntime(
        panelCoordinator: panel,
        pasteboard: pasteboard,
        shortcutRegistrar: shortcutRegistrar,
        menuBarIconPreferenceStore: preferenceStore,
        holdToPeekPreferenceStore: holdPreferenceStore,
        peekFocusRestorer: peekFocusRestorer,
        pageURLInputPresenter: pageURLInputPresenter,
        pageRepository: pageRepository,
        credentialVault: vault,
        notionClientFactory: { _ in client },
        destinationSearchDebounceDuration: destinationSearchDebounceDuration,
        shortcutHoldDuration: shortcutHoldDuration,
        initialServiceHealth: initialServiceHealth,
        automaticSettingsPresentationAllowed: automaticSettingsPresentationAllowed
    )
}

func makePage(id: String, title: String) throws -> NotionPageReference {
    try NotionPageReference(
        validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
    )
}

func makeStoredPage(id: String, title: String) throws -> StoredPageSnapshot {
    let page = try makePage(id: id, title: title)
    return StoredPageSnapshot(
        pageID: page.pageID,
        canonicalURL: page.canonicalURL,
        displayTitle: page.displayTitle,
        timestamp: .distantPast
    )
}

@MainActor
func waitUntilRuntimeCondition(
    _ condition: @escaping @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0 ..< 1_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Condition was not met", file: file, line: line)
}

@MainActor
final class RuntimePanelCoordinator: PiPPanelCoordinating {
    private(set) var currentPage: NotionPageReference?
    private(set) var shownPages: [NotionPageReference] = []
    private(set) var reloadedPages: [NotionPageReference] = []
    private(set) var replacedPages: [NotionPageReference] = []
    private(set) var isVisible = false
    private(set) var isStashed = false
    private(set) var isExpanded = false
    private(set) var globalShortcutActionCount = 0

    var presentationState: PiPPresentationState {
        guard currentPage != nil else { return .unavailable }
        return isVisible ? .visible : .stashed
    }

    func show(page: NotionPageReference) {
        currentPage = page
        shownPages.append(page)
        isVisible = true
        isStashed = false
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        currentPage = page
        reloadedPages.append(page)
        isVisible = true
        isStashed = false
    }

    func replace(page: NotionPageReference) {
        currentPage = page
        replacedPages.append(page)
        isVisible = true
        isStashed = false
    }

    func showCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        isVisible = true
        isStashed = false
        return true
    }

    func hide() {
        isVisible = false
        isStashed = false
    }

    func simulateStashedState() {
        isVisible = false
        isStashed = currentPage != nil
    }

    func simulateExpandedState() {
        isExpanded = currentPage != nil && isVisible
    }

    func performGlobalShortcutAction() -> Bool {
        globalShortcutActionCount += 1
        guard currentPage != nil else { return false }
        if isVisible, isExpanded {
            isExpanded = false
            return true
        }
        return stashOrRestoreCurrentPage()
    }

    func stashOrRestoreCurrentPage() -> Bool {
        guard currentPage != nil else { return false }
        if isVisible {
            isVisible = false
            isStashed = true
        } else {
            _ = showCurrentPage()
        }
        return true
    }

    func loseCurrentPage() {
        currentPage = nil
        isVisible = false
        isStashed = false
        isExpanded = false
    }
}

@MainActor
final class RuntimeSettingsWindowPresenter: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}

final class RuntimePasteboard: PasteboardReading {
    let value: String?
    private(set) var readCount = 0

    init(value: String?) {
        self.value = value
    }

    func readString() -> String? {
        readCount += 1
        return value
    }
}

@MainActor
final class RuntimeShortcutRegistrar: GlobalShortcutRegistering {
    var handler: (@MainActor () -> Void)?
    var eventHandler: (@MainActor (GlobalShortcutEvent) -> Void)?
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func register(
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor () -> Void
    ) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RuntimeShortcutRegistrationError.failed
        }
        self.handler = handler
    }

    func register(
        shortcut: GlobalShortcut,
        eventHandler: @escaping @MainActor (GlobalShortcutEvent) -> Void
    ) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RuntimeShortcutRegistrationError.failed
        }
        self.eventHandler = eventHandler
        handler = {
            eventHandler(.pressed)
            eventHandler(.released)
        }
    }

    func revalidate() throws {}
    func unregister() {}

    private enum RuntimeShortcutRegistrationError: Error {
        case failed
    }
}

@MainActor
final class RuntimePageURLInputPresenter: PageURLInputPresenting {
    private(set) var presentAndFocusCount = 0

    func presentAndFocus() {
        presentAndFocusCount += 1
    }

    func hide() {}
}

final class RuntimeSecretStore: SecretStoring {
    var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

enum RuntimeRepositoryError: Error {
    case saveFailed
    case restoreFailed
}

enum RuntimeTestWaitError: Error {
    case timedOut(String)
}

actor RuntimePinnedPageRepository: PageWorkingSetPersisting {
    private let delaySaves: Bool
    private let failingPageIDs: Set<String>
    private let immediateStoredPage: StoredPageSnapshot?
    private var restoreRequests = 0
    private var restoreReturned = false
    private var restoreContinuation: CheckedContinuation<StoredPageSnapshot?, any Error>?
    private var pagesSaved: [NotionPageReference] = []
    private var failedSaves = 0
    private var saveContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(
        delaySaves: Bool = false,
        failingPageIDs: Set<String> = [],
        immediateStoredPage: StoredPageSnapshot? = nil
    ) {
        self.delaySaves = delaySaves
        self.failingPageIDs = failingPageIDs
        self.immediateStoredPage = immediateStoredPage
    }

    func activePageSnapshot() async throws -> StoredPageSnapshot? {
        restoreRequests += 1
        if let immediateStoredPage {
            restoreReturned = true
            return immediateStoredPage
        }
        let page = try await withCheckedThrowingContinuation { continuation in
            restoreContinuation = continuation
        }
        restoreReturned = true
        return page
    }

    func workingSet() async throws -> PageWorkingSetSnapshot {
        PageWorkingSetSnapshot(
            activePage: try await activePageSnapshot(),
            pinnedPages: [],
            recentPages: [],
            restorations: []
        )
    }

    func recordVisit(_ page: NotionPageReference) async throws -> StoredPageSnapshot {
        pagesSaved.append(page)
        if delaySaves {
            await withCheckedContinuation { continuation in
                saveContinuations[page.pageID] = continuation
            }
        }
        if failingPageIDs.contains(page.pageID) {
            failedSaves += 1
            throw RuntimeRepositoryError.saveFailed
        }
        return StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: page.displayTitle,
            timestamp: .distantPast
        )
    }

    func setPinned(
        _ isPinned: Bool,
        page: NotionPageReference
    ) async throws -> StoredPageSnapshot {
        try await recordVisit(page)
    }

    func saveRestoration(
        _ restoration: DurablePageRestoration
    ) -> DurablePageRestoration {
        restoration
    }

    func waitUntilRestoreRequested(count: Int = 1) async throws {
        try await waitUntil(
            { restoreRequests >= count },
            operation: "restore request \(count)"
        )
    }

    func finishRestore(with page: StoredPageSnapshot?) {
        restoreContinuation?.resume(returning: page)
        restoreContinuation = nil
    }

    func finishRestore(throwing error: any Error) {
        restoreContinuation?.resume(throwing: error)
        restoreContinuation = nil
    }

    func waitUntilRestoreReturned() async throws {
        try await waitUntil({ restoreReturned }, operation: "restore return")
    }

    func restoreRequestCount() -> Int {
        restoreRequests
    }

    func waitUntilSaveCount(_ count: Int) async throws {
        try await waitUntil({ pagesSaved.count >= count }, operation: "save count \(count)")
    }

    func waitUntilFailedSaveCount(_ count: Int) async throws {
        try await waitUntil({ failedSaves >= count }, operation: "failed save count \(count)")
    }

    func savedPages() -> [NotionPageReference] {
        pagesSaved
    }

    func savedPageIDs() -> [String] {
        pagesSaved.map(\.pageID)
    }

    func finishSave(pageID: String) {
        saveContinuations.removeValue(forKey: pageID)?.resume()
    }

    private func waitUntil(
        _ condition: () -> Bool,
        operation: String
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition() {
            guard clock.now < deadline else {
                throw RuntimeTestWaitError.timedOut(operation)
            }
            await Task.yield()
        }
    }
}

actor RuntimeNotionClient: NotionWorkspaceClient {
    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        []
    }
}
