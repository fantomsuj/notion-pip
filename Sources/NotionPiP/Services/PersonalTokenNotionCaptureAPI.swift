import Foundation

actor PersonalTokenNotionCaptureAPI: NotionCapturePageAPI {
    private let credentialVault: PersonalTokenCredentialVault
    private let clientFactory: @Sendable (PersonalIntegrationToken) -> NotionAPIClient

    init(
        credentialVault: PersonalTokenCredentialVault,
        clientFactory: @escaping @Sendable (PersonalIntegrationToken) -> NotionAPIClient = {
            NotionAPIClient(token: $0)
        }
    ) {
        self.credentialVault = credentialVault
        self.clientFactory = clientFactory
    }

    func dataSourceTitleProperty(
        dataSourceID: String
    ) async throws -> NotionDataSourceTitleProperty {
        let client = try await client()
        return try await client.dataSourceTitleProperty(dataSourceID: dataSourceID)
    }

    func createPage(
        parent: NotionPageParent,
        titlePropertyName: String,
        title: String,
        children: [JSONValue]
    ) async throws -> NotionCreatedPage {
        let client = try await client()
        return try await client.createPage(
            parent: parent,
            titlePropertyName: titlePropertyName,
            title: title,
            children: children
        )
    }

    func appendBlockChildren(
        pageID: String,
        children: [JSONValue]
    ) async throws {
        let client = try await client()
        try await client.appendBlockChildren(pageID: pageID, children: children)
    }

    private func client() async throws -> NotionAPIClient {
        guard let token = try await credentialVault.load() else {
            throw NotionAPIClientError.unauthorized
        }
        return clientFactory(token)
    }
}
