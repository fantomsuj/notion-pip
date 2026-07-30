import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class NotionConnectionControllerTests: XCTestCase {
    func testConnectValidatesSavesTokenAndNotifiesReconnect() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        let client = ImmediateConnectionControllerClient(
            validation: .success(NotionConnectionSnapshot(workspaceName: "Personal Workspace"))
        )
        let reconnects = ConnectionControllerReconnectRecorder()
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client },
            onReconnect: {
                await reconnects.record()
            }
        )

        await controller.connect(" ntn_1234567890abcdef ")

        let validationCount = await client.validationCount()
        let reconnectCount = await reconnects.count()
        XCTAssertEqual(controller.state, .connected(workspaceName: "Personal Workspace"))
        XCTAssertEqual(try vault.load()?.redactedDescription, "ntn_…cdef")
        XCTAssertEqual(validationCount, 1)
        XCTAssertEqual(reconnectCount, 1)
    }

    func testConnectRejectsUnsupportedTokenWithoutCallingClient() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        let client = ImmediateConnectionControllerClient(
            validation: .success(NotionConnectionSnapshot(workspaceName: "Personal Workspace"))
        )
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.connect("secret_1234567890abcdef")

        let validationCount = await client.validationCount()
        XCTAssertEqual(
            controller.state,
            .failed("Use a Notion personal access token that starts with ntn_.")
        )
        XCTAssertNil(try vault.load())
        XCTAssertEqual(validationCount, 0)
    }

    func testConnectMapsUnauthorizedErrorWithoutSavingToken() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        let client = ImmediateConnectionControllerClient(validation: .failure(.unauthorized))
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.connect("ntn_1234567890abcdef")

        XCTAssertEqual(controller.state, .failed("Notion did not accept this token."))
        XCTAssertNil(try vault.load())
    }

    func testBootstrapSavedTokenUsesReconnectErrorMessage() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ImmediateConnectionControllerClient(validation: .failure(.accessDenied))
        let reconnects = ConnectionControllerReconnectRecorder()
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client },
            onReconnect: {
                await reconnects.record()
            }
        )

        await controller.bootstrapSavedToken()

        let reconnectCount = await reconnects.count()
        XCTAssertEqual(
            controller.state,
            .failed("This token does not have the Notion API capability. Reconnect to continue.")
        )
        XCTAssertEqual(reconnectCount, 0)
    }

    func testBootstrapSavedTokenNotifiesReconnect() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ImmediateConnectionControllerClient(
            validation: .success(NotionConnectionSnapshot(workspaceName: "Saved Workspace"))
        )
        let reconnects = ConnectionControllerReconnectRecorder()
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client },
            onReconnect: {
                await reconnects.record()
            }
        )

        await controller.bootstrapSavedToken()

        let reconnectCount = await reconnects.count()
        XCTAssertEqual(controller.state, .connected(workspaceName: "Saved Workspace"))
        XCTAssertEqual(reconnectCount, 1)
    }

    func testWorkspaceSearchFailurePublishesUserFacingError() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ImmediateConnectionControllerClient(
            validation: .success(NotionConnectionSnapshot(workspaceName: "Workspace")),
            search: .failure(.requestFailed(statusCode: 503))
        )
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )
        await controller.bootstrapSavedToken()

        await controller.searchPages(query: "Roadmap")

        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertEqual(
            controller.searchError,
            "Could not search Notion. Check the token, permissions, and network."
        )
    }

    func testDisconnectClearsSearchAndRemovesLegacyCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("NativePageCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let searchResult = try makeSearchResult(title: "Roadmap")
        let client = ImmediateConnectionControllerClient(
            validation: .success(NotionConnectionSnapshot(workspaceName: "Workspace")),
            search: .success([searchResult])
        )
        let controller = NotionConnectionController(
            credentialVault: vault,
            legacyCacheCleaner: FileSystemLegacyNativePageCacheCleaner(),
            legacyCacheDirectory: cacheDirectory,
            notionClientFactory: { _ in client }
        )
        await controller.bootstrapSavedToken()
        await controller.searchPages(query: "Roadmap")

        controller.disconnect()

        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertNil(controller.searchError)
        XCTAssertNil(try vault.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    }

    func testCredentialDeletionFailureDoesNotCleanLegacyCache() async throws {
        let store = DeleteFailingConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let cleaner = RecordingConnectionControllerCacheCleaner()
        let controller = NotionConnectionController(
            credentialVault: vault,
            legacyCacheCleaner: cleaner,
            legacyCacheDirectory: URL(fileURLWithPath: "/explicit/legacy-cache"),
            notionClientFactory: { _ in
                ImmediateConnectionControllerClient(
                    validation: .success(NotionConnectionSnapshot(workspaceName: "Workspace"))
                )
            }
        )

        controller.disconnect()

        XCTAssertEqual(controller.state, .failed("Could not remove the saved token."))
        XCTAssertTrue(cleaner.requestedDirectories.isEmpty)
        XCTAssertNotNil(try vault.load())
    }

    func testDisconnectAndReconnectRejectsLateWorkspaceSearchResult() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = DelayedConnectionControllerClient()
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.bootstrapSavedToken()
        let search = Task {
            await controller.searchPages(query: "Roadmap")
        }
        await client.waitUntilSearchStarts()

        controller.disconnect()
        await controller.connect("ntn_1234567890abcdef")
        await client.finishSearch()
        await search.value

        XCTAssertEqual(controller.state, .connected(workspaceName: "Workspace"))
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertNil(controller.searchError)
    }

    func testDisconnectAndReconnectRejectsLateWorkspaceSearchError() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = DelayedConnectionControllerClient(searchError: .unauthorized)
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.bootstrapSavedToken()
        let search = Task {
            await controller.searchPages(query: "Roadmap")
        }
        await client.waitUntilSearchStarts()

        controller.disconnect()
        await controller.connect("ntn_1234567890abcdef")
        await client.finishSearch()
        await search.value

        XCTAssertEqual(controller.state, .connected(workspaceName: "Workspace"))
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertNil(controller.searchError)
    }

    func testReconnectRejectsLateWorkspaceSearchErrorWithoutTaskCancellation() async throws {
        let store = ConnectionControllerTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = DelayedConnectionControllerClient(searchError: .unauthorized)
        let controller = NotionConnectionController(
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await controller.bootstrapSavedToken()
        let search = Task {
            await controller.searchPages(query: "Roadmap")
        }
        await client.waitUntilSearchStarts()

        await controller.connect("ntn_1234567890abcdef")
        await client.finishSearch()
        await search.value

        XCTAssertEqual(controller.state, .connected(workspaceName: "Workspace"))
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertNil(controller.searchError)
    }

    private func makeSearchResult(title: String) throws -> NotionPageSearchResult {
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/\(title)-0123456789abcdef0123456789abcdef")
            )
        )
        return NotionPageSearchResult(page: page, title: title, lastEditedTime: "")
    }
}

