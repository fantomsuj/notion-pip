import Combine
import XCTest
@testable import NotionPiP

@MainActor
final class AppRuntimeFacadeTests: XCTestCase {
    func testStartForwardsSavedTokenBootstrapThroughFacade() async throws {
        let client = FacadeNotionClient(workspaceName: "Launch Workspace")
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)

        runtime.start()
        await client.waitUntilValidationCount(1)

        let validationCount = await client.validationCount()
        XCTAssertEqual(validationCount, 1)
        XCTAssertEqual(
            runtime.connectionState,
            .connected(workspaceName: "Launch Workspace")
        )
    }

    func testWorkspaceSearchFacadeForwardsResultsAndChildPublication() async throws {
        let result = NotionPageSearchResult(
            page: try makePage(id: firstPageID, title: "Roadmap"),
            title: "Roadmap",
            lastEditedTime: "2026-07-28T00:00:00.000Z"
        )
        let client = FacadeNotionClient(workspaceResults: [result])
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)
        await runtime.bootstrapPersonalTokenConnection()
        var publicationCount = 0
        let observation = runtime.objectWillChange.sink {
            publicationCount += 1
        }

        await runtime.searchNotionPages(query: "Roadmap")

        let queries = await client.workspaceQueries()
        XCTAssertEqual(queries, ["Roadmap"])
        XCTAssertEqual(runtime.searchResults, [result])
        XCTAssertGreaterThan(publicationCount, 0)
        withExtendedLifetime(observation) {}
    }

    func testDestinationSearchFacadeForwardsResultsAndChildPublication() async {
        let result = NotionDestinationSearchResult(
            destination: .pageParent(pageID: firstPageID, title: "Roadmap"),
            lastEditedTime: "2026-07-28T00:00:00.000Z"
        )
        let client = FacadeNotionClient(
            destinationPage: NotionDestinationSearchPage(
                results: [result],
                nextCursor: nil
            )
        )
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)
        await runtime.bootstrapPersonalTokenConnection()
        var publicationCount = 0
        let observation = runtime.objectWillChange.sink {
            publicationCount += 1
        }

        await runtime.searchQuickCaptureDestinations(query: "Roadmap")

        let requests = await client.destinationRequests()
        XCTAssertEqual(
            requests,
            [FacadeDestinationRequest(query: "Roadmap", startCursor: nil)]
        )
        XCTAssertEqual(runtime.destinationSearchResults, [result])
        XCTAssertGreaterThan(publicationCount, 0)
        withExtendedLifetime(observation) {}
    }

    func testDisconnectFacadeResetsDestinationControllerState() async {
        let result = NotionDestinationSearchResult(
            destination: .pageParent(pageID: firstPageID, title: "Roadmap"),
            lastEditedTime: ""
        )
        let client = FacadeNotionClient(
            destinationPage: NotionDestinationSearchPage(
                results: [result],
                nextCursor: "next"
            )
        )
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)
        await runtime.bootstrapPersonalTokenConnection()
        await runtime.searchQuickCaptureDestinations(query: "Roadmap")

        runtime.disconnectPersonalToken()

        XCTAssertEqual(runtime.connectionState, .disconnected)
        XCTAssertTrue(runtime.destinationSearchResults.isEmpty)
        XCTAssertNil(runtime.destinationSearchError)
        XCTAssertFalse(runtime.isSearchingDestinations)
        XCTAssertFalse(runtime.canLoadMoreDestinations)
        XCTAssertFalse(runtime.isDestinationSearchCapped)
    }
}

private struct FacadeDestinationRequest: Equatable, Sendable {
    let query: String
    let startCursor: String?
}

private actor FacadeNotionClient: NotionWorkspaceClient {
    private let workspaceName: String
    private let workspaceResults: [NotionPageSearchResult]
    private let destinationPage: NotionDestinationSearchPage
    private var recordedValidationCount = 0
    private var recordedWorkspaceQueries: [String] = []
    private var recordedDestinationRequests: [FacadeDestinationRequest] = []

    init(
        workspaceName: String = "Workspace",
        workspaceResults: [NotionPageSearchResult] = [],
        destinationPage: NotionDestinationSearchPage = NotionDestinationSearchPage(
            results: [],
            nextCursor: nil
        )
    ) {
        self.workspaceName = workspaceName
        self.workspaceResults = workspaceResults
        self.destinationPage = destinationPage
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        recordedValidationCount += 1
        return NotionConnectionSnapshot(workspaceName: workspaceName)
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        recordedWorkspaceQueries.append(query)
        return workspaceResults
    }

    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        recordedDestinationRequests.append(
            FacadeDestinationRequest(query: query, startCursor: startCursor)
        )
        return destinationPage
    }

    func validationCount() -> Int {
        recordedValidationCount
    }

    func workspaceQueries() -> [String] {
        recordedWorkspaceQueries
    }

    func destinationRequests() -> [FacadeDestinationRequest] {
        recordedDestinationRequests
    }

    func waitUntilValidationCount(_ count: Int) async {
        while recordedValidationCount < count {
            await Task.yield()
        }
    }
}
