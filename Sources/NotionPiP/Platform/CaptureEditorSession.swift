import AppKit
import Combine
import Foundation
import WebKit

enum CaptureEditorStatus: Equatable, Sendable {
    case loading
    case ready
    case saving
    case saved(revision: Int)
    case stashed
    case failed(String)
}

enum CaptureStashTransitionStep: Equatable, Sendable {
    case persisted
    case stashed
}

struct CaptureConflict: Equatable, Sendable {
    let currentWork: CaptureEditorSnapshot
    let latest: CaptureEditorSnapshot
    let availableActions: [CaptureConflictAction]
}

@MainActor
protocol CaptureConflictResolving: AnyObject {
    func resolve(
        _ action: CaptureConflictAction,
        operationID: String,
        in webView: WKWebView
    ) async throws
}

@MainActor
final class WebKitCaptureConflictResolver: CaptureConflictResolving {
    func resolve(
        _ action: CaptureConflictAction,
        operationID: String,
        in webView: WKWebView
    ) async throws {
        let value = try await webView.callAsyncJavaScript(
            "return await window.NotionPiPBridge.resolveConflict(action, operationID)",
            arguments: [
                "action": action.rawValue,
                "operationID": operationID,
            ],
            in: nil,
            contentWorld: .page
        )
        guard let reply = value as? [String: Any],
              reply["version"] as? Int == CaptureBridgeReply.version,
              reply["id"] as? String == operationID,
              reply["ok"] as? Bool == true,
              let result = reply["result"] as? [String: Any],
              result["kind"] as? String == CaptureBridgeResultKind.conflictResolved.rawValue
        else {
            throw CaptureConflictResolverError.invalidReply
        }
    }
}

private enum CaptureConflictResolverError: Error {
    case invalidReply
}

private struct PendingConflictResolution {
    let action: CaptureConflictAction
    let operationID: String
    let originalConflict: CaptureConflict
}

struct CaptureEditorResourceRoots {
    let packagedApp: URL?
    let swiftPMBundle: URL?
}

enum CaptureEditorResources {
    static let unavailableEditorURL = URL(
        fileURLWithPath: "/__missing_NotionPiP_QuickCapture__/index.html"
    )

    static func editorURL(
        appResourceRoot: URL?,
        swiftPMResourceRoot: @autoclosure () -> URL?,
        fileManager: FileManager = .default
    ) -> URL {
        if let appResourceRoot {
            let packagedEditorURL = appResourceRoot
                .appendingPathComponent("NotionPiP_NotionPiP.bundle", isDirectory: true)
                .appendingPathComponent("QuickCapture", isDirectory: true)
                .appendingPathComponent("index.html", isDirectory: false)
            if fileManager.fileExists(atPath: packagedEditorURL.path) {
                return packagedEditorURL
            }
        }

        if let swiftPMResourceRoot = swiftPMResourceRoot() {
            let swiftPMEditorURL = swiftPMResourceRoot
                .appendingPathComponent("QuickCapture", isDirectory: true)
                .appendingPathComponent("index.html", isDirectory: false)
            if fileManager.fileExists(atPath: swiftPMEditorURL.path) {
                return swiftPMEditorURL
            }
        }

        return unavailableEditorURL
    }
}

private enum CaptureStateTransitionOperation: Equatable {
    case stash(snapshot: CaptureEditorSnapshot, expectedRevision: Int)
    case restore(draftID: String, expectedRevision: Int)
    case resolveConflict(action: CaptureConflictAction, snapshot: CaptureEditorSnapshot)

    init?(_ request: CaptureBridgeRequest) {
        switch request {
        case let .stash(_, snapshot, expectedRevision):
            self = .stash(snapshot: snapshot, expectedRevision: expectedRevision)
        case let .restore(_, draftID, expectedRevision):
            self = .restore(draftID: draftID, expectedRevision: expectedRevision)
        case let .resolveConflict(_, action, snapshot):
            self = .resolveConflict(action: action, snapshot: snapshot)
        case .ready, .changed, .save:
            return nil
        }
    }
}

@MainActor
final class CaptureEditorSession: NSObject, ObservableObject, CaptureScriptMessageHandling {
    @Published private(set) var status: CaptureEditorStatus = .loading
    @Published private(set) var conflict: CaptureConflict?
    @Published private(set) var isResolvingConflict = false

