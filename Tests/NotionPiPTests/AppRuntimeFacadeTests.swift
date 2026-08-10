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

    func testDisconnectFacadeResetsConnectionState() async {
        let client = FacadeNotionClient()
        let runtime = makeRuntime(panel: RuntimePanelCoordinator(), client: client)
        await runtime.bootstrapPersonalTokenConnection()

        runtime.disconnectPersonalToken()

        XCTAssertEqual(runtime.connectionState, .disconnected)
    }
}

private actor FacadeNotionClient: NotionWorkspaceClient {
    private let workspaceName: String
    private let workspaceResults: [NotionPageSearchResult]
    private var recordedValidationCount = 0
    private var recordedWorkspaceQueries: [String] = []

    init(
        workspaceName: String = "Workspace",
        workspaceResults: [NotionPageSearchResult] = []
    ) {
        self.workspaceName = workspaceName
        self.workspaceResults = workspaceResults
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        recordedValidationCount += 1
        return NotionConnectionSnapshot(workspaceName: workspaceName)
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        recordedWorkspaceQueries.append(query)
        return workspaceResults
    }

    func validationCount() -> Int {
        recordedValidationCount
    }

    func workspaceQueries() -> [String] {
        recordedWorkspaceQueries
    }

    func waitUntilValidationCount(_ count: Int) async {
        while recordedValidationCount < count {
            await Task.yield()
        }
    }
}
