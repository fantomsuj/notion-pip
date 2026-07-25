import Foundation

enum QuickCaptureCloseOutcome: Equatable, Sendable {
    case discarded
    case enqueued(recordID: String)
    case needsConfiguration(String)
    case failed(String)
}

actor QuickCaptureLifecycleCoordinator {
    private let repository: CaptureRepository
    private let destinations: any QuickCaptureDestinationPersisting
    private let hasUsableToken: @Sendable () async -> Bool
    private let onEnqueued: @Sendable (String) async -> Void

    init(
        repository: CaptureRepository,
        destinations: any QuickCaptureDestinationPersisting,
        hasUsableToken: @escaping @Sendable () async -> Bool,
        onEnqueued: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.repository = repository
        self.destinations = destinations
        self.hasUsableToken = hasUsableToken
        self.onEnqueued = onEnqueued
    }

    func close(snapshot: CaptureEditorSnapshot) async -> QuickCaptureCloseOutcome {
        do {
            guard let expectedRevision = snapshot.revision,
                  let stored = try await repository.draft(id: snapshot.draftID)
            else {
                return .failed("The latest capture could not be saved.")
            }
            let canonicalDocument = try CaptureBridgeProtocol.canonicalDocument(
                snapshot.document
            )
            let saved: CaptureDraftSnapshot
            if stored.title == snapshot.title,
               stored.editorDocument == canonicalDocument
            {
                saved = stored
            } else {
                saved = try await repository.saveDraft(
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

            if snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               CaptureDocumentContent.isEmpty(canonicalDocument)
            {
                try await repository.discardDraft(
                    id: saved.id,
                    expectedRevision: saved.revision
                )
                return .discarded
            }

            guard let destination = try await destinations.defaultDestination() else {
                return .needsConfiguration(
                    "Choose a Quick Capture destination in Settings."
                )
            }
            guard await hasUsableToken() else {
                return .needsConfiguration(
                    "Reconnect your Notion personal access token in Settings."
                )
            }

            let record = try await repository.enqueue(
                draftID: saved.id,
                expectedRevision: saved.revision,
                destination: destination.captureDestination
            )
            await onEnqueued(record.id)
            return .enqueued(recordID: record.id)
        } catch {
            return .failed("The latest capture could not be saved.")
        }
    }
}

enum CaptureDocumentContent {
    static func isEmpty(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "doc"
        else {
            return false
        }
        return !(root["content"] as? [Any] ?? []).contains(where: hasContent)
    }

    private static func hasContent(_ value: Any) -> Bool {
        guard let node = value as? [String: Any],
              let type = node["type"] as? String
        else {
            return true
        }
        switch type {
        case "text":
            return !((node["text"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        case "doc", "paragraph", "heading", "blockquote", "bulletList",
             "orderedList", "listItem", "taskList", "codeBlock":
            return (node["content"] as? [Any] ?? []).contains(where: hasContent)
        case "hardBreak":
            return false
        case "taskItem", "horizontalRule":
            return true
        default:
            return true
        }
    }
}
