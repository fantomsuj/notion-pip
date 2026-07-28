import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class QuickCaptureDestinationControllerTests: XCTestCase {
    func testSearchRejectsShortOrWhitespaceOnlyQueriesAndClearsResults() async throws {
        let client = DestinationControllerSearchClient(pages: [
            destinationPage(ids: ["one"], nextCursor: nil),
        ])
        let (_, controller) = try await makeController(client: client)

        await controller.search(query: "notes")
        await controller.search(query: " a ")
        await controller.search(query: "   ")

        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertNil(controller.searchError)
        XCTAssertFalse(controller.canLoadMore)
        XCTAssertFalse(controller.isSearching)
        let requests = await client.requests()
        XCTAssertEqual(requests, [
            DestinationControllerSearchRequest(query: "notes", startCursor: nil),
        ])
    }

    func testSearchDebouncesAutomaticQueriesAndImmediateSearchBypassesDelay() async throws {
        let client = DestinationControllerSearchClient(pages: [
            destinationPage(ids: ["immediate"], nextCursor: nil),
        ])
        let (_, controller) = try await makeController(
            client: client,
            debounceDuration: .seconds(60)
        )

        controller.scheduleSearch(query: "delayed")
        await Task.yield()
        let delayedRequests = await client.requests()
        XCTAssertTrue(delayedRequests.isEmpty)

        await controller.search(query: "immediate")

        let requests = await client.requests()
        XCTAssertEqual(requests, [
            DestinationControllerSearchRequest(query: "immediate", startCursor: nil),
        ])
        XCTAssertEqual(controller.searchResults.map(\.destination.title), ["immediate"])
    }

    func testLoadMoreAppendsUniqueResultsUsingPreviousCursor() async throws {
        let client = DestinationControllerSearchClient(pages: [
            destinationPage(ids: ["one", "two"], nextCursor: "cursor-2"),
            destinationPage(ids: ["two", "three"], nextCursor: nil),
        ])
        let (_, controller) = try await makeController(client: client)

        await controller.search(query: "notes")
        await controller.loadMore()

        XCTAssertEqual(controller.searchResults.map(\.destination.title), ["one", "two", "three"])
        let requests = await client.requests()
        XCTAssertEqual(requests, [
            DestinationControllerSearchRequest(query: "notes", startCursor: nil),
            DestinationControllerSearchRequest(query: "notes", startCursor: "cursor-2"),
        ])
        XCTAssertFalse(controller.canLoadMore)
    }

    func testSearchIgnoresOlderQueryCompletion() async throws {
        let client = DelayedDestinationControllerClient()
        let (_, controller) = try await makeController(client: client)

        let firstSearch = Task { await controller.search(query: "first") }
        await client.waitUntilStarted(query: "first")
        let secondSearch = Task { await controller.search(query: "second") }
        await client.waitUntilStarted(query: "second")
        await client.finish(
            query: "second",
            with: destinationPage(ids: ["current"], nextCursor: nil)
        )
        await secondSearch.value
        await client.finish(
            query: "first",
            with: destinationPage(ids: ["stale"], nextCursor: nil)
        )
        await firstSearch.value

        XCTAssertEqual(controller.searchResults.map(\.destination.title), ["current"])
        XCTAssertNil(controller.searchError)
    }

    func testSearchStopsOnRepeatedCursorWithoutDiscardingResults() async throws {
        let client = DestinationControllerSearchClient(pages: [
            destinationPage(ids: ["one"], nextCursor: "cursor-2"),
            destinationPage(ids: ["two"], nextCursor: "cursor-2"),
        ])
        let (_, controller) = try await makeController(client: client)

        await controller.search(query: "notes")
        await controller.loadMore()

        XCTAssertEqual(controller.searchResults.map(\.destination.title), ["one", "two"])
        XCTAssertEqual(controller.searchError, "Could not search Notion destinations.")
        XCTAssertFalse(controller.canLoadMore)
    }

    func testSearchCapsContinuationAfterFourPages() async throws {
        let client = DestinationControllerSearchClient(pages: [
            destinationPage(ids: ["one"], nextCursor: "cursor-2"),
            destinationPage(ids: ["two"], nextCursor: "cursor-3"),
            destinationPage(ids: ["three"], nextCursor: "cursor-4"),
            destinationPage(ids: ["four"], nextCursor: "cursor-5"),
        ])
        let (_, controller) = try await makeController(client: client)

        await controller.search(query: "notes")
        await controller.loadMore()
        await controller.loadMore()
        await controller.loadMore()

        XCTAssertEqual(
            controller.searchResults.map(\.destination.title),
            ["one", "two", "three", "four"]
        )
        XCTAssertTrue(controller.isSearchCapped)
        XCTAssertFalse(controller.canLoadMore)
    }

    func testSearchCapsContinuationAtOneHundredDisplayedResults() async throws {
        let client = DestinationControllerSearchClient(pages: [
            destinationPage(
                ids: (0 ..< 100).map { "destination-\($0)" },
                nextCursor: "cursor-2"
            ),
        ])
        let (_, controller) = try await makeController(client: client)

        await controller.search(query: "notes")

        XCTAssertEqual(controller.searchResults.count, 100)
        XCTAssertTrue(controller.isSearchCapped)
        XCTAssertFalse(controller.canLoadMore)
    }

    func testDisconnectAndReconnectRejectsLateDestinationSearchResult() async throws {
        let client = DelayedDestinationControllerClient()
        let (connectionController, controller) = try await makeController(client: client)
        let search = Task { await controller.search(query: "notes") }
        await client.waitUntilStarted(query: "notes")

        connectionController.disconnect()
        controller.resetAfterDisconnect()
        await connectionController.connect("ntn_1234567890abcdef")
        await client.finish(
            query: "notes",
            with: destinationPage(ids: ["stale"], nextCursor: "cursor-2")
        )
        await search.value

        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertNil(controller.searchError)
        XCTAssertFalse(controller.isSearching)
        XCTAssertFalse(controller.canLoadMore)
        XCTAssertFalse(controller.isSearchCapped)
    }

    func testLoadSavedDestinationPublishesRepositoryValue() async throws {
        let savedDestination = QuickCaptureDestination.pageParent(
            pageID: "saved",
            title: "Saved"
        )
        let repository = DestinationControllerRepository(savedDestination: savedDestination)
        let (_, controller) = try await makeController(repository: repository)

        await controller.loadSavedDestination()

        XCTAssertEqual(controller.destination, savedDestination)
        XCTAssertNil(controller.searchError)
    }

    func testSelectAndClearDestinationPersistBeforePublishing() async throws {
        let repository = DestinationControllerRepository()
        let (_, controller) = try await makeController(repository: repository)
        let destination = QuickCaptureDestination.dataSource(
            dataSourceID: "tasks",
            title: "Tasks"
        )

        await controller.select(destination)

        let selectedDestination = await repository.savedDestination()
        XCTAssertEqual(controller.destination, destination)
        XCTAssertEqual(selectedDestination, destination)
        XCTAssertNil(controller.searchError)

        await controller.clear()

        let clearedDestination = await repository.savedDestination()
        XCTAssertNil(controller.destination)
        XCTAssertNil(clearedDestination)
        XCTAssertNil(controller.searchError)
    }

    func testUnavailableRepositoryPreservesSelectionAndClearingErrorCopy() async throws {
        let (_, controller) = try await makeController()
        let destination = QuickCaptureDestination.pageParent(
            pageID: "notes",
            title: "Notes"
        )

        await controller.select(destination)
        XCTAssertNil(controller.destination)
        XCTAssertEqual(controller.searchError, "Quick Capture settings are unavailable.")

        await controller.clear()
        XCTAssertEqual(controller.searchError, "Quick Capture settings are unavailable.")
    }

    private func makeController(
        client: any NotionWorkspaceClient = DestinationControllerSearchClient(pages: []),
        repository: (any QuickCaptureDestinationPersisting)? = nil,
        debounceDuration: Duration = .zero
    ) async throws -> (NotionConnectionController, QuickCaptureDestinationController) {
        let store = DestinationControllerSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let connectionController = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )
        await connectionController.bootstrapSavedToken()
        return (
            connectionController,
            QuickCaptureDestinationController(
                connectionController: connectionController,
                repository: repository,
                searchDebounceDuration: debounceDuration
            )
        )
    }

    private func destinationPage(
        ids: [String],
        nextCursor: String?
    ) -> NotionDestinationSearchPage {
        NotionDestinationSearchPage(
            results: ids.map {
                NotionDestinationSearchResult(
                    destination: .pageParent(pageID: $0, title: $0),
                    lastEditedTime: ""
                )
            },
            nextCursor: nextCursor
        )
    }
}