    let webView: WKWebView
    private(set) var installedHandlerNames: Set<String> = [CaptureBridgeProtocol.handlerName]

    private let repository: CaptureRepository
    private let draftID: () -> String
    private let openInNotion: () -> Void
    private let openURL: @MainActor (URL) -> Void
    private let beforeBridgeRequest: (CaptureBridgeRequest) async -> Void
    private let beforeConflictResolution: (CaptureEditorSnapshot) async -> Void
    private let beforeCreatingActiveDraft: () async -> Void
    private let afterStashTransitionStep: (CaptureStashTransitionStep) async throws -> Void
    private let afterStateTransitionCommit: (
        CaptureBridgeRequest,
        CaptureBridgeReply
    ) async throws -> Void
    private let conflictResolver: any CaptureConflictResolving
    private let scriptHandler: WeakScriptMessageHandler
    private let editorDocumentURL: URL
    private let resourceRootURL: URL
    private var pendingConflictResolution: PendingConflictResolution?
    private var inFlightStateTransitions: [
        String: (operation: CaptureStateTransitionOperation, task: Task<CaptureBridgeReply, Never>)
    ] = [:]
    private var committedStateTransitions: [
        String: (operation: CaptureStateTransitionOperation, reply: CaptureBridgeReply)
    ] = [:]
    private var committedStateTransitionOrder: [String] = []
    private var ambiguousStateTransitions: [String: CaptureStateTransitionOperation] = [:]
    private var activeDraftCreationTask: Task<CaptureEditorSnapshot, Error>?
    private var terminationPersistenceTask: Task<Bool, Never>?
    private var isDisposed = false
    private var isRecoveringAfterRendererTermination = false

