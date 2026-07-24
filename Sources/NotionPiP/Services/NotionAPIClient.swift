import Foundation

protocol NotionRequestTransport: AnyObject {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol NotionWorkspaceClient: AnyObject {
    func validateConnection() async throws -> NotionConnectionSnapshot
    func searchPages(query: String) async throws -> [NotionPageSearchResult]
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

final class NotionAPIClient: NotionWorkspaceClient {
    static let apiVersion = "2026-03-11"
    static let defaultRequestTimeout: TimeInterval = 15
    static let defaultMaximumResponseBytes = 1_048_576

    private let token: PersonalIntegrationToken
    private let transport: any NotionRequestTransport
    private let requestTimeout: TimeInterval
    private let maximumResponseBytes: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
            query: normalizedQuery.isEmpty ? nil : normalizedQuery
        )
        let response: NotionSearchResponseDTO = try await post(path: "/v1/search", body: body)
        return try response.results.compactMap(pageSearchResult)
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        try await request(path: path, method: "GET", body: nil)
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        try await request(path: path, method: "POST", body: try encoder.encode(body))
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
            return try decoder.decode(Response.self, from: data)
        } catch is DecodingError {
            throw NotionAPIClientError.malformedResponse
        }
    }

    private func apiError(from data: Data, response: HTTPURLResponse) -> NotionAPIClientError {
        guard let responseBody = try? decoder.decode(NotionAPIErrorResponseDTO.self, from: data),
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
                requestID: responseBody.requestID
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
    let filter: Filter
    let sort: Sort
    let pageSize: Int
    let query: String?

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
    }
}

private struct NotionSearchResponseDTO: Decodable {
    let results: [NotionSearchResultDTO]
}

private struct NotionSearchResultDTO: Decodable {
    let object: String
    let url: String?
    let lastEditedTime: String?
    let properties: [String: NotionPropertyDTO]?

    private enum CodingKeys: String, CodingKey {
        case object
        case url
        case lastEditedTime = "last_edited_time"
        case properties
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