private final class DestinationControllerSecretStore: SecretStoring {
    var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private struct DestinationControllerSearchRequest: Equatable, Sendable {
    let query: String
    let startCursor: String?
}

private actor DestinationControllerSearchClient: NotionWorkspaceClient {
    private var pages: [NotionDestinationSearchPage]
    private var recordedRequests: [DestinationControllerSearchRequest] = []

    init(pages: [NotionDestinationSearchPage]) {
        self.pages = pages
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        []
    }

    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        recordedRequests.append(
            DestinationControllerSearchRequest(query: query, startCursor: startCursor)
        )
        guard !pages.isEmpty else {
            throw NotionAPIClientError.invalidResponse
        }
        return pages.removeFirst()
    }

    func requests() -> [DestinationControllerSearchRequest] {
        recordedRequests
    }
}

private actor DelayedDestinationControllerClient: NotionWorkspaceClient {
    private var startedQueries: Set<String> = []
    private var continuations: [
        String: CheckedContinuation<NotionDestinationSearchPage, Never>
    ] = [:]

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        []
    }

    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        startedQueries.insert(query)
        return await withCheckedContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func waitUntilStarted(query: String) async {
        while !startedQueries.contains(query) {
            await Task.yield()
        }
    }

    func finish(query: String, with page: NotionDestinationSearchPage) {
        continuations.removeValue(forKey: query)?.resume(returning: page)
    }
}

private actor DestinationControllerRepository: QuickCaptureDestinationPersisting {
    private var storedDestination: QuickCaptureDestination?

    init(savedDestination: QuickCaptureDestination? = nil) {
        storedDestination = savedDestination
    }

    func defaultDestination() throws -> QuickCaptureDestination? {
        storedDestination
    }

    func replaceDefault(with destination: QuickCaptureDestination) throws {
        storedDestination = destination
    }

    func clearDefault() throws {
        storedDestination = nil
    }

    func savedDestination() -> QuickCaptureDestination? {
        storedDestination
    }
}