private final class ConnectionControllerTestSecretStore: SecretStoring {
    var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private final class DeleteFailingConnectionControllerTestSecretStore: SecretStoring {
    var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { throw CocoaError(.fileWriteUnknown) }
}

private final class RecordingConnectionControllerCacheCleaner: LegacyNativePageCacheCleaning {
    private(set) var requestedDirectories: [URL] = []

    func removeLegacyCache(at directory: URL) throws {
        requestedDirectories.append(directory)
    }
}

private actor ConnectionControllerReconnectRecorder {
    private var reconnectCount = 0

    func record() {
        reconnectCount += 1
    }

    func count() -> Int {
        reconnectCount
    }
}

private actor ImmediateConnectionControllerClient: NotionWorkspaceClient {
    private let validation: Result<NotionConnectionSnapshot, NotionAPIClientError>
    private let search: Result<[NotionPageSearchResult], NotionAPIClientError>
    private var validationCallCount = 0

    init(
        validation: Result<NotionConnectionSnapshot, NotionAPIClientError>,
        search: Result<[NotionPageSearchResult], NotionAPIClientError> = .success([])
    ) {
        self.validation = validation
        self.search = search
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        validationCallCount += 1
        return try validation.get()
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        try search.get()
    }

    func validationCount() -> Int {
        validationCallCount
    }
}

private actor DelayedConnectionControllerClient: NotionWorkspaceClient {
    private let searchError: NotionAPIClientError?
    private var searchContinuation: CheckedContinuation<Void, Never>?
    private var searchStarted = false

    init(searchError: NotionAPIClientError? = nil) {
        self.searchError = searchError
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        NotionConnectionSnapshot(workspaceName: "Workspace")
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        searchStarted = true
        await withCheckedContinuation { searchContinuation = $0 }
        if let searchError {
            throw searchError
        }
        let page = try! NotionPageReference(
            validating: URL(
                string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"
            )!
        )
        return [NotionPageSearchResult(page: page, title: "Roadmap", lastEditedTime: "")]
    }

    func waitUntilSearchStarts() async {
        while !searchStarted {
            await Task.yield()
        }
    }

    func finishSearch() {
        searchContinuation?.resume()
        searchContinuation = nil
    }
}