    init(
        repository: CaptureRepository,
        draftID: @escaping () -> String = { UUID().uuidString.lowercased() },
        openInNotion: @escaping () -> Void = {},
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        beforeBridgeRequest: @escaping (CaptureBridgeRequest) async -> Void = { _ in },
        beforeConflictResolution: @escaping (CaptureEditorSnapshot) async -> Void = { _ in },
        beforeCreatingActiveDraft: @escaping () async -> Void = {},
        afterStashTransitionStep: @escaping (
            CaptureStashTransitionStep
        ) async throws -> Void = { _ in },
        afterStateTransitionCommit: @escaping (
            CaptureBridgeRequest,
            CaptureBridgeReply
        ) async throws -> Void = { _, _ in },
        conflictResolver: any CaptureConflictResolving = WebKitCaptureConflictResolver(),
        editorResourceRoots: CaptureEditorResourceRoots? = nil
    ) {
        self.repository = repository
        self.draftID = draftID
        self.openInNotion = openInNotion
        self.openURL = openURL
        self.beforeBridgeRequest = beforeBridgeRequest
        self.beforeConflictResolution = beforeConflictResolution
        self.beforeCreatingActiveDraft = beforeCreatingActiveDraft
        self.afterStashTransitionStep = afterStashTransitionStep
        self.afterStateTransitionCommit = afterStateTransitionCommit
        self.conflictResolver = conflictResolver

        let documentURL = editorResourceRoots.map(Self.editorURL(for:)) ?? Self.bundledEditorURL
        editorDocumentURL = documentURL
        resourceRootURL = documentURL.deletingLastPathComponent()
        let handler = WeakScriptMessageHandler(allowedDocumentURL: documentURL)
        scriptHandler = handler
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addScriptMessageHandler(
            handler,
            contentWorld: .page,
            name: CaptureBridgeProtocol.handlerName
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear

        super.init()
        handler.delegate = self
        webView.navigationDelegate = self
        loadLocalEditor()
    }

    func handleScriptMessage(_ request: CaptureBridgeRequest) async -> CaptureBridgeReply {
        await handle(request)
    }

    func handle(_ request: CaptureBridgeRequest) async -> CaptureBridgeReply {
        await beforeBridgeRequest(request)
        if let operation = CaptureStateTransitionOperation(request) {
            return await idempotentStateTransition(request, operation: operation)
        }
        return await perform(request)
    }

    func latestSnapshot() async throws -> CaptureEditorSnapshot {
        let value = try await webView.callAsyncJavaScript(
            "return window.NotionPiPBridge.snapshot()",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let object = value as? [String: Any],
              let draftID = object["draftID"] as? String,
              !draftID.isEmpty,
              let title = object["title"] as? String,
              let revision = object["revision"] as? Int,
              let documentObject = object["document"],
              JSONSerialization.isValidJSONObject(documentObject)
        else {
            throw CaptureConflictResolverError.invalidReply
        }
        let document = try CanonicalJSON.encode(documentObject)
        return CaptureEditorSnapshot(
            draftID: draftID,
            title: title,
            document: document,
            revision: revision
        )
    }

    func prefill(_ text: String) async -> Bool {
        guard !text.isEmpty else { return false }
        do {
            return try await webView.callAsyncJavaScript(
                "return window.NotionPiPBridge.prefill(text)",
                arguments: ["text": text], in: nil, contentWorld: .page
            ) as? Bool == true
        } catch { return false }
    }

    func prepareForTermination() async -> Bool {
        if let terminationPersistenceTask {
            return await terminationPersistenceTask.value
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return true }
            do {
                let snapshot = try await self.latestSnapshot()
                try await self.persistTerminationSnapshot(snapshot)
                return true
            } catch {
                self.status = .failed("Could not save the latest draft before quitting.")
                return false
            }
        }
        terminationPersistenceTask = task
        let result = await task.value
        terminationPersistenceTask = nil
        return result
    }

    func reportCloseGuidance(_ message: String) {
        status = .failed(message)
    }

    private func perform(_ request: CaptureBridgeRequest) async -> CaptureBridgeReply {
        do {
            switch request {
            case let .ready(id):
                let snapshot = try await activeOrNewDraft()
                status = .ready
                isRecoveringAfterRendererTermination = false
                return .success(id: id, result: .ready(snapshot))

            case let .changed(id, snapshot, expectedRevision):
                status = .saving
                do {
                    let saved = try await repository.saveDraft(
                        try mutation(snapshot, id: snapshot.draftID),
                        expectedRevision: expectedRevision
                    )
                    status = .saved(revision: saved.revision)
                    conflict = nil
                    return .success(id: id, result: .changed(revision: saved.revision))
                } catch let error as CaptureRepositoryError {
                    return await repositoryFailure(
                        error,
                        id: id,
                        currentWork: snapshot
                    )
                }

            case let .save(id, snapshot, expectedRevision):
                do {
                    let stored = try await persistSuppliedSnapshot(
                        snapshot,
                        expectedRevision: expectedRevision
                    )
                    status = .saved(revision: stored.revision)
                    conflict = nil
                    return .success(id: id, result: .saved(revision: stored.revision))
                } catch let error as CaptureRepositoryError {
                    return await repositoryFailure(error, id: id, currentWork: snapshot)
                }

            case let .stash(id, snapshot, expectedRevision):
                do {
                    let stored = try await persistSuppliedSnapshot(
                        snapshot,
                        expectedRevision: expectedRevision
                    )
                    try await afterStashTransitionStep(.persisted)
                    _ = try await repository.stashDraft(
                        id: snapshot.draftID,
                        expectedRevision: stored.revision
                    )
                    try await afterStashTransitionStep(.stashed)
                    let next = try await activeOrNewDraft()
                    status = .stashed
                    conflict = nil
                    return .success(id: id, result: .stashed(next))
                } catch let error as CaptureRepositoryError {
                    return await repositoryFailure(error, id: id, currentWork: snapshot)
                }

            case let .restore(id, draftID, expectedRevision):
                let restored = try await repository.restoreDraft(
                    id: draftID,
                    expectedRevision: expectedRevision
                )
                let snapshot = try bridgeSnapshot(restored)
                status = .saved(revision: restored.revision)
                conflict = nil
                return .success(id: id, result: .restored(snapshot))

            case let .resolveConflict(id, action, snapshot):
                return await performConflictResolution(
                    id: id,
                    action: action,
                    snapshot: snapshot
                )
            }
        } catch let error as CaptureRepositoryError {
            return await repositoryFailure(error, id: request.id, currentWork: nil)
        } catch {
            status = .failed("Could not persist this draft.")
            return .failure(
                id: request.id,
                code: .persistenceFailure,
                message: "Could not persist this draft.",
                recoverable: true
            )
        }
    }

    func resolve(_ action: CaptureConflictAction) async {
        guard !isResolvingConflict else { return }
        let pending: PendingConflictResolution
        if let existing = pendingConflictResolution {
            guard existing.action == action else {
                status = .failed("Retry the pending recovery action before choosing another one.")
                return
            }
            pending = existing
        } else {
            guard let originalConflict = conflict else { return }
            pending = PendingConflictResolution(
                action: action,
                operationID: UUID().uuidString.lowercased(),
                originalConflict: originalConflict
            )
            pendingConflictResolution = pending
        }

        isResolvingConflict = true
        defer { isResolvingConflict = false }
        do {
            try await conflictResolver.resolve(
                action,
                operationID: pending.operationID,
                in: webView
            )
            pendingConflictResolution = nil
            if action != .openInNotion {
                conflict = nil
            }
        } catch {
            conflict = pending.originalConflict
            status = .failed("The editor could not apply the recovered draft.")
        }
    }

    private func idempotentStateTransition(
        _ request: CaptureBridgeRequest,
        operation: CaptureStateTransitionOperation
    ) async -> CaptureBridgeReply {
        let id = request.id
        if let ambiguous = ambiguousStateTransitions[id] {
            guard ambiguous == operation else {
                return invalidStateTransitionReplay(id: id)
            }
        }
        if let committed = committedStateTransitions[id] {
            guard committed.operation == operation else {
                return invalidStateTransitionReplay(id: id)
            }
            return committed.reply
        }
        if let inFlight = inFlightStateTransitions[id] {
            guard inFlight.operation == operation else {
                return invalidStateTransitionReplay(id: id)
            }
            return await inFlight.task.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return CaptureBridgeReply.failure(
                    id: id,
                    code: .persistenceFailure,
                    message: "Conflict recovery is no longer available.",
                    recoverable: true
                )
            }
            if self.ambiguousStateTransitions[id] != nil,
               let reconciled = await self.reconcileStateTransition(operation, id: id)
            {
                return reconciled
            }
            let reply = await self.perform(request)
            guard reply.result != nil else { return reply }
            if case .resolveConflict = operation {
                self.rememberStateTransition(id: id, operation: operation, reply: reply)
            }
            do {
                try await self.afterStateTransitionCommit(request, reply)
                return reply
            } catch {
                self.status = .failed("Could not confirm the saved draft transition.")
                return .failure(
                    id: id,
                    code: .persistenceFailure,
                    message: "Could not confirm the saved draft transition.",
                    recoverable: true
                )
            }
        }
        inFlightStateTransitions[id] = (operation, task)
        let reply = await task.value
        inFlightStateTransitions[id] = nil
        if reply.result != nil {
            ambiguousStateTransitions[id] = nil
            rememberStateTransition(id: id, operation: operation, reply: reply)
        } else if reply.error?.code == .persistenceFailure {
            if committedStateTransitions[id] == nil {
                rememberAmbiguousStateTransition(id: id, operation: operation)
            }
        } else {
            ambiguousStateTransitions[id] = nil
        }
        return reply
    }

