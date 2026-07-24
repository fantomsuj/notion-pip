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
        XCTAssertEqual(request.timeoutInterval, 15)
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

    func testRejectsResponseBodyOverConfiguredLimit() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse(#"{"object":"user","padding":"too large"}"#)
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport,
            maximumResponseBytes: 16
        )

        do {
            _ = try await client.validateConnection()
            XCTFail("Expected an oversized response to be rejected")
        } catch {
            XCTAssertEqual(error as? NotionAPIClientError, .responseTooLarge(maximumBytes: 16))
        }
    }

    func testDecodesStructuredNotionAPIError() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse(
                """
                {
                  "object":"error",
                  "status":429,
                  "code":"rate_limited",
                  "message":"Slow down",
                  "request_id":"request-123"
                }
                """,
                statusCode: 429
            )
        ])
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )

        do {
            _ = try await client.validateConnection()
            XCTFail("Expected a structured API error")
        } catch {
            XCTAssertEqual(
                error as? NotionAPIClientError,
                .apiError(
                    NotionAPIErrorDetails(
                        statusCode: 429,
                        code: "rate_limited",
                        message: "Slow down",
                        requestID: "request-123"
                    )
                )
            )
        }
    }

    func testCancellationPropagatesToTransport() async throws {
        let transport = SuspendingNotionTransport()
        let client = NotionAPIClient(
            token: try PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )
        let request = Task {
            try await client.validateConnection()
        }

        await transport.waitUntilStarted()
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testDefaultTransportHasFiniteRequestAndResourceDeadlines() {
        let transport = URLSessionNotionRequestTransport()

        XCTAssertEqual(transport.requestTimeout, 15)
        XCTAssertEqual(transport.resourceTimeout, 30)
        XCTAssertEqual(transport.maximumResponseBytes, 1_048_576)
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

private actor SuspendingNotionTransport: NotionRequestTransport {
    private var started = false

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        started = true
        try await Task.sleep(for: .seconds(60))
        return jsonResponse("{}")
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
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
