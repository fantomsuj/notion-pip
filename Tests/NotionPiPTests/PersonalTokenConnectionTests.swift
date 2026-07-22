import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class PersonalTokenConnectionTests: XCTestCase {
    func testSuccessfulConnectionValidatesBeforeSavingToken() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        let client = ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace"))
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: ConnectionTestPasteboard(),
            shortcutRegistrar: ConnectionTestShortcutRegistrar(),
            pageURLInputPresenter: FakePageURLInputPresenter(),
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await runtime.connectPersonalToken("ntn_1234567890abcdef")

        XCTAssertEqual(runtime.connectionState, .connected(workspaceName: "Personal Workspace"))
        XCTAssertEqual(try vault.load()?.redactedDescription, "ntn_…cdef")
        XCTAssertEqual(client.validationCount, 1)
    }

    func testFailedConnectionDoesNotPersistToken() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        let client = ConnectionTestClient(error: .unauthorized)
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: ConnectionTestPasteboard(),
            shortcutRegistrar: ConnectionTestShortcutRegistrar(),
            pageURLInputPresenter: FakePageURLInputPresenter(),
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        await runtime.connectPersonalToken("ntn_1234567890abcdef")

        XCTAssertEqual(runtime.connectionState, .failed("Notion did not accept this token."))
        XCTAssertNil(try vault.load())
    }

    func testSavedTokenBootstrapValidatesBeforePublishingConnectedState() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Saved Workspace"))
        let runtime = makeRuntime(vault: vault, client: client)

        await runtime.bootstrapPersonalTokenConnection()

        XCTAssertEqual(client.validationCount, 1)
        XCTAssertEqual(runtime.connectionState, .connected(workspaceName: "Saved Workspace"))
    }

    func testStartBootstrapsSavedTokenBeforePublishingConnectedState() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Launch Workspace"))
        let runtime = makeRuntime(vault: vault, client: client)

        runtime.start()
        for _ in 0 ..< 20 where runtime.connectionState != .connected(workspaceName: "Launch Workspace") {
            await Task.yield()
        }

        XCTAssertEqual(client.validationCount, 1)
        XCTAssertEqual(runtime.connectionState, .connected(workspaceName: "Launch Workspace"))
    }

    func testDisconnectDuringSavedTokenBootstrapDoesNotReconnect() async throws {
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let client = DelayedConnectionTestClient(workspaceName: "Saved Workspace")
        let runtime = AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: ConnectionTestPasteboard(),
            shortcutRegistrar: ConnectionTestShortcutRegistrar(),
            pageURLInputPresenter: FakePageURLInputPresenter(),
            credentialVault: vault,
            notionClientFactory: { _ in client }
        )

        let bootstrap = Task {
            await runtime.bootstrapPersonalTokenConnection()
        }
        await client.waitUntilValidationStarts()
        runtime.disconnectPersonalToken()
        await client.finishValidation()
        await bootstrap.value

        XCTAssertEqual(runtime.connectionState, .disconnected)
        XCTAssertNil(try vault.load())
    }

    func testFailedSavedTokenBootstrapRequiresReconnectAndDisablesAPISearch() async throws {
        let rawToken = "ntn_1234567890abcdef"
        let secretStore = ConnectionTestSecretStore()
        let vault = PersonalTokenCredentialVault(store: secretStore)
        try vault.save(PersonalIntegrationToken(validating: rawToken))
        let client = ConnectionTestClient(error: .unauthorized)
        let runtime = makeRuntime(vault: vault, client: client)

        await runtime.bootstrapPersonalTokenConnection()
        await runtime.searchNotionPages(query: "private")
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Private-0123456789abcdef0123456789abcdef"))
        )
        runtime.activate(page: page, source: .typedURL)
        for _ in 0 ..< 3 { await Task.yield() }

        XCTAssertEqual(runtime.connectionState, .failed("Notion did not accept this token. Reconnect to continue."))
        XCTAssertEqual(client.validationCount, 1)
        XCTAssertEqual(client.searchCount, 0)
        XCTAssertEqual(client.previewCount, 0)
        XCTAssertFalse(connectionMessage(runtime.connectionState).contains(rawToken))
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
        let runtime = makeRuntime(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: FileSystemLegacyNativePageCacheCleaner(),
            legacyCacheDirectory: cacheDirectory
        )

        runtime.disconnectPersonalToken()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
        XCTAssertNil(try vault.load())
        XCTAssertEqual(runtime.connectionState, .disconnected)
    }

    func testCleanupFailureStillLeavesTokenDisconnected() throws {
        let cacheDirectory = URL(fileURLWithPath: "/explicit/legacy/NativePageCache", isDirectory: true)
        let cleaner = FailingLegacyNativePageCacheCleaner()
        let vault = PersonalTokenCredentialVault(store: ConnectionTestSecretStore())
        try vault.save(PersonalIntegrationToken(validating: "ntn_1234567890abcdef"))
        let runtime = makeRuntime(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: cleaner,
            legacyCacheDirectory: cacheDirectory
        )

        runtime.disconnectPersonalToken()

        XCTAssertEqual(cleaner.requestedDirectories, [cacheDirectory])
        XCTAssertNil(try vault.load())
        XCTAssertEqual(runtime.connectionState, .disconnected)
    }

    func testStartDoesNotAutomaticallyCleanLegacyNativePreviewCache() {
        let cleaner = RecordingLegacyNativePageCacheCleaner()
        let vault = PersonalTokenCredentialVault(store: ConnectionTestSecretStore())
        let runtime = makeRuntime(
            vault: vault,
            client: ConnectionTestClient(connection: NotionConnectionSnapshot(workspaceName: "Personal Workspace")),
            legacyCacheCleaner: cleaner,
            legacyCacheDirectory: URL(fileURLWithPath: "/explicit/legacy/NativePageCache", isDirectory: true)
        )

        runtime.start()

        XCTAssertTrue(cleaner.requestedDirectories.isEmpty)
    }

    private func makeRuntime(
        vault: PersonalTokenCredentialVault,
        client: ConnectionTestClient,
        legacyCacheCleaner: any LegacyNativePageCacheCleaning = FileSystemLegacyNativePageCacheCleaner(),
        legacyCacheDirectory: URL = FileSystemLegacyNativePageCacheCleaner.defaultDirectoryURL
    ) -> AppRuntime {
        AppRuntime(
            panelCoordinator: FakePanelCoordinator(),
            pasteboard: ConnectionTestPasteboard(),
            shortcutRegistrar: ConnectionTestShortcutRegistrar(),
            pageURLInputPresenter: FakePageURLInputPresenter(),
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

private final class ConnectionTestClient: NotionWorkspaceClient {
    private let connection: NotionConnectionSnapshot?
    private let error: NotionAPIClientError?
    private(set) var validationCount = 0
    private(set) var searchCount = 0
    private(set) var previewCount = 0

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
    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot {
        previewCount += 1
        return NativePageSnapshot(pageID: page.pageID, title: "Unused", blocks: [], remoteFingerprint: "", fetchedAt: Date())
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

    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot {
        NativePageSnapshot(pageID: page.pageID, title: "Unused", blocks: [], remoteFingerprint: "", fetchedAt: Date())
    }

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
    func register(handler: @escaping @MainActor () -> Void) throws {}
    func unregister() {}
}
