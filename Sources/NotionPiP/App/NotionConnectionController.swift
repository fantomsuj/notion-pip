import Combine
import Foundation

struct NotionWorkspaceClientLease {
    let generation: Int
    let client: any NotionWorkspaceClient
}

@MainActor
final class NotionConnectionController: ObservableObject {
    @Published private(set) var state: PersonalTokenConnectionState = .disconnected
    @Published private(set) var searchResults: [NotionPageSearchResult] = []
    @Published private(set) var searchError: String?

    var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    var generation: Int {
        connectionGeneration
    }

    private let credentialVault: PersonalTokenCredentialVault
    private let notionClientFactory: (PersonalIntegrationToken) -> any NotionWorkspaceClient
    private let onReconnect: @MainActor () async -> Void
    private var searchTask: Task<Void, Never>?
    private var connectionGeneration = 0

    init(
        credentialVault: PersonalTokenCredentialVault = PersonalTokenCredentialVault(),
        notionClientFactory: @escaping (PersonalIntegrationToken) -> any NotionWorkspaceClient = { token in
            NotionAPIClient(token: token)
        },
        onReconnect: @escaping @MainActor () async -> Void = {}
    ) {
        self.credentialVault = credentialVault
        self.notionClientFactory = notionClientFactory
        self.onReconnect = onReconnect
    }

    func connect(_ rawValue: String) async {
        connectionGeneration &+= 1
        let generation = connectionGeneration

        do {
            let token = try PersonalIntegrationToken(validating: rawValue)
            state = .connecting
            let connection = try await notionClientFactory(token).validateConnection()
            guard isCurrent(generation: generation) else { return }
            try credentialVault.save(token)
            guard isCurrent(generation: generation) else { return }
            state = .connected(workspaceName: connection.workspaceName)
            await onReconnect()
        } catch let error as PersonalIntegrationTokenError {
            guard isCurrent(generation: generation) else { return }
            state = .failed(
                error == .missing
                    ? "Enter your Notion personal access token."
                    : "Use a Notion personal access token that starts with ntn_."
            )
        } catch let error as NotionAPIClientError {
            guard isCurrent(generation: generation) else { return }
            state = .failed(Self.connectionMessage(for: error))
        } catch {
            guard isCurrent(generation: generation) else { return }
            state = .failed("Could not connect to Notion. Check your network and try again.")
        }
    }

    func bootstrapSavedToken() async {
        let generation = connectionGeneration

        do {
            guard let token = try credentialVault.load() else {
                guard isCurrent(generation: generation) else { return }
                state = .disconnected
                return
            }
            state = .connecting
            let connection = try await notionClientFactory(token).validateConnection()
            guard isCurrent(generation: generation) else { return }
            state = .connected(workspaceName: connection.workspaceName)
            await onReconnect()
        } catch let error as NotionAPIClientError {
            guard isCurrent(generation: generation) else { return }
            state = .failed(Self.reconnectMessage(for: error))
        } catch {
            guard isCurrent(generation: generation) else { return }
            state = .failed("Saved Notion access needs to be reconnected.")
        }
    }

    func disconnect() {
        do {
            try credentialVault.disconnect()
            connectionGeneration &+= 1
            searchTask?.cancel()
            searchTask = nil
            state = .disconnected
            searchResults = []
            searchError = nil
        } catch {
            state = .failed("Could not remove the saved token.")
            return
        }

    }

    func searchPages(query: String) async {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.loadSearchResults(query: query)
        }
        await searchTask?.value
    }

    func hasUsableToken() -> Bool {
        guard isConnected else { return false }
        return (try? credentialVault.load()) != nil
    }

    func workspaceClientLease() throws -> NotionWorkspaceClientLease? {
        guard let token = try credentialVault.load() else {
            return nil
        }
        return NotionWorkspaceClientLease(
            generation: connectionGeneration,
            client: notionClientFactory(token)
        )
    }

    func isCurrent(_ lease: NotionWorkspaceClientLease) -> Bool {
        isCurrent(generation: lease.generation)
    }

    private func loadSearchResults(query: String) async {
        let generation = connectionGeneration
        do {
            guard isCurrent(generation: generation) else { return }
            guard isConnected else {
                searchResults = []
                searchError = "Reconnect to Notion to search your workspace."
                return
            }
            guard let lease = try workspaceClientLease() else {
                guard isCurrent(generation: generation) else { return }
                searchResults = []
                searchError = "Connect a Notion personal access token first."
                return
            }
            guard isCurrent(lease) else { return }
            searchError = nil
            let results = try await lease.client.searchPages(query: query)
            guard isCurrent(lease) else { return }
            searchResults = results
        } catch {
            guard isCurrent(generation: generation) else { return }
            searchResults = []
            searchError = "Could not search Notion. Check the token, permissions, and network."
        }
    }

    func isCurrent(generation: Int) -> Bool {
        generation == connectionGeneration && !Task.isCancelled
    }

    private static func connectionMessage(for error: NotionAPIClientError) -> String {
        switch error {
        case .unauthorized:
            "Notion did not accept this token."
        case .accessDenied:
            "This token does not have the Notion API capability."
        case .apiError(let details) where details.statusCode == 401:
            "Notion did not accept this token."
        case .apiError(let details) where details.statusCode == 403:
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
        case .apiError(let details) where details.statusCode == 401:
            "Notion did not accept this token. Reconnect to continue."
        case .apiError(let details) where details.statusCode == 403:
            "This token does not have the Notion API capability. Reconnect to continue."
        default:
            "Saved Notion access needs to be reconnected."
        }
    }
}
