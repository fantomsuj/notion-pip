import Foundation

private struct CaptureDeliveryJournal: Codable, Equatable, Sendable {
    let stage: String
    let pageID: String
    let titlePropertyName: String
    let nextBatchIndex: Int
    let totalBatchCount: Int

    init(
        pageID: String,
        titlePropertyName: String,
        nextBatchIndex: Int,
        totalBatchCount: Int
    ) {
        stage = "captureDelivery"
        self.pageID = pageID
        self.titlePropertyName = titlePropertyName
        self.nextBatchIndex = nextBatchIndex
        self.totalBatchCount = totalBatchCount
    }
}

actor NotionCaptureDeliveryService: CaptureDeliveryTransport {
    private let repository: any CaptureDeliveryJournaling
    private let api: any NotionCapturePageAPI
    private let converter: NotionBlockConverter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        repository: any CaptureDeliveryJournaling,
        api: any NotionCapturePageAPI,
        converter: NotionBlockConverter = NotionBlockConverter()
    ) {
        self.repository = repository
        self.api = api
        self.converter = converter
    }

    func createChildPage(
        _ record: CaptureRecordSnapshot,
        parentPageID: String
    ) async throws -> DeliveryReceipt {
        try await deliver(
            record,
            parent: .pageID(parentPageID),
            titlePropertyName: "title"
        )
    }

    func createDataSourcePage(
        _ record: CaptureRecordSnapshot,
        dataSourceID: String
    ) async throws -> DeliveryReceipt {
        let existingJournal = try journal(from: record.operationJournal)
        let titlePropertyName: String
        if let existingJournal {
            titlePropertyName = existingJournal.titlePropertyName
        } else {
            do {
                titlePropertyName = try await api
                    .dataSourceTitleProperty(dataSourceID: dataSourceID)
                    .name
            } catch {
                throw map(error, ambiguousByDefault: false)
            }
        }
        return try await deliver(
            record,
            parent: .dataSourceID(dataSourceID),
            titlePropertyName: titlePropertyName
        )
    }

    func findManagedCapture(
        captureID: String,
        databaseID: String
    ) async throws -> DeliveryReceipt? {
        throw DeliveryTransportError.transport(
            message: "Legacy managed delivery is unavailable."
        )
    }

    func createManaged(
        _ record: CaptureRecordSnapshot,
        databaseID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(
            message: "Legacy managed delivery is unavailable."
        )
    }

    func appendManual(
        _ record: CaptureRecordSnapshot,
        pageID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(
            message: "Legacy append delivery is unavailable."
        )
    }

    private func deliver(
        _ record: CaptureRecordSnapshot,
        parent: NotionPageParent,
        titlePropertyName: String
    ) async throws -> DeliveryReceipt {
        let conversion: NotionBlockConversion
        do {
            conversion = try converter.convert(record.editorDocument)
        } catch {
            throw DeliveryTransportError.transport(
                message: "The local capture document is malformed."
            )
        }
        let batches = conversion.batches
        var journal = try journal(from: record.operationJournal)

        if journal == nil {
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let createdPage: NotionCreatedPage
            do {
                createdPage = try await api.createPage(
                    parent: parent,
                    titlePropertyName: titlePropertyName,
                    title: title.isEmpty ? "Untitled" : title,
                    children: batches.first ?? []
                )
            } catch {
                throw map(error, ambiguousByDefault: true)
            }
            journal = CaptureDeliveryJournal(
                pageID: createdPage.id,
                titlePropertyName: titlePropertyName,
                nextBatchIndex: batches.isEmpty ? 0 : 1,
                totalBatchCount: batches.count
            )
            do {
                try await persist(journal!, recordID: record.id)
            } catch {
                throw DeliveryTransportError.ambiguous(
                    message: "The page was created but local progress could not be saved."
                )
            }
        }

        guard var journal else {
            throw DeliveryTransportError.transport(message: "Missing delivery journal.")
        }
        guard journal.totalBatchCount == batches.count,
              journal.nextBatchIndex <= batches.count
        else {
            throw DeliveryTransportError.ambiguous(
                message: "Delivery progress does not match the local capture."
            )
        }

        while journal.nextBatchIndex < batches.count {
            let batchIndex = journal.nextBatchIndex
            do {
                try await api.appendBlockChildren(
                    pageID: journal.pageID,
                    children: batches[batchIndex]
                )
            } catch {
                throw map(error, ambiguousByDefault: true)
            }
            journal = CaptureDeliveryJournal(
                pageID: journal.pageID,
                titlePropertyName: journal.titlePropertyName,
                nextBatchIndex: batchIndex + 1,
                totalBatchCount: journal.totalBatchCount
            )
            do {
                try await persist(journal, recordID: record.id)
            } catch {
                throw DeliveryTransportError.ambiguous(
                    message: "Blocks were appended but local progress could not be saved."
                )
            }
        }
        return DeliveryReceipt(remoteIdentity: journal.pageID, fingerprint: nil)
    }

    private func journal(from data: Data?) throws -> CaptureDeliveryJournal? {
        guard let data else { return nil }
        guard let journal = try? decoder.decode(CaptureDeliveryJournal.self, from: data),
              journal.stage == "captureDelivery"
        else {
            throw DeliveryTransportError.ambiguous(
                message: "Another unresolved operation is recorded for this capture."
            )
        }
        return journal
    }

    private func persist(
        _ journal: CaptureDeliveryJournal,
        recordID: String
    ) async throws {
        _ = try await repository.updateDeliveryJournal(
            recordID: recordID,
            journal: try encoder.encode(journal)
        )
    }

    private func map(
        _ error: Error,
        ambiguousByDefault: Bool
    ) -> DeliveryTransportError {
        if let error = error as? DeliveryTransportError {
            return error
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return .retryable(message: "The network is unavailable.")
            default:
                return ambiguousByDefault
                    ? .ambiguous(message: nil)
                    : .transport(message: nil)
            }
        }
        guard let error = error as? NotionAPIClientError else {
            return ambiguousByDefault
                ? .ambiguous(message: nil)
                : .transport(message: nil)
        }
        switch error {
        case .unauthorized:
            return .http(status: 401, retryAfter: nil, message: nil)
        case .accessDenied:
            return .http(status: 403, retryAfter: nil, message: nil)
        case let .requestFailed(statusCode):
            if ambiguousByDefault, (500 ... 599).contains(statusCode) {
                return .ambiguous(message: nil)
            }
            return .http(status: statusCode, retryAfter: nil, message: nil)
        case let .apiError(details):
            if ambiguousByDefault, (500 ... 599).contains(details.statusCode) {
                return .ambiguous(message: nil)
            }
            return .http(
                status: details.statusCode,
                retryAfter: details.retryAfter,
                message: details.message
            )
        case .invalidResponse, .responseTooLarge, .malformedResponse:
            return ambiguousByDefault
                ? .ambiguous(message: nil)
                : .transport(message: nil)
        }
    }
}
