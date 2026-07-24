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
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
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
        let requests = await transport.requests
        let body = try XCTUnwrap(requests.first?.httpBody)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("roadmap"))
    }

    func testDestinationSearchDecodesPagesAndDataSourcesAcrossPagination() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("""
            {
              "object":"list", "has_more":true, "next_cursor":"cursor-2",
              "results":[
                {
                  "object":"page",
                  "id":"0123456789abcdef0123456789abcdef",
                  "url":"https://www.notion.so/Inbox-0123456789abcdef0123456789abcdef",
                  "last_edited_time":"2026-07-21T10:00:00.000Z",
                  "properties":{"title":{"type":"title","title":[{"plain_text":"Inbox"}]}}
                },
                {
                  "object":"data_source",
                  "id":"source-1",
                  "last_edited_time":"2026-07-20T10:00:00.000Z",
                  "title":[{"plain_text":"Notes"}]
                }
              ]
            }
            """),
            jsonResponse("""
            {
              "object":"list", "has_more":false, "next_cursor":null,
              "results":[
                {
                  "object":"data_source",
                  "id":"source-2",
                  "last_edited_time":"2026-07-19T10:00:00.000Z",
                  "title":[{"plain_text":"Journal"}]
                }
              ]
            }
            """),
        ])
        let client = makeClient(transport: transport)

        let results = try await client.searchDestinations(query: "notes")

        XCTAssertEqual(results.map(\.destination), [
            .pageParent(pageID: "0123456789abcdef0123456789abcdef", title: "Inbox"),
            .dataSource(dataSourceID: "source-1", title: "Notes"),
            .dataSource(dataSourceID: "source-2", title: "Journal"),
        ])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let firstBody = try jsonObject(for: requests[0])
        let secondBody = try jsonObject(for: requests[1])
        XCTAssertNil(firstBody["filter"])
        XCTAssertEqual(firstBody["query"] as? String, "notes")
        XCTAssertEqual(secondBody["start_cursor"] as? String, "cursor-2")
    }

    func testRetrievesDataSourceTitleProperty() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse("""
            {
              "object":"data_source",
              "id":"source-1",
              "title":[{"plain_text":"Notes"}],
              "properties":{
                "Name":{"id":"title","name":"Name","type":"title","title":{}},
                "Status":{"id":"status","name":"Status","type":"status","status":{}}
              }
            }
            """)
        ])
        let client = makeClient(transport: transport)

        let property = try await client.dataSourceTitleProperty(dataSourceID: "source-1")

        XCTAssertEqual(property, NotionDataSourceTitleProperty(name: "Name"))
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.path, "/v1/data_sources/source-1")
    }

    func testCreatesPagesWithParentSpecificRequestBodies() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse(#"{"object":"page","id":"created-page-1","url":"https://www.notion.so/created-page-1"}"#),
            jsonResponse(#"{"object":"page","id":"created-page-2","url":"https://www.notion.so/created-page-2"}"#),
        ])
        let client = makeClient(transport: transport)

        _ = try await client.createPage(
            parent: .pageID("page-1"),
            titlePropertyName: "title",
            title: "Child note",
            children: []
        )
        _ = try await client.createPage(
            parent: .dataSourceID("source-1"),
            titlePropertyName: "Name",
            title: "Database note",
            children: []
        )

        let requests = await transport.requests
        let pageBody = try jsonObject(for: requests[0])
        let dataSourceBody = try jsonObject(for: requests[1])
        XCTAssertEqual((pageBody["parent"] as? [String: Any])?["page_id"] as? String, "page-1")
        XCTAssertEqual(
            (dataSourceBody["parent"] as? [String: Any])?["data_source_id"] as? String,
            "source-1"
        )
        XCTAssertNotNil((pageBody["properties"] as? [String: Any])?["title"])
        XCTAssertNotNil((dataSourceBody["properties"] as? [String: Any])?["Name"])
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(requests.map(\.url?.path), ["/v1/pages", "/v1/pages"])
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
                statusCode: 429,
                headerFields: ["Retry-After": "7"]
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
                        requestID: "request-123",
                        retryAfter: 7
                    )
                )
            )
        }
    }

    func testMapsUnstructuredAuthorizationAndNotFoundErrors() async throws {
        let fixtures: [(Int, NotionAPIClientError)] = [
            (401, .unauthorized),
            (403, .accessDenied),
            (404, .requestFailed(statusCode: 404)),
        ]

        for (statusCode, expectedError) in fixtures {
            let transport = RecordingNotionTransport(responses: [
                jsonResponse("{}", statusCode: statusCode)
            ])
            let client = makeClient(transport: transport)

            do {
                _ = try await client.validateConnection()
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch {
                XCTAssertEqual(error as? NotionAPIClientError, expectedError)
            }
        }
    }

    func testRejectsMalformedDestinationSearchResponse() async throws {
        let transport = RecordingNotionTransport(responses: [
            jsonResponse(#"{"object":"list","results":"not-an-array"}"#)
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.searchDestinations(query: "")
            XCTFail("Expected malformed search response to fail")
        } catch {
            XCTAssertEqual(error as? NotionAPIClientError, .malformedResponse)
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

    private func makeClient(transport: RecordingNotionTransport) -> NotionAPIClient {
        NotionAPIClient(
            token: try! PersonalIntegrationToken(validating: "ntn_1234567890abcdef"),
            transport: transport
        )
    }

    private func jsonObject(for request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
    }
}

private actor RecordingNotionTransport: NotionRequestTransport {
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
    statusCode: Int = 200,
    headerFields: [String: String]? = nil
) -> (Data, HTTPURLResponse) {
    let url = URL(string: "https://api.notion.com")!
    return (
        Data(json.utf8),
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headerFields
        )!
    )
}
