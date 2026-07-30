import Combine
import Foundation

@MainActor
final class QuickCaptureDestinationController: ObservableObject {
    @Published private(set) var destination: QuickCaptureDestination?
    @Published private(set) var searchResults: [NotionDestinationSearchResult] = []
    @Published private(set) var searchError: String?
    @Published private(set) var isSearching = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var isSearchCapped = false

    private let connectionController: NotionConnectionController
    private let repository: (any QuickCaptureDestinationPersisting)?
    private let searchDebounceDuration: Duration
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var activeSearchQuery: String?
    private var nextCursor: String?
    private var requestedCursors: Set<String> = []
    private var returnedCursors: Set<String> = []
    private var pageCount = 0
    private var displayedResultCount = 0

    private static let minimumQueryLength = 2
    private static let maximumSearchPages = 4
    private static let maximumSearchResults = 100

    init(
        connectionController: NotionConnectionController,
        repository: (any QuickCaptureDestinationPersisting)? = nil,
        searchDebounceDuration: Duration = .milliseconds(300)
    ) {
        self.connectionController = connectionController
        self.repository = repository
        self.searchDebounceDuration = searchDebounceDuration
    }

    func search(query: String) async {
        beginSearch(query: query, debounced: false)
        await searchTask?.value
    }

    func scheduleSearch(query: String) {
        beginSearch(query: query, debounced: true)
    }

    func loadMore() async {
        guard let query = activeSearchQuery,
              let cursor = nextCursor,
              !isSearching,
              !isSearchCapped
        else {
            return
        }

        guard requestedCursors.insert(cursor).inserted else {
            stopForInvalidContinuation()
            return
        }

        let connectionGeneration = connectionController.generation
        let expectedSearchGeneration = searchGeneration
        isSearching = true
        searchTask = Task { [weak self] in
            await self?.loadSearchResults(
                query: query,
                startCursor: cursor,
                connectionGeneration: connectionGeneration,
                searchGeneration: expectedSearchGeneration,
                appendingResults: true
            )
        }
        await searchTask?.value
    }

    func select(_ destination: QuickCaptureDestination) async {
        guard let repository else {
            searchError = "Quick Capture settings are unavailable."
            return
        }
        do {
            try await repository.replaceDefault(with: destination)
            self.destination = destination
            searchError = nil
        } catch {
            searchError = "Could not save the Quick Capture destination."
        }
    }

    func clear() async {
        guard let repository else {
            searchError = "Quick Capture settings are unavailable."
            return
        }
        do {
            try await repository.clearDefault()
            destination = nil
            searchError = nil
        } catch {
            searchError = "Could not clear the Quick Capture destination."
        }
    }

    func loadSavedDestination() async {
        guard let repository else { return }
        do {
            destination = try await repository.defaultDestination()
        } catch {
            searchError = "Could not load the Quick Capture destination."
        }
    }

    func resetAfterDisconnect() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        resetSearchState()
    }
}

