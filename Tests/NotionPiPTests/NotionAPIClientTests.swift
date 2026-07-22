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
