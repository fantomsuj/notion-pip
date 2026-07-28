import Foundation

protocol NotionRequestTransport: AnyObject, Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol NotionWorkspaceClient: AnyObject, Sendable {
    func validateConnection() async throws -> NotionConnectionSnapshot
    func searchPages(query: String) async throws -> [NotionPageSearchResult]
    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage
    func dataSourceTitleProperty(dataSourceID: String) async throws -> NotionDataSourceTitleProperty
}

extension NotionWorkspaceClient {
    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        throw NotionAPIClientError.invalidResponse
    }

    func dataSourceTitleProperty(
        dataSourceID: String
    ) async throws -> NotionDataSourceTitleProperty {
        throw NotionAPIClientError.invalidResponse
    }
}

final class URLSessionNotionRequestTransport: NotionRequestTransport {
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval
    let maximumResponseBytes: Int

    private let session: URLSession

    init(
        requestTimeout: TimeInterval = 15,
        resourceTimeout: TimeInterval = 30,
        maximumResponseBytes: Int = NotionAPIClient.defaultMaximumResponseBytes
    ) {
        precondition(maximumResponseBytes > 0)
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumResponseBytes = maximumResponseBytes

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAPIClientError.invalidResponse
        }
        if response.expectedContentLength > maximumResponseBytes {
            throw NotionAPIClientError.responseTooLarge(maximumBytes: maximumResponseBytes)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseBytes))
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else {
                throw NotionAPIClientError.responseTooLarge(maximumBytes: maximumResponseBytes)
            }
            data.append(byte)
        }
        return (data, httpResponse)
    }
}

struct NotionAPIErrorDetails: Error, Equatable, Sendable {
    let statusCode: Int
    let code: String?
    let message: String?
    let requestID: String?
    let retryAfter: TimeInterval?

    init(
        statusCode: Int,
        code: String?,
        message: String?,
        requestID: String?,
        retryAfter: TimeInterval? = nil
    ) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
        self.requestID = requestID
        self.retryAfter = retryAfter
    }
}

enum NotionAPIClientError: Error, Equatable {
    case invalidResponse
    case unauthorized
    case accessDenied
    case requestFailed(statusCode: Int)
    case apiError(NotionAPIErrorDetails)
    case responseTooLarge(maximumBytes: Int)
    case malformedResponse
}

struct NotionConnectionSnapshot: Equatable, Sendable {
    let workspaceName: String
}

struct NotionPageSearchResult: Equatable, Sendable {
    let page: NotionPageReference
    let title: String
    let lastEditedTime: String
}

struct NotionDestinationSearchResult: Equatable, Sendable {
    let destination: QuickCaptureDestination
    let lastEditedTime: String
}

struct NotionDestinationSearchPage: Equatable, Sendable {
    let results: [NotionDestinationSearchResult]
    let nextCursor: String?
}

struct NotionDataSourceTitleProperty: Equatable, Sendable {
    let name: String
}

enum NotionPageParent: Equatable, Sendable {
    case pageID(String)
    case dataSourceID(String)
}

struct NotionCreatedPage: Equatable, Sendable {
    let id: String
    let url: URL?
}

protocol NotionCapturePageAPI: Sendable {
    func dataSourceTitleProperty(dataSourceID: String) async throws -> NotionDataSourceTitleProperty
    func createPage(
        parent: NotionPageParent,
        titlePropertyName: String,
        title: String,
        children: [JSONValue]
    ) async throws -> NotionCreatedPage
    func appendBlockChildren(pageID: String, children: [JSONValue]) async throws
}

final class NotionAPIClient: NotionWorkspaceClient, NotionCapturePageAPI, Sendable {
    static let apiVersion = "2026-03-11"
    static let defaultRequestTimeout: TimeInterval = 15
    static let defaultMaximumResponseBytes = 1_048_576

    private let token: PersonalIntegrationToken
    private let transport: any NotionRequestTransport
    private let requestTimeout: TimeInterval
    private let maximumResponseBytes: Int
    init(
        token: PersonalIntegrationToken,
        transport: any NotionRequestTransport = URLSessionNotionRequestTransport(),
        requestTimeout: TimeInterval = NotionAPIClient.defaultRequestTimeout,
        maximumResponseBytes: Int = NotionAPIClient.defaultMaximumResponseBytes
    ) {
        precondition(requestTimeout > 0)
        precondition(maximumResponseBytes > 0)
        self.token = token
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.maximumResponseBytes = maximumResponseBytes
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        let response: NotionUserResponseDTO = try await get(path: "/v1/users/me")
        let workspaceName = response.bot?.workspaceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return NotionConnectionSnapshot(
            workspaceName: workspaceName?.isEmpty == false
                ? workspaceName!
                : "Connected Notion workspace"
        )
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = NotionSearchRequestDTO(
            filter: .init(value: "page", property: "object"),
            sort: .init(direction: "descending", timestamp: "last_edited_time"),
            pageSize: 25,
            query: normalizedQuery.isEmpty ? nil : normalizedQuery,
            startCursor: nil
        )
        let response: NotionSearchResponseDTO = try await post(path: "/v1/search", body: body)
        return try response.results.compactMap(pageSearchResult)
    }