private extension QuickCaptureDestinationController {
    private func beginSearch(query: String, debounced: Bool) {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        resetSearchState()

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= Self.minimumQueryLength else {
            return
        }

        let connectionGeneration = connectionController.generation
        let expectedSearchGeneration = searchGeneration
        activeSearchQuery = normalizedQuery
        isSearching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            if debounced {
                do {
                    try await Task.sleep(for: searchDebounceDuration)
                } catch {
                    return
                }
                guard isCurrentSearch(
                    connectionGeneration: connectionGeneration,
                    searchGeneration: expectedSearchGeneration
                ) else { return }
            }
            guard !Task.isCancelled else { return }
            await loadSearchResults(
                query: normalizedQuery,
                startCursor: nil,
                connectionGeneration: connectionGeneration,
                searchGeneration: expectedSearchGeneration,
                appendingResults: false
            )
        }
    }

    private func loadSearchResults(
        query: String,
        startCursor: String?,
        connectionGeneration: Int,
        searchGeneration: Int,
        appendingResults: Bool
    ) async {
        defer {
            if isCurrentSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) {
                isSearching = false
            }
        }

        var lease: NotionWorkspaceClientLease?
        do {
            guard isCurrentSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return }
            guard connectionController.isConnected else {
                searchResults = []
                searchError = "Reconnect to Notion to search destinations."
                canLoadMore = false
                return
            }
            guard let currentLease = try currentWorkspaceClientLease(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return }
            lease = currentLease
            guard connectionController.isCurrent(currentLease),
                  currentLease.generation == connectionGeneration
            else {
                return
            }
            searchError = nil
            guard let page = try await searchPage(
                query: query,
                startCursor: startCursor,
                lease: currentLease,
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return }
            apply(page, appendingResults: appendingResults)
        } catch is CancellationError {
            return
        } catch {
            publishSearchFailure(
                lease: lease,
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration,
                appendingResults: appendingResults
            )
        }
    }

    private func currentWorkspaceClientLease(
        connectionGeneration: Int,
        searchGeneration: Int
    ) throws -> NotionWorkspaceClientLease? {
        guard let lease = try connectionController.workspaceClientLease() else {
            guard isCurrentSearch(
                connectionGeneration: connectionGeneration,
                searchGeneration: searchGeneration
            ) else { return nil }
            searchResults = []
            searchError = "Connect a Notion personal access token first."
            canLoadMore = false
            return nil
        }
        return lease
    }

    private func searchPage(
        query: String,
        startCursor: String?,
        lease: NotionWorkspaceClientLease,
        connectionGeneration: Int,
        searchGeneration: Int
    ) async throws -> NotionDestinationSearchPage? {
        let page = try await lease.client.searchDestinations(
            query: query,
            startCursor: startCursor
        )
        guard connectionController.isCurrent(lease),
              isCurrentSearch(
                  connectionGeneration: connectionGeneration,
                  searchGeneration: searchGeneration
              )
        else {
            return nil
        }
        return page
    }

    private func publishSearchFailure(
        lease: NotionWorkspaceClientLease?,
        connectionGeneration: Int,
        searchGeneration: Int,
        appendingResults: Bool
    ) {
        guard isCurrentSearch(
            connectionGeneration: connectionGeneration,
            searchGeneration: searchGeneration
        ) else { return }
        if let lease {
            guard connectionController.isCurrent(lease) else { return }
        }
        if !appendingResults {
            searchResults = []
        }
        searchError = "Could not search Notion destinations."
        nextCursor = nil
        canLoadMore = false
    }

    private func apply(
        _ page: NotionDestinationSearchPage,
        appendingResults: Bool
    ) {
        let results: [NotionDestinationSearchResult]
        if appendingResults {
            var knownDestinations = Set(searchResults.map(destinationIdentifier))
            results = searchResults + page.results.filter {
                knownDestinations.insert(destinationIdentifier($0)).inserted
            }
        } else {
            var knownDestinations: Set<String> = []
            results = page.results.filter {
                knownDestinations.insert(destinationIdentifier($0)).inserted
            }
        }
        searchResults = Array(results.prefix(Self.maximumSearchResults))
        pageCount += 1
        displayedResultCount = searchResults.count

        guard let nextCursor = page.nextCursor else {
            self.nextCursor = nil
            canLoadMore = false
            return
        }

        if returnedCursors.contains(nextCursor) {
            stopForInvalidContinuation()
            return
        }
        returnedCursors.insert(nextCursor)

        if pageCount >= Self.maximumSearchPages
            || displayedResultCount >= Self.maximumSearchResults {
            isSearchCapped = true
            self.nextCursor = nil
            canLoadMore = false
            return
        }

        self.nextCursor = nextCursor
        canLoadMore = true
    }

    private func destinationIdentifier(_ result: NotionDestinationSearchResult) -> String {
        "\(result.destination.rawKind):\(result.destination.identifier)"
    }

    private func stopForInvalidContinuation() {
        nextCursor = nil
        canLoadMore = false
        searchError = "Could not search Notion destinations."
    }

    private func resetSearchState() {
        activeSearchQuery = nil
        nextCursor = nil
        requestedCursors = []
        returnedCursors = []
        pageCount = 0
        displayedResultCount = 0
        searchResults = []
        searchError = nil
        isSearching = false
        canLoadMore = false
        isSearchCapped = false
    }

    private func isCurrentSearch(
        connectionGeneration: Int,
        searchGeneration: Int
    ) -> Bool {
        connectionController.isCurrent(generation: connectionGeneration)
            && searchGeneration == self.searchGeneration
    }
}
