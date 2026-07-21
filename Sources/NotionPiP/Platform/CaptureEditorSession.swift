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

struct CaptureConflict: Equatable, Sendable {
    let currentWork: CaptureEditorSnapshot
    let latest: CaptureEditorSnapshot
    let availableActions: [CaptureConflictAction]
}

@MainActor
protocol CaptureReplyApplying: AnyObject {
    func apply(_ reply: CaptureBridgeReply, to webView: WKWebView) async throws
}

@MainActor
final class WebKitCaptureReplyApplier: CaptureReplyApplying {
    func apply(_ reply: CaptureBridgeReply, to webView: WKWebView) async throws {
        let replyObject = try CaptureBridgeProtocol.replyObject(reply)
        _ = try await webView.callAsyncJavaScript(
            "return window.NotionPiPBridge.applyNativeReply(reply)",
            arguments: ["reply": replyObject],
            in: nil,
            contentWorld: .page
        )
    }
}

@MainActor
final class CaptureEditorSession: NSObject, ObservableObject, CaptureScriptMessageHandling {
    @Published private(set) var status: CaptureEditorStatus = .loading
    @Published private(set) var conflict: CaptureConflict?

    let webView: WKWebView
    let installedHandlerNames: Set<String> = [CaptureBridgeProtocol.handlerName]

    private let repository: CaptureRepository
    private let draftID: () -> String
    private let openInNotion: () -> Void
    private let replyApplier: any CaptureReplyApplying
    private let scriptHandler: WeakScriptMessageHandler
    private let editorDocumentURL: URL
    private let resourceRootURL: URL

    init(
        repository: CaptureRepository,
        draftID: @escaping () -> String = { UUID().uuidString.lowercased() },
        openInNotion: @escaping () -> Void = {},
        replyApplier: any CaptureReplyApplying = WebKitCaptureReplyApplier()
    ) {
        self.repository = repository
        self.draftID = draftID
        self.openInNotion = openInNotion
        self.replyApplier = replyApplier

        let documentURL = Self.bundledEditorURL
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
        webView.setValue(false, forKey: "drawsBackground")

        super.init()
        handler.delegate = self
        webView.navigationDelegate = self
        loadLocalEditor()
    }

    func handleScriptMessage(_ request: CaptureBridgeRequest) async -> CaptureBridgeReply {
        await handle(request)
    }

    func handle(_ request: CaptureBridgeRequest) async -> CaptureBridgeReply {
        do {
            switch request {
            case let .ready(id):
                let snapshot = try await activeOrNewDraft()
                status = .ready
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
                guard let stored = try await repository.draft(id: snapshot.draftID) else {
                    return .failure(
                        id: id,
                        code: .draftNotFound,
                        message: "This draft is no longer available.",
                        recoverable: true
                    )
                }
                guard stored.revision == expectedRevision else {
                    let latest = try bridgeSnapshot(stored)
                    return staleReply(id: id, currentWork: snapshot, latest: latest)
                }
                status = .saved(revision: stored.revision)
                return .success(id: id, result: .saved(revision: stored.revision))

            case let .stash(id, snapshot, expectedRevision):
                do {
                    _ = try await repository.stashDraft(
                        id: snapshot.draftID,
                        expectedRevision: expectedRevision
                    )
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
                return try await resolveConflict(id: id, action: action, snapshot: snapshot)
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
        guard let originalConflict = conflict else { return }
        let reply = await handle(
            .resolveConflict(
                id: UUID().uuidString.lowercased(),
                action: action,
                snapshot: originalConflict.currentWork
            )
        )
        guard action != .openInNotion, reply.result != nil else { return }
        do {
            try await replyApplier.apply(reply, to: webView)
        } catch {
            conflict = originalConflict
            status = .failed("The editor could not apply the recovered draft.")
        }
    }

    private func resolveConflict(
        id: String,
        action: CaptureConflictAction,
        snapshot: CaptureEditorSnapshot
    ) async throws -> CaptureBridgeReply {
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
    }

    private func activeOrNewDraft() async throws -> CaptureEditorSnapshot {
        if let active = try await repository.drafts().first(where: { $0.disposition == .active }) {
            return try bridgeSnapshot(active)
        }
        let id = draftID()
        let created = try await repository.saveDraft(
            DraftMutation(
                id: id,
                title: "",
                editorDocument: Self.emptyDocument,
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        return try bridgeSnapshot(created)
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
        guard editorDocumentURL.isFileURL,
              FileManager.default.fileExists(atPath: editorDocumentURL.path)
        else {
            status = .failed("The bundled editor could not be loaded.")
            return
        }
        webView.loadFileURL(editorDocumentURL, allowingReadAccessTo: resourceRootURL)
    }

    private static let emptyDocument = Data(
        #"{"content":[{"type":"paragraph"}],"type":"doc"}"#.utf8
    )

    private static var bundledEditorURL: URL {
        Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "QuickCapture"
        ) ?? URL(fileURLWithPath: "/__missing_NotionPiP_QuickCapture__/index.html")
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
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "notion.so" || host == "www.notion.so"
        else {
            return .cancel
        }
        return .openExternal
    }
}

extension CaptureEditorSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        switch CaptureEditorNavigationPolicy.decision(
            for: navigationAction.request.url,
            resourceRoot: resourceRootURL
        ) {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .openExternal:
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
    }
}
