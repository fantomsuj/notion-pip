import Foundation

protocol NotionRequestTransport: AnyObject {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol NotionWorkspaceClient: AnyObject {
    func validateConnection() async throws -> NotionConnectionSnapshot
    func searchPages(query: String) async throws -> [NotionPageSearchResult]
}

final class URLSessionNotionRequestTransport: NotionRequestTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAPIClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

enum NotionAPIClientError: Error, Equatable {
    case invalidResponse
    case unauthorized
    case accessDenied
    case requestFailed(statusCode: Int)
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

    private let token: PersonalIntegrationToken
    private let transport: any NotionRequestTransport

    init(
        token: PersonalIntegrationToken,
        transport: any NotionRequestTransport = URLSessionNotionRequestTransport()
    ) {
        self.token = token
        self.transport = transport
    }

    func validateConnection() async throws -> NotionConnectionSnapshot {
        let response = try await request(path: "/v1/users/me")
        let bot = response["bot"] as? [String: Any]
        let workspaceName = (bot?["workspace_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return NotionConnectionSnapshot(
            workspaceName: workspaceName?.isEmpty == false ? workspaceName! : "Connected Notion workspace"
        )
    }

    func searchPages(query: String) async throws -> [NotionPageSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = [
            "filter": ["value": "page", "property": "object"],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"],
            "page_size": 25,
        ]
        if !normalizedQuery.isEmpty {
            body["query"] = normalizedQuery
        }
        let response = try await request(path: "/v1/search", method: "POST", body: body)
        guard let results = response["results"] as? [[String: Any]] else {
            throw NotionAPIClientError.malformedResponse
        }
        return try results.compactMap(pageSearchResult)
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.notion.com\(path)") else {
            throw NotionAPIClientError.invalidResponse
        }
        return try await request(url: url, method: method, body: body)
    }

    private func request(
        url: URL,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200 ..< 300:
            break
        case 401:
            throw NotionAPIClientError.unauthorized
        case 403:
            throw NotionAPIClientError.accessDenied
        default:
            throw NotionAPIClientError.requestFailed(statusCode: response.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionAPIClientError.malformedResponse
        }
        return json
    }

    private func pageSearchResult(_ value: [String: Any]) throws -> NotionPageSearchResult? {
        guard value["object"] as? String == "page",
              let rawURL = value["url"] as? String,
              let url = URL(string: rawURL)
        else {
            return nil
        }
        let page = try NotionPageReference(validating: url)
        let title = pageTitle(from: value) ?? page.displayTitle ?? "Untitled page"
        return NotionPageSearchResult(
            page: page,
            title: title,
            lastEditedTime: value["last_edited_time"] as? String ?? ""
        )
    }

    private func pageTitle(from value: [String: Any]) -> String? {
        guard let properties = value["properties"] as? [String: Any] else {
            return nil
        }
        for property in properties.values {
            guard let titleProperty = property as? [String: Any],
                  titleProperty["type"] as? String == "title",
                  let richText = titleProperty["title"] as? [[String: Any]]
            else {
                continue
            }
            let title = richText.compactMap { $0["plain_text"] as? String }.joined()
            if !title.isEmpty {
                return title
            }
        }
        return nil
    }

}
