import Foundation
import XCTest
@testable import NotionPiP

final class NotionAPIClientTests: XCTestCase {
    func testConnectionValidationUsesCurrentNotionVersionAndReturnsWorkspaceName() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("""
            {"object":"user","type":"bot","bot":{"workspace_name":"Personal Workspace"}}
            """)
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )

        let connection = try await client.validateConnection()

        XCTAssertEqual(connection.workspaceName, "Personal Workspace")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/users/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ntn_1234567890abcdef")
    }

    func testSearchReturnsOnlyAccessibleNotionPages() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("""
            {
              "object":"list", "has_more":false, "next_cursor":null,
              "results":[
                {
                  "object":"page", "id":"0123456789abcdef0123456789abcdef",
                  "url":"https://www.notion.so/Project-Roadmap-0123456789abcdef0123456789abcdef",
                  "last_edited_time":"2026-07-21T10:00:00.000Z",
                  "properties":{"title":{"type":"title","title":[{"plain_text":"Project Roadmap"}]}}
                },
                {"object":"data_source", "id":"ignored"}
              ]
            }
            """)
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )

        let pages = try await client.searchPages(query: "roadmap")

        XCTAssertEqual(pages.map(\.title), ["Project Roadmap"])
        XCTAssertEqual(pages.first?.page.pageID, "0123456789abcdef0123456789abcdef")
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("roadmap"))
    }

    func testFetchPagePreviewUsesReadOnlyRequestsAndRetainsUnsupportedBlocks() async throws {
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Project-0123456789abcdef0123456789abcdef"))
        )
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("""
            {
              "object":"page", "last_edited_time":"2026-07-21T10:00:00.000Z",
              "properties":{"title":{"type":"title","title":[{"plain_text":"Project brief"}]}}
            }
            """),
            jsonResponse("""
            {
              "object":"list", "has_more":false, "next_cursor":null,
              "results":[
                {"object":"block","id":"block-1","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Hello"}]}},
                {"object":"block","id":"block-2","type":"to_do","to_do":{"rich_text":[{"plain_text":"Ship it"}],"checked":true}},
                {"object":"block","id":"block-3","type":"image","image":{}}
              ]
            }
            """)
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )

        let snapshot = try await client.fetchPagePreview(page: page)

        XCTAssertEqual(snapshot.title, "Project brief")
        XCTAssertEqual(snapshot.remoteFingerprint, "2026-07-21T10:00:00.000Z")
        XCTAssertEqual(snapshot.blocks, [
            NativePageBlock(id: "block-1", kind: .paragraph, text: "Hello"),
            NativePageBlock(id: "block-2", kind: .toDo, text: "Ship it", checked: true),
            NativePageBlock(id: "block-3", kind: .image),
        ])
        XCTAssertEqual(transport.requests.map(\.url?.path), [
            "/v1/pages/0123456789abcdef0123456789abcdef",
            "/v1/blocks/0123456789abcdef0123456789abcdef/children",
        ])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testFetchPagePreviewFollowsOpaqueCursorsAndPreservesTopLevelBlockOrder() async throws {
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Project-0123456789abcdef0123456789abcdef"))
        )
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("""
            {"object":"page","properties":{"title":{"type":"title","title":[{"plain_text":"Project"}]}}}
            """),
            jsonResponse("""
            {
              "object":"list", "has_more":true, "next_cursor":"cursor/with?opaque=value",
              "results":[
                {"object":"block","id":"block-1","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"First"}]}},
                {"object":"block","id":"block-2","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Second"}]}}
              ]
            }
            """),
            jsonResponse("""
            {
              "object":"list", "has_more":false, "next_cursor":null,
              "results":[
                {"object":"block","id":"block-3","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Third"}]}}
              ]
            }
            """)
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )

        let snapshot = try await client.fetchPagePreview(page: page)

        XCTAssertEqual(snapshot.blocks.map(\.id), ["block-1", "block-2", "block-3"])
        XCTAssertEqual(transport.requests.count, 3)
        let firstChildrenRequest = try XCTUnwrap(transport.requests[safe: 1])
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(firstChildrenRequest.url), resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "page_size", value: "100"),
        ])
        let secondChildrenRequest = try XCTUnwrap(transport.requests[safe: 2])
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(secondChildrenRequest.url), resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "page_size", value: "100"),
            URLQueryItem(name: "start_cursor", value: "cursor/with?opaque=value"),
        ])
    }

    func testFetchPagePreviewMarksNestedAndUnsupportedBlocksAsPreviewOnly() async throws {
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Project-0123456789abcdef0123456789abcdef"))
        )
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("{\"object\":\"page\",\"properties\":{}}"),
            jsonResponse("""
            {
              "object":"list", "has_more":false, "next_cursor":null,
              "results":[
                {"object":"block","id":"nested","type":"paragraph","has_children":true,"paragraph":{"rich_text":[{"plain_text":"Parent"}]}},
                {"object":"block","id":"unsupported","type":"table","table":{}}
              ]
            }
            """)
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )

        let snapshot = try await client.fetchPagePreview(page: page)

        XCTAssertEqual(snapshot.blocks, [
            NativePageBlock(id: "nested", kind: .unsupported("paragraph"), text: "Parent"),
            NativePageBlock(id: "unsupported", kind: .unsupported("table")),
        ])
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class RecordingNotionTransport: NotionRequestTransport {
    private var responses: [(Data, HTTPURLResponse)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return responses.removeFirst()
    }
}

private func jsonResponse(
    _ json: String,
    statusCode: Int = 200
) -> (Data, HTTPURLResponse) {
    let url = URL(string: "https://api.notion.com")!
    return (
        Data(json.utf8),
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    )
}
