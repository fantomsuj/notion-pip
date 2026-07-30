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

    func testDisconnectRemovesLegacyNativePreviewCacheAtExplicitDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheDirectory = root
            .appendingPathComponent("Application Support/NotionPiP/NativePageCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data("legacy preview".utf8).write(to: cacheDirectory.appendingPathComponent("preview.html"))
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = PersonalTokenCredentialVault(store: ConnectionTestSecretStore())
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let controller = makeController(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: FileSystemLegacyNativePageCacheCleaner(),
            legacyCacheDirectory: cacheDirectory
        )

        controller.disconnect()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
        XCTAssertNil(try vault.load())
        XCTAssertEqual(controller.state, .disconnected)
    }

    func testCleanupFailureStillLeavesTokenDisconnected() throws {
        let cacheDirectory = URL(fileURLWithPath: "/explicit/legacy/NativePageCache", isDirectory: true)
        let cleaner = FailingLegacyNativePageCacheCleaner()
        let vault = PersonalTokenCredentialVault(store: ConnectionTestSecretStore())
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let controller = makeController(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: cleaner,
            legacyCacheDirectory: cacheDirectory
        )

        controller.disconnect()

        XCTAssertEqual(cleaner.requestedDirectories, [cacheDirectory])
        XCTAssertNil(try vault.load())
        XCTAssertEqual(controller.state, .disconnected)
    }

    func testBootstrapSavedTokenDoesNotCleanLegacyNativePreviewCache() async {
        let cleaner = RecordingLegacyNativePageCacheCleaner()
        let vault = PersonalTokenCredentialVault(store: ConnectionTestSecretStore())
        let controller = makeController(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: cleaner,
            legacyCacheDirectory: URL(fileURLWithPath: "/explicit/legacy/NativePageCache", isDirectory: true)
        )

        await controller.bootstrapSavedToken()

        XCTAssertTrue(cleaner.requestedDirectories.isEmpty)
    }

    func testDefaultRuntimeCleanerDoesNotTouchLegacyNativePreviewCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("NativePageCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = PersonalTokenCredentialVault(store: ConnectionTestSecretStore())
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ConnectionTestClient(
            connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")
        )
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: ConnectionTestPasteboard(),
            shortcutRegistrar: ConnectionTestShortcutRegistrar(),
            pageURLInputPresenter: FakePageURLInputPresenter(),
            credentialVault: vault,
            legacyCacheDirectory: cacheDirectory,
            notionClientFactory: { _ in client }
        )

        runtime.disconnectPersonalToken()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDirectory.path))
        XCTAssertNil(try vault.load())
        XCTAssertEqual(runtime.connectionState, .disconnected)
    }

    func testCredentialDeletionFailureDoesNotAttemptLegacyCacheCleanup() throws {
        let store = DeleteFailingConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: store)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let cleaner = RecordingLegacyNativePageCacheCleaner()
        let cacheDirectory = URL(fileURLWithPath: "/explicit/legacy/NativePageCache", isDirectory: true)
        let controller = makeController(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: cleaner,
            legacyCacheDirectory: cacheDirectory
        )

        controller.disconnect()

        XCTAssertTrue(cleaner.requestedDirectories.isEmpty)
        XCTAssertEqual(
            controller.state,
            .failed("Could not remove the saved token.")
        )
        XCTAssertNotNil(try vault.load())
    }

    private func makeController(
        vault: PersonalTokenCredentialVault,
        client: any NotionWorkspaceClient,
        legacyCacheCleaner: any LegacyNativePageCacheCleaning = NoOpLegacyNativePageCacheCleaner(),
        legacyCacheDirectory: URL = FileSystemLegacyNativePageCacheCleaner.defaultDirectoryURL
    ) -> NotionConnectionController {
        NotionConnectionController(
            credentialVault: vault,
            legacyCacheCleaner: legacyCacheCleaner,
            legacyCacheDirectory: legacyCacheDirectory,
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

private final class DeleteFailingConnectionTestSecretStore: SecretStoring {
    var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { throw CocoaError(.fileWriteUnknown) }
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

private final class RecordingLegacyNativePageCacheCleaner: LegacyNativePageCacheCleaning {
    private(set) var requestedDirectories: [URL] = []

    func removeLegacyCache(at directory: URL) throws {
        requestedDirectories.append(directory)
    }
}

private final class FailingLegacyNativePageCacheCleaner: LegacyNativePageCacheCleaning {
    private(set) var requestedDirectories: [URL] = []

    func removeLegacyCache(at directory: URL) throws {
        requestedDirectories.append(directory)
        throw CocoaError(.fileWriteUnknown)
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

private struct ConnectionTestPasteboard: PasteboardReading {
    func readString() -> String? { nil }
}

@MainActor
private final class ConnectionTestShortcutRegistrar: GlobalShortcutRegistering {
    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {}
    func unregister() {}
}