    private func reconcileStateTransition(
        _ operation: CaptureStateTransitionOperation,
        id: String
    ) async -> CaptureBridgeReply? {
        do {
            switch operation {
            case let .stash(snapshot, expectedRevision):
                guard let stored = try await repository.draft(id: snapshot.draftID),
                      stored.title == snapshot.title,
                      stored.editorDocument == (try CaptureBridgeProtocol.canonicalDocument(snapshot.document))
                else { return nil }
                let next: CaptureEditorSnapshot
                switch stored.disposition {
                case .active:
                    guard expectedRevision < Int.max,
                          stored.revision == expectedRevision + 1
                    else { return nil }
                    do {
                        _ = try await repository.stashDraft(
                            id: snapshot.draftID,
                            expectedRevision: stored.revision
                        )
                        try await afterStashTransitionStep(.stashed)
                        next = try await activeOrNewDraft()
                    } catch {
                        return ambiguousStateTransitionFailure(id: id)
                    }
                case .stashed:
                    guard stored.revision > expectedRevision else { return nil }
                    do {
                        try await afterStashTransitionStep(.stashed)
                        next = try await activeOrNewDraft()
                    } catch {
                        return ambiguousStateTransitionFailure(id: id)
                    }
                case .abandoned:
                    return nil
                }
                status = .stashed
                conflict = nil
                return .success(id: id, result: .stashed(next))

            case let .restore(draftID, expectedRevision):
                guard expectedRevision < Int.max,
                      let restored = try await repository.draft(id: draftID),
                      restored.disposition == .active,
                      restored.revision == expectedRevision + 1
                else { return nil }
                let snapshot = try bridgeSnapshot(restored)
                status = .saved(revision: restored.revision)
                conflict = nil
                return .success(id: id, result: .restored(snapshot))

            case .resolveConflict:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func performConflictResolution(
        id: String,
        action: CaptureConflictAction,
        snapshot: CaptureEditorSnapshot
    ) async -> CaptureBridgeReply {
        do {
        await beforeConflictResolution(snapshot)
        switch action {
        case .reloadLatest:
            guard let latest = try await repository.draft(id: snapshot.draftID) else {
                return .failure(
                    id: id,
                    code: .draftNotFound,
                    message: "The latest draft is no longer available.",
                    recoverable: true
                )
            }
            let bridge = try bridgeSnapshot(latest)
            conflict = nil
            status = .saved(revision: latest.revision)
            return .success(id: id, result: .conflictResolved(bridge))

        case .saveAsNew:
            let newID = draftID()
            let saved = try await repository.saveDraft(
                try mutation(snapshot, id: newID),
                expectedRevision: 0
            )
            let bridge = try bridgeSnapshot(saved)
            conflict = nil
            status = .saved(revision: saved.revision)
            return .success(id: id, result: .conflictResolved(bridge))

        case .openInNotion:
            openInNotion()
            return .success(id: id, result: .conflictResolved(nil))
        }
        } catch let error as CaptureRepositoryError {
            return await repositoryFailure(error, id: id, currentWork: snapshot)
        } catch {
            status = .failed("Could not recover this draft.")
            return .failure(
                id: id,
                code: .persistenceFailure,
                message: "Could not recover this draft.",
                recoverable: true
            )
        }
    }

    private func invalidStateTransitionReplay(id: String) -> CaptureBridgeReply {
        .failure(
            id: id,
            code: .invalidMessage,
            message: "State transition request did not match its original operation.",
            recoverable: false
        )
    }

    private func ambiguousStateTransitionFailure(id: String) -> CaptureBridgeReply {
        status = .failed("Could not confirm the saved draft transition.")
        return .failure(
            id: id,
            code: .persistenceFailure,
            message: "Could not confirm the saved draft transition.",
            recoverable: true
        )
    }

    private func rememberStateTransition(
        id: String,
        operation: CaptureStateTransitionOperation,
        reply: CaptureBridgeReply
    ) {
        let isNewReceipt = committedStateTransitions[id] == nil
        committedStateTransitions[id] = (operation, reply)
        if isNewReceipt {
            committedStateTransitionOrder.append(id)
        }
        if committedStateTransitionOrder.count > 64 {
            let expired = committedStateTransitionOrder.removeFirst()
            committedStateTransitions[expired] = nil
        }
    }

    private func rememberAmbiguousStateTransition(
        id: String,
        operation: CaptureStateTransitionOperation
    ) {
        ambiguousStateTransitions[id] = operation
        if ambiguousStateTransitions.count > 64,
           let expired = ambiguousStateTransitions.keys.sorted().first(where: { $0 != id })
        {
            ambiguousStateTransitions[expired] = nil
        }
    }

    private func activeOrNewDraft() async throws -> CaptureEditorSnapshot {
        if let active = try await repository.drafts().first(where: { $0.disposition == .active }) {
            return try bridgeSnapshot(active)
        }
        if let activeDraftCreationTask {
            return try await activeDraftCreationTask.value
        }
        let task = Task { @MainActor [weak self] () throws -> CaptureEditorSnapshot in
            guard let self else { throw CancellationError() }
            await self.beforeCreatingActiveDraft()
            let id = self.draftID()
            let created = try await self.repository.saveDraft(
                DraftMutation(
                    id: id,
                    title: "",
                    editorDocument: Self.emptyDocument,
                    sourceDocument: nil,
                    disposition: .active
                ),
                expectedRevision: 0
            )
            return try self.bridgeSnapshot(created)
        }
        activeDraftCreationTask = task
        defer { activeDraftCreationTask = nil }
        return try await task.value
    }

    private func persistSuppliedSnapshot(
        _ snapshot: CaptureEditorSnapshot,
        expectedRevision: Int
    ) async throws -> CaptureDraftSnapshot {
        guard let stored = try await repository.draft(id: snapshot.draftID) else {
            throw CaptureRepositoryError.draftNotFound(snapshot.draftID)
        }
        guard stored.revision == expectedRevision else {
            throw CaptureRepositoryError.staleRevision(
                expected: expectedRevision,
                actual: stored.revision
            )
        }
        let canonicalDocument = try CaptureBridgeProtocol.canonicalDocument(snapshot.document)
        if stored.title == snapshot.title, stored.editorDocument == canonicalDocument {
            return stored
        }
        return try await repository.saveDraft(
            DraftMutation(
                id: snapshot.draftID,
                title: snapshot.title,
                editorDocument: canonicalDocument,
                sourceDocument: stored.sourceDocument,
                disposition: stored.disposition
            ),
            expectedRevision: expectedRevision
        )
    }

    private func persistTerminationSnapshot(
        _ snapshot: CaptureEditorSnapshot
    ) async throws {
        let canonicalDocument = try CaptureBridgeProtocol.canonicalDocument(snapshot.document)
        guard var stored = try await repository.draft(id: snapshot.draftID) else {
            throw CaptureRepositoryError.draftNotFound(snapshot.draftID)
        }
        guard stored.disposition != .abandoned else {
            throw CaptureRepositoryError.abandonedDraftImmutable
        }
        if stored.title == snapshot.title, stored.editorDocument == canonicalDocument {
            return
        }

        do {
            _ = try await saveTerminationSnapshot(
                snapshot,
                canonicalDocument: canonicalDocument,
                stored: stored
            )
        } catch CaptureRepositoryError.staleRevision {
            guard let latest = try await repository.draft(id: snapshot.draftID) else {
                throw CaptureRepositoryError.draftNotFound(snapshot.draftID)
            }
            stored = latest
            if stored.title == snapshot.title, stored.editorDocument == canonicalDocument {
                return
            }
            _ = try await saveTerminationSnapshot(
                snapshot,
                canonicalDocument: canonicalDocument,
                stored: stored
            )
        }
    }

    private func saveTerminationSnapshot(
        _ snapshot: CaptureEditorSnapshot,
        canonicalDocument: Data,
        stored: CaptureDraftSnapshot
    ) async throws -> CaptureDraftSnapshot {
        try await repository.saveDraft(
            DraftMutation(
                id: snapshot.draftID,
                title: snapshot.title,
                editorDocument: canonicalDocument,
                sourceDocument: stored.sourceDocument,
                disposition: stored.disposition
            ),
            expectedRevision: stored.revision
        )
    }

    private func mutation(_ snapshot: CaptureEditorSnapshot, id: String) throws -> DraftMutation {
        DraftMutation(
            id: id,
            title: snapshot.title,
            editorDocument: try CaptureBridgeProtocol.canonicalDocument(snapshot.document),
            sourceDocument: nil,
            disposition: .active
        )
    }

    private func bridgeSnapshot(_ snapshot: CaptureDraftSnapshot) throws -> CaptureEditorSnapshot {
        CaptureEditorSnapshot(
            draftID: snapshot.id,
            title: snapshot.title,
            document: try CaptureBridgeProtocol.canonicalDocument(snapshot.editorDocument),
            revision: snapshot.revision
        )
    }

    private func repositoryFailure(
        _ error: CaptureRepositoryError,
        id: String,
        currentWork: CaptureEditorSnapshot?
    ) async -> CaptureBridgeReply {
        switch error {
        case let .staleRevision(_, actual):
            var latest: CaptureEditorSnapshot?
            if let currentWork,
               let stored = try? await repository.draft(id: currentWork.draftID)
            {
                latest = try? bridgeSnapshot(stored)
            }
            return staleReply(
                id: id,
                currentWork: currentWork,
                latest: latest,
                actualRevision: actual
            )
        case .draftNotFound:
            status = .failed("This draft is no longer available.")
            return .failure(
                id: id,
                code: .draftNotFound,
                message: "This draft is no longer available.",
                recoverable: true
            )
        default:
            status = .failed("Could not persist this draft.")
            return .failure(
                id: id,
                code: .persistenceFailure,
                message: "Could not persist this draft.",
                recoverable: true
            )
        }
    }

    private func staleReply(
        id: String,
        currentWork: CaptureEditorSnapshot?,
        latest: CaptureEditorSnapshot?,
        actualRevision: Int? = nil
    ) -> CaptureBridgeReply {
        if let currentWork, let latest {
            conflict = CaptureConflict(
                currentWork: currentWork,
                latest: latest,
                availableActions: CaptureConflictAction.allCases
            )
        }
        status = .failed("A newer draft revision is available.")
        let suffix = actualRevision.map { " (revision \($0))" } ?? ""
        return .failure(
            id: id,
            code: .staleRevision,
            message: "A newer draft revision is available\(suffix).",
            recoverable: true,
            latest: latest
        )
    }

    private func loadLocalEditor() {
        guard !isDisposed else { return }
        guard editorDocumentURL.isFileURL,
              FileManager.default.fileExists(atPath: editorDocumentURL.path)
        else {
            status = .failed("The bundled editor could not be loaded.")
            return
        }
        webView.loadFileURL(editorDocumentURL, allowingReadAccessTo: resourceRootURL)
    }

    func tearDownBridge() {
        guard installedHandlerNames.remove(CaptureBridgeProtocol.handlerName) != nil else { return }
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: CaptureBridgeProtocol.handlerName,
            contentWorld: .page
        )
        scriptHandler.delegate = nil
        webView.navigationDelegate = nil
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        terminationPersistenceTask?.cancel()
        activeDraftCreationTask?.cancel()
        for transition in inFlightStateTransitions.values {
            transition.task.cancel()
        }
        webView.stopLoading()
        tearDownBridge()
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    func handleNavigation(to url: URL?) -> WKNavigationActionPolicy {
        switch CaptureEditorNavigationPolicy.decision(
            for: url,
            resourceRoot: resourceRootURL
        ) {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .openExternal:
            if let url {
                openURL(url)
            }
            return .cancel
        }
    }

    private static let emptyDocument = Data(
        #"{"content":[{"type":"paragraph"}],"type":"doc"}"#.utf8
    )

    private static var bundledEditorURL: URL {
        CaptureEditorResources.editorURL(
            appResourceRoot: Bundle.main.resourceURL,
            swiftPMResourceRoot: Bundle.module.resourceURL
        )
    }

    private static func editorURL(for roots: CaptureEditorResourceRoots) -> URL {
        CaptureEditorResources.editorURL(
            appResourceRoot: roots.packagedApp,
            swiftPMResourceRoot: roots.swiftPMBundle
        )
    }
}

enum CaptureEditorNavigationDecision: Equatable, Sendable {
    case allow
    case cancel
    case openExternal
}

enum CaptureEditorNavigationPolicy {
    static func decision(for url: URL?, resourceRoot: URL) -> CaptureEditorNavigationDecision {
        guard let url else { return .cancel }
        if url.isFileURL {
            let root = resourceRoot.standardizedFileURL.resolvingSymlinksInPath().path
            let candidate = url.standardizedFileURL.resolvingSymlinksInPath().path
            let rootPrefix = root.hasSuffix("/") ? root : root + "/"
            return candidate.hasPrefix(rootPrefix) ? .allow : .cancel
        }
        switch WebNavigationDestination.classify(url) {
        case .trustedNotion, .externalWeb:
            return .openExternal
        case .unsupported:
            return .cancel
        }
    }
}

extension CaptureEditorSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        handleNavigation(to: navigationAction.request.url)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView,
              !isDisposed,
              !isRecoveringAfterRendererTermination
        else { return }

        isRecoveringAfterRendererTermination = true
        status = .loading
        loadLocalEditor()
    }
}
