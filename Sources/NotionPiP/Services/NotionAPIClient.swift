import Foundation

protocol NotionRequestTransport: AnyObject {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol NotionWorkspaceClient: AnyObject {
    func validateConnection() async throws -> NotionConnectionSnapshot
    func searchPages(query: String) async throws -> [NotionPageSearchResult]
    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot
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

    func fetchPagePreview(page: NotionPageReference) async throws -> NativePageSnapshot {
        let pagePayload = try await request(path: "/v1/pages/\(page.pageID)")
        var blocks: [NativePageBlock] = []
        var cursor: String?

        while true {
            let childrenPayload = try await request(url: childrenURL(pageID: page.pageID, cursor: cursor))
            guard let results = childrenPayload["results"] as? [[String: Any]] else {
                throw NotionAPIClientError.malformedResponse
            }
            blocks.append(contentsOf: try results.compactMap(notionBlock))

            guard childrenPayload["has_more"] as? Bool == true else {
                break
            }
            guard let nextCursor = childrenPayload["next_cursor"] as? String, !nextCursor.isEmpty else {
                throw NotionAPIClientError.malformedResponse
            }
            cursor = nextCursor
        }

        return NativePageSnapshot(
            pageID: page.pageID,
            title: pageTitle(from: pagePayload) ?? page.displayTitle ?? "Untitled page",
            blocks: blocks,
            remoteFingerprint: pagePayload["last_edited_time"] as? String ?? "",
            fetchedAt: Date()
        )
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

    private func childrenURL(pageID: String, cursor: String?) throws -> URL {
        guard var components = URLComponents(string: "https://api.notion.com/v1/blocks/\(pageID)/children") else {
            throw NotionAPIClientError.invalidResponse
        }
        var queryItems = [URLQueryItem(name: "page_size", value: "100")]
        if let cursor {
            queryItems.append(URLQueryItem(name: "start_cursor", value: cursor))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NotionAPIClientError.invalidResponse
        }
        return url
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

    private func notionBlock(_ value: [String: Any]) throws -> NativePageBlock? {
        guard let id = value["id"] as? String, let type = value["type"] as? String else {
            return nil
        }
        let attributes = value[type] as? [String: Any]
        let text = richText(from: attributes?["rich_text"])
        let kind: NotionBlockKind
        if value["has_children"] as? Bool == true {
            // Nested content is deliberately not flattened into this read-only preview.
            kind = .unsupported(type)
        } else {
            switch type {
            case "paragraph": kind = .paragraph
            case "heading_1": kind = .heading(level: 1)
            case "heading_2": kind = .heading(level: 2)
            case "heading_3": kind = .heading(level: 3)
            case "bulleted_list_item": kind = .bulletedList
            case "numbered_list_item": kind = .numberedList
            case "to_do": kind = .toDo
            case "quote": kind = .quote
            case "toggle": kind = .toggle
            case "code": kind = .code
            case "divider": kind = .divider
            case "image": kind = .image
            default: kind = .unsupported(type)
            }
        }
        return NativePageBlock(
            id: id,
            kind: kind,
            text: text,
            checked: attributes?["checked"] as? Bool ?? false
        )
    }

    private func richText(from value: Any?) -> String {
        guard let items = value as? [[String: Any]] else {
            return ""
        }
        return items.compactMap { $0["plain_text"] as? String }.joined()
    }

}
