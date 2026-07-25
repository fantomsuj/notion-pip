import Foundation
import XCTest
@testable import NotionPiP

final class NotionCaptureDeliveryServiceTests: XCTestCase {
    func testCreatesOnceThenPersistsProgressBeforeEachRemainingBatch() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let record = try await seedRecord(repository, paragraphCount: 201)
        let api = RecordingCaptureAPI(repository: repository, recordID: record.id)
        let service = NotionCaptureDeliveryService(
            repository: repository,
            api: api
        )

        let receipt = try await service.createChildPage(record, parentPageID: "parent-1")

        XCTAssertEqual(receipt.remoteIdentity, "remote-page")
        let calls = await api.calls
        XCTAssertEqual(calls, [
            .create(parent: .pageID("parent-1"), titleProperty: "title", title: "Capture", childCount: 100),
            .append(pageID: "remote-page", childCount: 100),
            .append(pageID: "remote-page", childCount: 1),
        ])
        let observedJournalIndexes = await api.journalIndexesObservedBeforeAppend
        XCTAssertEqual(observedJournalIndexes, [1, 2])
        let stored = try await repository.record(id: record.id)
        XCTAssertEqual(try journalIndex(stored?.operationJournal), 3)
    }

    func testRetryResumesCreatedPageAfterCompletedAppendProgress() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let record = try await seedRecord(repository, paragraphCount: 201)
        let api = RecordingCaptureAPI(
            repository: repository,
            recordID: record.id,
            failAppendCall: 2
        )
        let service = NotionCaptureDeliveryService(repository: repository, api: api)

        do {
            _ = try await service.createChildPage(record, parentPageID: "parent-1")
            XCTFail("Expected the second append to fail")
        } catch {
            XCTAssertEqual(
                error as? DeliveryTransportError,
                .http(status: 429, retryAfter: 5, message: "Slow down")
            )
        }

        let partiallyDelivered = try await repository.record(id: record.id)
        XCTAssertEqual(try journalIndex(partiallyDelivered?.operationJournal), 2)
        await api.allowAppends()

        _ = try await service.createChildPage(
            try XCTUnwrap(partiallyDelivered),
            parentPageID: "parent-1"
        )

        let calls = await api.calls
        XCTAssertEqual(calls.filter(\.isCreate).count, 1)
        XCTAssertEqual(calls.last, .append(pageID: "remote-page", childCount: 1))
    }

    func testDataSourceDeliveryUsesSchemaTitlePropertyAndUntitledFallback() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let record = try await seedRecord(
            repository,
            paragraphCount: 1,
            title: "  ",
            destination: .dataSource(dataSourceID: "source-1")
        )
        let api = RecordingCaptureAPI(repository: repository, recordID: record.id)
        let service = NotionCaptureDeliveryService(repository: repository, api: api)

        _ = try await service.createDataSourcePage(record, dataSourceID: "source-1")

        let calls = await api.calls
        XCTAssertEqual(
            calls.first,
            .create(
                parent: .dataSourceID("source-1"),
                titleProperty: "Name",
                title: "Untitled",
                childCount: 1
            )
        )
    }

    func testUnknownCreateOutcomeBecomesUncertainWithoutSecondCreate() async throws {
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 10_000))
        let repository = try CaptureRepository(inMemory: true, clock: clock)
        _ = try await seedRecord(repository, paragraphCount: 1)
        let api = RecordingCaptureAPI(
            repository: repository,
            recordID: "capture-1",
            failCreateAmbiguously: true
        )
        let service = NotionCaptureDeliveryService(repository: repository, api: api)
        let engine = DeliveryEngine(repository: repository, transport: service, clock: clock)

        _ = try await engine.drain()
        _ = try await engine.drain()

        let stored = try await repository.record(id: "capture-1")
        let createCallCount = await api.calls.filter(\.isCreate).count
        XCTAssertEqual(stored?.state, .uncertain)
        XCTAssertEqual(createCallCount, 1)
        XCTAssertEqual(stored?.safeError?.code, "ambiguousPageCreation")
        XCTAssertEqual(
            stored?.safeError?.message,
            "Notion may have created this capture. Open the local copy to recover without creating a duplicate."
        )
    }

    private func seedRecord(
        _ repository: CaptureRepository,
        paragraphCount: Int,
        title: String = "Capture",
        destination: CaptureDestination = .pageParent(pageID: "parent-1")
    ) async throws -> CaptureRecordSnapshot {
        let document = jsonData([
            "type": "doc",
            "content": (0 ..< paragraphCount).map { index in
                [
                    "type": "paragraph",
                    "content": [["type": "text", "text": "Paragraph \(index)"]],
                ]
            },
        ])
        let draft = try await repository.saveDraft(
            DraftMutation(
                id: "capture-1",
                title: title,
                editorDocument: document,
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        return try await repository.enqueue(
            draftID: draft.id,
            expectedRevision: draft.revision,
            destination: destination
        )
    }

    private func journalIndex(_ data: Data?) throws -> Int {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any]
        )
        return try XCTUnwrap(object["nextBatchIndex"] as? Int)
    }
}

private enum CaptureAPICall: Equatable, Sendable {
    case create(
        parent: NotionPageParent,
        titleProperty: String,
        title: String,
        childCount: Int
    )
    case append(pageID: String, childCount: Int)

    var isCreate: Bool {
        if case .create = self { true } else { false }
    }
}

private actor RecordingCaptureAPI: NotionCapturePageAPI {
    private let repository: CaptureRepository
    private let recordID: String
    private var failAppendCall: Int?
    private let failCreateAmbiguously: Bool
    private var appendCount = 0
    private(set) var calls: [CaptureAPICall] = []
    private(set) var journalIndexesObservedBeforeAppend: [Int] = []

    init(
        repository: CaptureRepository,
        recordID: String,
        failAppendCall: Int? = nil,
        failCreateAmbiguously: Bool = false
    ) {
        self.repository = repository
        self.recordID = recordID
        self.failAppendCall = failAppendCall
        self.failCreateAmbiguously = failCreateAmbiguously
    }

    func dataSourceTitleProperty(
        dataSourceID: String
    ) async throws -> NotionDataSourceTitleProperty {
        NotionDataSourceTitleProperty(name: "Name")
    }

    func createPage(
        parent: NotionPageParent,
        titlePropertyName: String,
        title: String,
        children: [JSONValue]
    ) async throws -> NotionCreatedPage {
        calls.append(
            .create(
                parent: parent,
                titleProperty: titlePropertyName,
                title: title,
                childCount: children.count
            )
        )
        if failCreateAmbiguously {
            throw URLError(.networkConnectionLost)
        }
        return NotionCreatedPage(
            id: "remote-page",
            url: URL(string: "https://www.notion.so/remote-page")
        )
    }

    func appendBlockChildren(pageID: String, children: [JSONValue]) async throws {
        let record = try await repository.record(id: recordID)
        let object = try JSONSerialization.jsonObject(
            with: XCTUnwrap(record?.operationJournal)
        ) as? [String: Any]
        journalIndexesObservedBeforeAppend.append(object?["nextBatchIndex"] as? Int ?? -1)
        appendCount += 1
        calls.append(.append(pageID: pageID, childCount: children.count))
        if appendCount == failAppendCall {
            throw NotionAPIClientError.apiError(
                NotionAPIErrorDetails(
                    statusCode: 429,
                    code: "rate_limited",
                    message: "Slow down",
                    requestID: "request-1",
                    retryAfter: 5
                )
            )
        }
    }

    func allowAppends() {
        failAppendCall = nil
    }
}