    func searchDestinations(
        query: String,
        startCursor: String?
    ) async throws -> NotionDestinationSearchPage {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = NotionSearchRequestDTO(
            filter: nil,
            sort: .init(direction: "descending", timestamp: "last_edited_time"),
            pageSize: 25,
            query: normalizedQuery.isEmpty ? nil : normalizedQuery,
            startCursor: startCursor
        )
        let response: NotionSearchResponseDTO = try await post(path: "/v1/search", body: body)
        let nextCursor: String?
        if response.hasMore {
            guard let cursor = response.nextCursor,
                  !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw NotionAPIClientError.malformedResponse
            }
            nextCursor = cursor
        } else {
            nextCursor = nil
        }
        return NotionDestinationSearchPage(
            results: try response.results.compactMap(destinationSearchResult),
            nextCursor: nextCursor
        )
    }

    func dataSourceTitleProperty(
        dataSourceID: String
    ) async throws -> NotionDataSourceTitleProperty {
        let response: NotionDataSourceResponseDTO = try await get(
            path: "/v1/data_sources/\(dataSourceID)"
        )
        guard let property = response.properties.first(where: { $0.value.type == "title" }) else {
            throw NotionAPIClientError.malformedResponse
        }
        return NotionDataSourceTitleProperty(name: property.key)
    }

    func createPage(
        parent: NotionPageParent,
        titlePropertyName: String,
        title: String,
        children: [JSONValue]
    ) async throws -> NotionCreatedPage {
        let response: NotionCreatedPageResponseDTO = try await post(
            path: "/v1/pages",
            body: NotionCreatePageRequestDTO(
                parent: .init(parent),
                properties: [
                    titlePropertyName: .init(
                        title: [
                            .init(
                                type: "text",
                                text: .init(content: title)
                            ),
                        ]
                    ),
                ],
                children: children
            )
        )
        return NotionCreatedPage(
            id: response.id,
            url: response.url.flatMap(URL.init(string:))
        )
    }

    func appendBlockChildren(pageID: String, children: [JSONValue]) async throws {
        let _: NotionAppendChildrenResponseDTO = try await patch(
            path: "/v1/blocks/\(pageID)/children",
            body: NotionAppendChildrenRequestDTO(children: children)
        )
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        try await request(path: path, method: "GET", body: nil)
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        try await request(path: path, method: "POST", body: try JSONEncoder().encode(body))
    }

    private func patch<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        try await request(path: path, method: "PATCH", body: try JSONEncoder().encode(body))
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: Data?
    ) async throws -> Response {
        guard let url = URL(string: "https://api.notion.com\(path)") else {
            throw NotionAPIClientError.invalidResponse
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= maximumResponseBytes else {
            throw NotionAPIClientError.responseTooLarge(maximumBytes: maximumResponseBytes)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw apiError(from: data, response: response)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch is DecodingError {
            throw NotionAPIClientError.malformedResponse
        }
    }

    private func apiError(from data: Data, response: HTTPURLResponse) -> NotionAPIClientError {
        guard let responseBody = try? JSONDecoder().decode(
            NotionAPIErrorResponseDTO.self,
            from: data
        ),
              responseBody.object == "error"
        else {
            switch response.statusCode {
            case 401:
                return .unauthorized
            case 403:
                return .accessDenied
            default:
                return .requestFailed(statusCode: response.statusCode)
            }
        }
        return .apiError(
            NotionAPIErrorDetails(
                statusCode: response.statusCode,
                code: responseBody.code,
                message: responseBody.message,
                requestID: responseBody.requestID,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(TimeInterval.init)
            )
        )
    }

    private func pageSearchResult(_ value: NotionSearchResultDTO) throws -> NotionPageSearchResult? {
        guard value.object == "page",
              let rawURL = value.url,
              let url = URL(string: rawURL)
        else {
            return nil
        }
        let page = try NotionPageReference(validating: url)
        let title = pageTitle(from: value) ?? page.displayTitle ?? "Untitled page"
        return NotionPageSearchResult(
            page: page,
            title: title,
            lastEditedTime: value.lastEditedTime ?? ""
        )
    }

    private func pageTitle(from value: NotionSearchResultDTO) -> String? {
        guard let properties = value.properties else { return nil }
        for property in properties.values where property.type == "title" {
            let title = (property.title ?? []).compactMap(\.plainText).joined()
            if !title.isEmpty {
                return title
            }
        }
        return nil
    }

    private func destinationSearchResult(
        _ value: NotionSearchResultDTO
    ) throws -> NotionDestinationSearchResult? {
        let title: String
        let destination: QuickCaptureDestination
        switch value.object {
        case "page":
            guard let id = value.id, !id.isEmpty else {
                throw NotionAPIClientError.malformedResponse
            }
            title = pageTitle(from: value) ?? "Untitled page"
            destination = .pageParent(pageID: id, title: title)
        case "data_source":
            guard let id = value.id, !id.isEmpty else {
                throw NotionAPIClientError.malformedResponse
            }
            let decodedTitle = (value.title ?? []).compactMap(\.plainText).joined()
            title = decodedTitle.isEmpty ? "Untitled data source" : decodedTitle
            destination = .dataSource(dataSourceID: id, title: title)
        default:
            return nil
        }
        return NotionDestinationSearchResult(
            destination: destination,
            lastEditedTime: value.lastEditedTime ?? ""
        )
    }
}

private struct NotionUserResponseDTO: Decodable {
    let bot: NotionBotDTO?
}

private struct NotionBotDTO: Decodable {
    let workspaceName: String?

    private enum CodingKeys: String, CodingKey {
        case workspaceName = "workspace_name"
    }
}

private struct NotionSearchRequestDTO: Encodable {
    let filter: Filter?
    let sort: Sort
    let pageSize: Int
    let query: String?
    let startCursor: String?

    struct Filter: Encodable {
        let value: String
        let property: String
    }

    struct Sort: Encodable {
        let direction: String
        let timestamp: String
    }

    private enum CodingKeys: String, CodingKey {
        case filter
        case sort
        case pageSize = "page_size"
        case query
        case startCursor = "start_cursor"
    }
}

private struct NotionSearchResponseDTO: Decodable {
    let results: [NotionSearchResultDTO]
    let hasMore: Bool
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct NotionSearchResultDTO: Decodable {
    let object: String
    let id: String?
    let url: String?
    let lastEditedTime: String?
    let properties: [String: NotionPropertyDTO]?
    let title: [NotionRichTextDTO]?

    private enum CodingKeys: String, CodingKey {
        case object
        case id
        case url
        case lastEditedTime = "last_edited_time"
        case properties
        case title
    }
}

private struct NotionPropertyDTO: Decodable {
    let type: String?
    let title: [NotionRichTextDTO]?
}

private struct NotionRichTextDTO: Decodable {
    let plainText: String?

    private enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

private struct NotionDataSourceResponseDTO: Decodable {
    let properties: [String: NotionDataSourcePropertyDTO]
}

private struct NotionDataSourcePropertyDTO: Decodable {
    let type: String
}

private struct NotionCreatePageRequestDTO: Encodable {
    let parent: Parent
    let properties: [String: TitleProperty]
    let children: [JSONValue]

    struct Parent: Encodable {
        let pageID: String?
        let dataSourceID: String?

        init(_ parent: NotionPageParent) {
            switch parent {
            case let .pageID(id):
                pageID = id
                dataSourceID = nil
            case let .dataSourceID(id):
                pageID = nil
                dataSourceID = id
            }
        }

        private enum CodingKeys: String, CodingKey {
            case pageID = "page_id"
            case dataSourceID = "data_source_id"
        }
    }

    struct TitleProperty: Encodable {
        let title: [RichText]
    }

    struct RichText: Encodable {
        let type: String
        let text: Text
    }

    struct Text: Encodable {
        let content: String
    }
}

private struct NotionCreatedPageResponseDTO: Decodable {
    let id: String
    let url: String?
}

private struct NotionAppendChildrenRequestDTO: Encodable {
    let children: [JSONValue]
}

private struct NotionAppendChildrenResponseDTO: Decodable {}

private struct NotionAPIErrorResponseDTO: Decodable {
    let object: String
    let code: String?
    let message: String?
    let requestID: String?

    private enum CodingKeys: String, CodingKey {
        case object
        case code
        case message
        case requestID = "request_id"
    }
}
