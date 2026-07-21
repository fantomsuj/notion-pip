import Foundation
import SwiftData

enum CaptureRepositoryError: Error, Equatable {
    case invalidIdentifier
    case invalidJSON
    case draftNotFound(String)
    case recordNotFound(String)
    case staleRevision(expected: Int, actual: Int)
    case enqueueDestinationMismatch
    case invalidDraftTransition(from: DraftDisposition, to: DraftDisposition)
    case abandonedDraftImmutable
    case invalidNewDraftDisposition(DraftDisposition)
    case invalidStoredValue(String)
}

enum CaptureRepositoryHelperFetch: Equatable, Sendable {
    case activeDraft
    case otherActiveDrafts
    case returnDraft
}

typealias CaptureRepositoryHelperFetchCheck = @Sendable (CaptureRepositoryHelperFetch) throws -> Void

actor CaptureRepository {
    private let container: ModelContainer
    private let context: ModelContext
    private let clock: any CaptureClock
    private let beforeHelperFetch: CaptureRepositoryHelperFetchCheck

    init(
        storeURL: URL? = nil,
        inMemory: Bool = false,
        clock: any CaptureClock = SystemCaptureClock(),
        beforeHelperFetch: @escaping CaptureRepositoryHelperFetchCheck = { _ in }
    ) throws {
        let schema = Schema(versionedSchema: NotionPiPSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        container = try ModelContainer(
            for: schema,
            migrationPlan: NotionPiPMigrationPlan.self,
            configurations: configuration
        )
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.clock = clock
        self.beforeHelperFetch = beforeHelperFetch
    }

    func saveDraft(_ mutation: DraftMutation, expectedRevision: Int) throws -> CaptureDraftSnapshot {
        guard !mutation.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureRepositoryError.invalidIdentifier
        }
        let canonicalEditor: Data
        let canonicalSource: Data?
        do {
            canonicalEditor = try CanonicalJSON.canonicalize(mutation.editorDocument)
            canonicalSource = try mutation.sourceDocument.map(CanonicalJSON.canonicalize)
        } catch {
            throw CaptureRepositoryError.invalidJSON
        }

        let now = clock.now()
        if let model = try draftModel(id: mutation.id) {
            if expectedRevision != model.revision {
                if expectedRevision == model.revision - 1,
                   draftMatches(
                       model,
                       mutation: mutation,
                       canonicalEditor: canonicalEditor,
                       canonicalSource: canonicalSource
                   ) {
                    return try snapshot(model)
                }
                throw CaptureRepositoryError.staleRevision(expected: expectedRevision, actual: model.revision)
            }

            guard let currentDisposition = DraftDisposition(rawValue: model.dispositionRawValue) else {
                throw CaptureRepositoryError.invalidStoredValue(model.dispositionRawValue)
            }
            guard currentDisposition != .abandoned else {
                throw CaptureRepositoryError.abandonedDraftImmutable
            }
            guard mutation.disposition == currentDisposition else {
                throw CaptureRepositoryError.invalidDraftTransition(
                    from: currentDisposition,
                    to: mutation.disposition
                )
            }

            return try commit {
                if mutation.disposition == .active {
                    try stashOtherActiveDrafts(except: model.stableID, at: now)
                }
                model.title = mutation.title
                model.editorDocument = canonicalEditor
                model.sourceDocument = canonicalSource
                model.dispositionRawValue = mutation.disposition.rawValue
                model.updatedAt = now
                model.revision += 1
                return try snapshot(model)
            }
        }

        guard expectedRevision == 0 else {
            throw CaptureRepositoryError.staleRevision(expected: expectedRevision, actual: 0)
        }
        guard mutation.disposition != .abandoned else {
            throw CaptureRepositoryError.invalidNewDraftDisposition(mutation.disposition)
        }
        return try commit {
            let returnDraftID: String?
            if mutation.disposition == .active {
                returnDraftID = try activeDraft(except: mutation.id)?.stableID
                try stashOtherActiveDrafts(except: mutation.id, at: now)
            } else {
                returnDraftID = nil
            }
            let model = CaptureDraftModel(
                stableID: mutation.id,
                revision: 1,
                title: mutation.title,
                editorDocument: canonicalEditor,
                sourceDocument: canonicalSource,
                dispositionRawValue: mutation.disposition.rawValue,
                createdAt: now,
                updatedAt: now,
                returnDraftID: returnDraftID
            )
            context.insert(model)
            return try snapshot(model)
        }
    }

    func restoreDraft(id: String, expectedRevision: Int) throws -> CaptureDraftSnapshot {
        guard let model = try draftModel(id: id) else {
            throw CaptureRepositoryError.draftNotFound(id)
        }
        guard model.revision == expectedRevision else {
            throw CaptureRepositoryError.staleRevision(expected: expectedRevision, actual: model.revision)
        }
        guard let currentDisposition = DraftDisposition(rawValue: model.dispositionRawValue) else {
            throw CaptureRepositoryError.invalidStoredValue(model.dispositionRawValue)
        }
        guard currentDisposition == .stashed else {
            throw CaptureRepositoryError.invalidDraftTransition(from: currentDisposition, to: .active)
        }
        let now = clock.now()
        return try commit {
            model.returnDraftID = try activeDraft(except: id)?.stableID
            try stashOtherActiveDrafts(except: id, at: now)
            model.dispositionRawValue = DraftDisposition.active.rawValue
            model.captureRecordID = nil
            model.updatedAt = now
            model.revision += 1
            return try snapshot(model)
        }
    }

    func stashDraft(id: String, expectedRevision: Int) throws -> CaptureDraftSnapshot {
        guard let model = try draftModel(id: id) else {
            throw CaptureRepositoryError.draftNotFound(id)
        }
        guard model.revision == expectedRevision else {
            throw CaptureRepositoryError.staleRevision(expected: expectedRevision, actual: model.revision)
        }
        guard let currentDisposition = DraftDisposition(rawValue: model.dispositionRawValue) else {
            throw CaptureRepositoryError.invalidStoredValue(model.dispositionRawValue)
        }
        guard currentDisposition == .active else {
            throw CaptureRepositoryError.invalidDraftTransition(from: currentDisposition, to: .stashed)
        }
        let now = clock.now()
        return try commit {
            let returnDraftID = model.returnDraftID
            model.dispositionRawValue = DraftDisposition.stashed.rawValue
            model.returnDraftID = nil
            model.updatedAt = now
            model.revision += 1
            try reactivateReturnDraft(id: returnDraftID, at: now)
            return try snapshot(model)
        }
    }

    func enqueue(
        draftID: String,
        expectedRevision: Int,
        destination: CaptureDestination
    ) throws -> CaptureRecordSnapshot {
        if let existing = try recordModel(id: draftID) {
            guard expectedRevision == existing.enqueuedDraftRevision else {
                throw CaptureRepositoryError.staleRevision(
                    expected: expectedRevision,
                    actual: existing.enqueuedDraftRevision
                )
            }
            guard existing.destinationKind == destination.rawKind,
                  existing.destinationID == destination.identifier
            else {
                throw CaptureRepositoryError.enqueueDestinationMismatch
            }
            return try snapshot(existing)
        }
        guard let draft = try draftModel(id: draftID) else {
            throw CaptureRepositoryError.draftNotFound(draftID)
        }
        guard draft.revision == expectedRevision else {
            throw CaptureRepositoryError.staleRevision(expected: expectedRevision, actual: draft.revision)
        }

        let now = clock.now()
        let record = CaptureRecordModel(
            stableID: draft.stableID,
            draftID: draft.stableID,
            enqueuedDraftRevision: expectedRevision,
            revision: 1,
            title: draft.title,
            editorDocument: draft.editorDocument,
            sourceDocument: draft.sourceDocument,
            destinationKind: destination.rawKind,
            destinationID: destination.identifier,
            stateRawValue: DeliveryState.queued.rawValue,
            attemptCount: 0,
            firstQueuedAt: now,
            nextAttemptAt: now,
            inFlightAt: nil,
            deliveredAt: nil,
            updatedAt: now
        )
        return try commit {
            context.insert(record)
            let returnDraftID = draft.returnDraftID
            draft.dispositionRawValue = DraftDisposition.abandoned.rawValue
            draft.captureRecordID = record.stableID
            draft.returnDraftID = nil
            draft.updatedAt = now
            draft.revision += 1
            try reactivateReturnDraft(id: returnDraftID, at: now)
            return try snapshot(record)
        }
    }

    func draft(id: String) throws -> CaptureDraftSnapshot? {
        try draftModel(id: id).map(snapshot)
    }

    func drafts() throws -> [CaptureDraftSnapshot] {
        try context.fetch(FetchDescriptor<CaptureDraftModel>())
            .map(snapshot)
            .sorted { $0.id < $1.id }
    }

    func record(id: String) throws -> CaptureRecordSnapshot? {
        try recordModel(id: id).map(snapshot)
    }

    func records() throws -> [CaptureRecordSnapshot] {
        try context.fetch(FetchDescriptor<CaptureRecordModel>())
            .map(snapshot)
            .sorted { $0.id < $1.id }
    }

    func claimNext(at now: Date, retryPolicy: RetryPolicy) throws -> CaptureRecordSnapshot? {
        let candidates = try context.fetch(FetchDescriptor<CaptureRecordModel>())
            .filter {
                $0.stateRawValue == DeliveryState.queued.rawValue
                    || $0.stateRawValue == DeliveryState.retrying.rawValue
            }
            .sorted {
                if $0.firstQueuedAt == $1.firstQueuedAt { return $0.stableID < $1.stableID }
                return $0.firstQueuedAt < $1.firstQueuedAt
            }

        var changedForAttention = false
        for model in candidates {
            if retryPolicy.requiresAttention(firstQueuedAt: model.firstQueuedAt, now: now) {
                model.stateRawValue = DeliveryState.uncertain.rawValue
                model.nextAttemptAt = nil
                model.inFlightAt = nil
                model.updatedAt = now
                model.revision += 1
                setSafeError(
                    SafeDeliveryError(
                        code: "requiresAttention",
                        message: "Delivery needs review after seven days.",
                        statusCode: nil,
                        retryAfter: nil
                    ),
                    on: model
                )
                changedForAttention = true
                continue
            }
            guard let nextAttemptAt = model.nextAttemptAt, nextAttemptAt <= now else { continue }
            return try commit {
                model.stateRawValue = DeliveryState.inFlight.rawValue
                model.inFlightAt = now
                model.nextAttemptAt = nil
                model.attemptCount += 1
                model.updatedAt = now
                model.revision += 1
                return try snapshot(model)
            }
        }
        if changedForAttention {
            try commit {}
        }
        return nil
    }

    func recoverInterruptedWork(at now: Date) throws -> Int {
        let interrupted = try context.fetch(FetchDescriptor<CaptureRecordModel>())
            .filter { $0.stateRawValue == DeliveryState.inFlight.rawValue }
        guard !interrupted.isEmpty else { return 0 }
        return try commit {
            for model in interrupted {
                if model.destinationKind == "managed" {
                    model.stateRawValue = DeliveryState.retrying.rawValue
                    model.nextAttemptAt = now
                    model.requiresManagedCheck = true
                    setSafeError(
                        SafeDeliveryError(
                            code: "interruptedManagedDelivery",
                            message: "Checking for an earlier managed delivery before retrying.",
                            statusCode: nil,
                            retryAfter: nil
                        ),
                        on: model
                    )
                } else {
                    model.stateRawValue = DeliveryState.uncertain.rawValue
                    model.nextAttemptAt = nil
                    model.requiresManagedCheck = false
                    setSafeError(
                        SafeDeliveryError(
                            code: "interruptedManualAppend",
                            message: "Manual append outcome needs review.",
                            statusCode: nil,
                            retryAfter: nil
                        ),
                        on: model
                    )
                }
                model.inFlightAt = nil
                model.updatedAt = now
                model.revision += 1
            }
            return interrupted.count
        }
    }

    func markDelivered(
        recordID: String,
        receipt: DeliveryReceipt,
        at now: Date
    ) throws -> CaptureRecordSnapshot {
        guard let model = try recordModel(id: recordID) else {
            throw CaptureRepositoryError.recordNotFound(recordID)
        }
        return try commit {
            model.stateRawValue = DeliveryState.delivered.rawValue
            model.nextAttemptAt = nil
            model.inFlightAt = nil
            model.deliveredAt = now
            model.updatedAt = now
            model.remoteIdentity = receipt.remoteIdentity
            model.fingerprint = receipt.fingerprint
            model.requiresManagedCheck = false
            clearSafeError(on: model)
            model.revision += 1
            return try snapshot(model)
        }
    }

    func markRetrying(
        recordID: String,
        nextAttemptAt: Date?,
        requiresManagedCheck: Bool,
        safeError: SafeDeliveryError,
        at now: Date
    ) throws -> CaptureRecordSnapshot {
        try transition(
            recordID: recordID,
            state: .retrying,
            nextAttemptAt: nextAttemptAt,
            requiresManagedCheck: requiresManagedCheck,
            safeError: safeError,
            at: now
        )
    }

    func markBlockedConflict(
        recordID: String,
        safeError: SafeDeliveryError,
        at now: Date
    ) throws -> CaptureRecordSnapshot {
        try transition(
            recordID: recordID,
            state: .blockedConflict,
            nextAttemptAt: nil,
            requiresManagedCheck: false,
            safeError: safeError,
            at: now
        )
    }

    func markUncertain(
        recordID: String,
        safeError: SafeDeliveryError,
        at now: Date
    ) throws -> CaptureRecordSnapshot {
        try transition(
            recordID: recordID,
            state: .uncertain,
            nextAttemptAt: nil,
            requiresManagedCheck: false,
            safeError: safeError,
            at: now
        )
    }

    func recordReplacementBeforeArchive(
        recordID: String,
        replacementBlockIDs: [String],
        blocksToArchive: [String]
    ) throws -> CaptureRecordSnapshot {
        guard let model = try recordModel(id: recordID) else {
            throw CaptureRepositoryError.recordNotFound(recordID)
        }
        let operationJournal = try CanonicalJSON.encode([
            "blocksToArchive": blocksToArchive.sorted(),
            "replacementBlockIDs": replacementBlockIDs.sorted(),
            "stage": "replacementWrittenAwaitingArchive",
        ])
        return try commit {
            model.operationJournal = operationJournal
            model.updatedAt = clock.now()
            model.revision += 1
            return try snapshot(model)
        }
    }

    func applyRetention(at now: Date, policy: RetentionPolicy) throws -> RetentionResult {
        let cutoff = now.addingTimeInterval(-policy.retentionInterval)
        let records = try context.fetch(FetchDescriptor<CaptureRecordModel>())
        let deletableRecords = records.filter {
            $0.stateRawValue == DeliveryState.delivered.rawValue
                && ($0.deliveredAt ?? $0.updatedAt) < cutoff
                && $0.operationJournal == nil
        }
        let deletableRecordIDs = Set(deletableRecords.map(\.stableID))
        let drafts = try context.fetch(FetchDescriptor<CaptureDraftModel>())
        let deletableDrafts = drafts.filter {
            guard $0.dispositionRawValue == DraftDisposition.abandoned.rawValue,
                  $0.updatedAt < cutoff
            else { return false }
            guard let captureRecordID = $0.captureRecordID else { return true }
            return deletableRecordIDs.contains(captureRecordID)
        }
        let result = RetentionResult(
            deletedRecords: deletableRecords.count,
            deletedDrafts: deletableDrafts.count
        )
        guard !deletableRecords.isEmpty || !deletableDrafts.isEmpty else { return result }
        return try commit {
            deletableRecords.forEach(context.delete)
            deletableDrafts.forEach(context.delete)
            return result
        }
    }

    private func draftModel(id: String) throws -> CaptureDraftModel? {
        try context.fetch(FetchDescriptor<CaptureDraftModel>()).first { $0.stableID == id }
    }

    private func recordModel(id: String) throws -> CaptureRecordModel? {
        try context.fetch(FetchDescriptor<CaptureRecordModel>()).first { $0.stableID == id }
    }

    private func activeDraft(except id: String) throws -> CaptureDraftModel? {
        try beforeHelperFetch(.activeDraft)
        return try context.fetch(FetchDescriptor<CaptureDraftModel>())
            .filter {
                $0.stableID != id
                    && $0.dispositionRawValue == DraftDisposition.active.rawValue
            }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.stableID < $1.stableID }
                return $0.updatedAt > $1.updatedAt
            }
            .first
    }

    private func reactivateReturnDraft(id: String?, at now: Date) throws {
        guard let id else { return }
        try beforeHelperFetch(.returnDraft)
        guard let returnDraft = try draftModel(id: id),
              returnDraft.dispositionRawValue == DraftDisposition.stashed.rawValue,
              returnDraft.captureRecordID == nil
        else { return }
        try stashOtherActiveDrafts(except: id, at: now)
        returnDraft.dispositionRawValue = DraftDisposition.active.rawValue
        returnDraft.updatedAt = now
        returnDraft.revision += 1
    }

    private func transition(
        recordID: String,
        state: DeliveryState,
        nextAttemptAt: Date?,
        requiresManagedCheck: Bool,
        safeError: SafeDeliveryError,
        at now: Date
    ) throws -> CaptureRecordSnapshot {
        guard let model = try recordModel(id: recordID) else {
            throw CaptureRepositoryError.recordNotFound(recordID)
        }
        return try commit {
            model.stateRawValue = state.rawValue
            model.nextAttemptAt = nextAttemptAt
            model.inFlightAt = nil
            model.requiresManagedCheck = requiresManagedCheck
            model.updatedAt = now
            model.revision += 1
            setSafeError(safeError, on: model)
            return try snapshot(model)
        }
    }

    private func commit<Result>(_ changes: () throws -> Result) throws -> Result {
        do {
            let result = try changes()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private func setSafeError(_ error: SafeDeliveryError, on model: CaptureRecordModel) {
        model.safeErrorCode = error.code
        model.safeErrorMessage = error.message
        model.safeErrorStatusCode = error.statusCode
        model.safeErrorRetryAfter = error.retryAfter
    }

    private func clearSafeError(on model: CaptureRecordModel) {
        model.safeErrorCode = nil
        model.safeErrorMessage = nil
        model.safeErrorStatusCode = nil
        model.safeErrorRetryAfter = nil
    }

    private func stashOtherActiveDrafts(except id: String, at now: Date) throws {
        try beforeHelperFetch(.otherActiveDrafts)
        for draft in try context.fetch(FetchDescriptor<CaptureDraftModel>())
        where draft.stableID != id && draft.dispositionRawValue == DraftDisposition.active.rawValue {
            draft.dispositionRawValue = DraftDisposition.stashed.rawValue
            draft.updatedAt = now
            draft.revision += 1
        }
    }

    private func draftMatches(
        _ model: CaptureDraftModel,
        mutation: DraftMutation,
        canonicalEditor: Data,
        canonicalSource: Data?
    ) -> Bool {
        model.title == mutation.title
            && model.editorDocument == canonicalEditor
            && model.sourceDocument == canonicalSource
            && model.dispositionRawValue == mutation.disposition.rawValue
    }

    private func snapshot(_ model: CaptureDraftModel) throws -> CaptureDraftSnapshot {
        guard let disposition = DraftDisposition(rawValue: model.dispositionRawValue) else {
            throw CaptureRepositoryError.invalidStoredValue(model.dispositionRawValue)
        }
        return CaptureDraftSnapshot(
            id: model.stableID,
            revision: model.revision,
            title: model.title,
            editorDocument: model.editorDocument,
            sourceDocument: model.sourceDocument,
            disposition: disposition,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            captureRecordID: model.captureRecordID,
            returnDraftID: model.returnDraftID
        )
    }

    private func snapshot(_ model: CaptureRecordModel) throws -> CaptureRecordSnapshot {
        guard let destination = CaptureDestination(rawKind: model.destinationKind, identifier: model.destinationID),
              let state = DeliveryState(rawValue: model.stateRawValue)
        else {
            throw CaptureRepositoryError.invalidStoredValue("\(model.destinationKind)/\(model.stateRawValue)")
        }
        let safeError = model.safeErrorCode.map {
            SafeDeliveryError(
                code: $0,
                message: model.safeErrorMessage,
                statusCode: model.safeErrorStatusCode,
                retryAfter: model.safeErrorRetryAfter
            )
        }
        return CaptureRecordSnapshot(
            id: model.stableID,
            draftID: model.draftID,
            enqueuedDraftRevision: model.enqueuedDraftRevision,
            revision: model.revision,
            title: model.title,
            editorDocument: model.editorDocument,
            sourceDocument: model.sourceDocument,
            destination: destination,
            state: state,
            attemptCount: model.attemptCount,
            firstQueuedAt: model.firstQueuedAt,
            nextAttemptAt: model.nextAttemptAt,
            inFlightAt: model.inFlightAt,
            deliveredAt: model.deliveredAt,
            updatedAt: model.updatedAt,
            fingerprint: model.fingerprint,
            operationJournal: model.operationJournal,
            remoteIdentity: model.remoteIdentity,
            safeError: safeError,
            requiresManagedCheck: model.requiresManagedCheck
        )
    }
}
