import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class PersonalTokenConnectionTests: XCTestCase {
    func testSuccessfulConnectionValidatesBeforeSavingToken() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        let client = ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace"))
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.connect("ntn_1234567890abcdef")

        XCTAssertEqual(
            controller.state,
            .connected(workspaceName: "Personal Workspace")
        )
        XCTAssertEqual(try vault.load()?.redactedDescription, "ntn_…cdef")
        XCTAssertEqual(client.validationCount, 1)
    }

    func testFailedConnectionDoesNotPersistToken() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        let client = ConnectionTestClient(error: .unauthorized)
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.connect("ntn_1234567890abcdef")

        XCTAssertEqual(
            controller.state,
            .failed("Notion did not accept this token.")
        )
        XCTAssertNil(try vault.load())
    }

    func testSavedTokenBootstrapValidatesBeforePublishingConnectedState() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Saved Workspace"))
        let controller = makeController(vault: vault, client: client)

        await controller.bootstrapSavedToken()

        XCTAssertEqual(client.validationCount, 1)
        XCTAssertEqual(
            controller.state,
            .connected(workspaceName: "Saved Workspace")
        )
    }

    func testDisconnectDuringSavedTokenBootstrapDoesNotReconnect() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = DelayedConnectionTestClient(workspaceName: "Saved Workspace")
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        let bootstrap = Task {
            await controller.bootstrapSavedToken()
        }
        await client.waitUntilValidationStarts()
        controller.disconnect()
        await client.finishValidation()
        await bootstrap.value

        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertNil(try vault.load())
    }

    func testFailedSavedTokenBootstrapRequiresReconnectAndDisablesAPISearch() async throws {
        let rawToken = "ntn_1234567890abcdef"
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: rawToken))
        let client = ConnectionTestClient(error: .unauthorized)
        let controller = makeController(vault: vault, client: client)

        await controller.bootstrapSavedToken()
        await controller.searchPages(query: "private")

        XCTAssertEqual(
            controller.state,
            .failed("Notion did not accept this token. Reconnect to continue.")
        )
        XCTAssertEqual(client.validationCount, 1)
        XCTAssertEqual(client.searchCount, 0)
        XCTAssertFalse(connectionMessage(controller.state).contains(rawToken))
    }

    private func makeController(
        vault: PersonalTokenCredentialVault,
        client: any NotionWorkspaceClient
    ) -> NotionConnectionController {
        NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )
    }

    private func connectionMessage(_ state: PersonalTokenConnectionState) -> String {
        guard case let .failed(message) = state else { return "" }
        return message
    }
}

private final class ConnectionTestSecretStore: SecretStoring {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

@MainActor
private final class ConnectionTestClient: NotionWorkspaceClient {
    private let connection: NotionConnectionSnapshot?
    private let error: NotionAPIClientError?
    private(set) var validationCount = 0
    private(set) var searchCount = 0

    init(connection: NotionConnectionSnapshot) {
        self.connection = connection
        error = nil
    }

    init(error: NotionAPIClientError) {
        connection = nil
        self.error = error
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        validationCount += 1
        if let error { throw error }
        return connection!
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        searchCount += 1
        return []
    }
}

private actor DelayedConnectionTestClient: NotionWorkspaceClient {
    private let workspaceName: String
    private var validationContinuation: CheckedContinuation<Void, Never>?
    private var validationStarted = false

    init(workspaceName: String) {
        self.workspaceName = workspaceName
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        validationStarted = true
        await withCheckedContinuation { validationContinuation = $0 }
        return NotionConnectionSnapshot(workspaceName: workspaceName)
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] { [] }

    func waitUntilValidationStarts() async {
        while !validationStarted {
            await Task.yield()
        }
    }

    func finishValidation() {
        validationContinuation?.resume()
        validationContinuation = nil
    }
}
