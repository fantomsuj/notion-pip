import AppKit
import Combine
import Foundation
import UserNotifications

typealias AgentStreamReceiptCancellation = @MainActor () -> Void
typealias AgentStreamReceiptScheduler = @MainActor (
    _ delay: Duration,
    _ operation: @escaping @MainActor () -> Void
) -> AgentStreamReceiptCancellation

typealias AgentStreamIDGenerator = @Sendable () -> UUID
typealias AgentStreamClock = @Sendable () -> Date

@MainActor
protocol AgentStreamTarget: AnyObject {
    /// True when a Notion page is loaded and likely editable (does not require a cursor).
    var isAgentStreamTargetAvailable: Bool { get }

    /// Opaque page identity for diagnostics only; never returned as a URL/title.
    var agentStreamOpaquePageID: String? { get }

    /// Capture the current editor cursor immediately before paste-on-accept.
    func rememberCurrentEditorCursor(
        completion: @escaping @MainActor (Bool) -> Void
    )

    /// Paste Markdown at the saved cursor so Notion converts structure.
    func pasteMarkdownAtSavedEditorCursor(
        _ markdown: String,
        completion: @escaping @MainActor (Bool) -> Void
    )
}

@MainActor
protocol AgentStreamNotifying: AnyObject {
    func notifyStreamReady(label: String, streamID: UUID)
    func clearStreamNotifications()
}

@MainActor
final class AgentStreamUserNotifier: AgentStreamNotifying {
    static let categoryIdentifier = "perch.agent-stream.ready"
    static let acceptActionIdentifier = "perch.agent-stream.accept"
    static let dismissActionIdentifier = "perch.agent-stream.dismiss"

    private let center: UNUserNotificationCenter
    private var didRequestAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    static func installNotificationCenterDelegate(
        _ delegate: UNUserNotificationCenterDelegate
    ) {
        UNUserNotificationCenter.current().delegate = delegate
    }

    func registerCategoriesIfNeeded() {
        let accept = UNNotificationAction(
            identifier: Self.acceptActionIdentifier,
            title: AgentStreamUserFacingCopy.acceptButton,
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: Self.dismissActionIdentifier,
            title: AgentStreamUserFacingCopy.dismissButton,
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [accept, dismiss],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func notifyStreamReady(label: String, streamID: UUID) {
        registerCategoriesIfNeeded()
        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted else { return }
            let content = UNMutableNotificationContent()
            content.title = AgentStreamUserFacingCopy.readyTitle
            content.body =
                "\(label): \(AgentStreamUserFacingCopy.readyBodyPrefix)."
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["streamID": streamID.uuidString]
            let request = UNNotificationRequest(
                identifier: streamID.uuidString,
                content: content,
                trigger: nil
            )
            self.center.add(request)
        }
    }

    func clearStreamNotifications() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    private func requestAuthorizationIfNeeded(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if didRequestAuthorization {
            center.getNotificationSettings { settings in
                let authorized = settings.authorizationStatus == .authorized
                Task { @MainActor in
                    completion(authorized)
                }
            }
            return
        }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                completion(granted)
            }
        }
    }
}

@MainActor
final class AgentStreamController: ObservableObject {
    static let successReceiptDuration: Duration = .milliseconds(900)

    @Published private(set) var snapshot: AgentStreamSnapshot?
    @Published private(set) var overlayPresentation: AgentStreamOverlayPresentation = .hidden

    private weak var target: (any AgentStreamTarget)?
    private let notifier: any AgentStreamNotifying
    private let limits: AgentStreamLimits
    private let idGenerator: AgentStreamIDGenerator
    private let clock: AgentStreamClock
    private let receiptScheduler: AgentStreamReceiptScheduler
    private var createIdempotency: [String: UUID] = [:]
    private var lastActivityAt: Date?
    private var cancelSuccessReceipt: AgentStreamReceiptCancellation?
    private var assembledBuffer = ""
    private var lastAcceptedSequence: Int = -1

    init(
        target: any AgentStreamTarget,
        notifier: any AgentStreamNotifying = AgentStreamUserNotifier(),
        limits: AgentStreamLimits = .default,
        idGenerator: @escaping AgentStreamIDGenerator = { UUID() },
        clock: @escaping AgentStreamClock = { Date() },
        receiptScheduler: @escaping AgentStreamReceiptScheduler = scheduleAgentStreamReceipt
    ) {
        self.target = target
        self.notifier = notifier
        self.limits = limits
        self.idGenerator = idGenerator
        self.clock = clock
        self.receiptScheduler = receiptScheduler
    }

    func bind(target: any AgentStreamTarget) {
        self.target = target
    }

    func status() -> AgentStreamServerStatus {
        expireIfNeeded()
        let active = snapshot.flatMap { $0.occupiesActiveSlot ? $0 : nil }
        return AgentStreamServerStatus(
            ready: true,
            targetAvailable: target?.isAgentStreamTargetAvailable ?? false,
            limits: limits,
            activeStreamID: active?.id,
            activeStreamPhase: active?.phase
        )
    }

    @discardableResult
    func create(_ request: AgentStreamCreateRequest) throws -> AgentStreamCreateResult {
        expireIfNeeded()

        if let existingID = createIdempotency[request.idempotencyKey],
           let existing = snapshot,
           existing.id == existingID
        {
            return AgentStreamCreateResult(snapshot: existing, limits: limits)
        }

        if let current = snapshot, current.occupiesActiveSlot {
            throw AgentStreamError.streamActive()
        }

        guard request.commitMode == .acceptToPaste else {
            throw AgentStreamError.invalidRequest(
                "Unsupported commitMode. Use accept_to_paste."
            )
        }
        guard request.contentType == .markdown else {
            throw AgentStreamError.invalidRequest(
                "Unsupported contentType. Use text/markdown."
            )
        }
        let client = request.client.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !client.isEmpty, client.utf8.count <= 128 else {
            throw AgentStreamError.invalidRequest("client is required.")
        }
        let label = normalizedLabel(request.label, fallbackClient: client)

        cancelPendingSuccessReceipt()
        notifier.clearStreamNotifications()
        assembledBuffer = ""
        lastAcceptedSequence = -1

        let id = idGenerator()
        createIdempotency[request.idempotencyKey] = id
        let created = AgentStreamSnapshot(
            id: id,
            label: label,
            client: client,
            contentType: request.contentType,
            phase: .receiving,
            assembledText: "",
            nextSequence: 0,
            opaquePageID: target?.agentStreamOpaquePageID,
            errorMessage: nil,
            canAccept: false,
            showsOverlay: true
        )
        publish(created)
        touch()
        return AgentStreamCreateResult(snapshot: created, limits: limits)
    }

    @discardableResult
    func append(streamID: UUID, chunk: AgentStreamChunk) throws -> AgentStreamSnapshot {
        expireIfNeeded()
        guard var current = snapshot, current.id == streamID else {
            throw AgentStreamError.streamGone()
        }
        guard current.phase == .receiving else {
            throw AgentStreamError.streamGone()
        }

        if chunk.sequence == lastAcceptedSequence {
            return current
        }
        guard chunk.sequence == current.nextSequence else {
            throw AgentStreamError.sequenceMismatch(expected: current.nextSequence)
        }
        let chunkBytes = chunk.text.utf8.count
        guard chunkBytes <= limits.maxChunkUTF8Bytes else {
            throw AgentStreamError.payloadTooLarge("Chunk exceeds the 32 KiB limit.")
        }
        let nextAssembledBytes = assembledBuffer.utf8.count + chunkBytes
        guard nextAssembledBytes <= limits.maxAssembledUTF8Bytes else {
            throw AgentStreamError.payloadTooLarge(
                "Assembled response exceeds the 512 KiB limit."
            )
        }

        assembledBuffer += chunk.text
        lastAcceptedSequence = chunk.sequence
        current = AgentStreamSnapshot(
            id: current.id,
            label: current.label,
            client: current.client,
            contentType: current.contentType,
            phase: .receiving,
            assembledText: assembledBuffer,
            nextSequence: chunk.sequence + 1,
            opaquePageID: current.opaquePageID,
            errorMessage: nil,
            canAccept: false,
            showsOverlay: true
        )
        publish(current)
        touch()
        return current
    }

    /// Agent signals input is finished. Does not write to Notion.
    @discardableResult
    func complete(streamID: UUID) throws -> AgentStreamSnapshot {
        expireIfNeeded()
        guard var current = snapshot, current.id == streamID else {
            throw AgentStreamError.streamGone()
        }
        switch current.phase {
        case .ready, .inserting, .inserted, .failed:
            // Idempotent complete while awaiting/replaying accept.
            return current
        case .cancelled, .expired:
            throw AgentStreamError.streamGone()
        case .receiving:
            break
        }

        current = AgentStreamSnapshot(
            id: current.id,
            label: current.label,
            client: current.client,
            contentType: current.contentType,
            phase: .ready,
            assembledText: assembledBuffer,
            nextSequence: current.nextSequence,
            opaquePageID: current.opaquePageID,
            errorMessage: nil,
            canAccept: true,
            showsOverlay: true
        )
        publish(current)
        touch()
        notifier.notifyStreamReady(label: current.label, streamID: current.id)
        return current
    }

    @discardableResult
    func cancel(streamID: UUID) throws -> AgentStreamSnapshot {
        expireIfNeeded()
        guard let current = snapshot, current.id == streamID else {
            throw AgentStreamError.streamGone()
        }
        if current.phase == .cancelled {
            return current
        }
        guard current.phase == .receiving
            || current.phase == .ready
            || current.phase == .failed
            || current.phase == .inserting
        else {
            throw AgentStreamError.streamGone()
        }
        return finalizeCancellation(of: current)
    }

    func stream(id: UUID) throws -> AgentStreamSnapshot {
        expireIfNeeded()
        guard let current = snapshot, current.id == id else {
            throw AgentStreamError.streamGone()
        }
        return current
    }

    /// User Accept: capture the live cursor, then paste Markdown once.
    func accept() {
        expireIfNeeded()
        guard let current = snapshot,
              current.canAccept || current.phase == .failed,
              current.phase == .ready || current.phase == .failed
        else {
            return
        }
        guard let target else {
            publishFailed(current, message: AgentStreamUserFacingCopy.clickFirstHint)
            return
        }

        let streamID = current.id
        let markdown = assembledBuffer
        publish(
            AgentStreamSnapshot(
                id: current.id,
                label: current.label,
                client: current.client,
                contentType: current.contentType,
                phase: .inserting,
                assembledText: markdown,
                nextSequence: current.nextSequence,
                opaquePageID: current.opaquePageID,
                errorMessage: nil,
                canAccept: false,
                showsOverlay: true
            )
        )
        touch()

        target.rememberCurrentEditorCursor { [weak self] remembered in
            guard let self,
                  let latest = self.snapshot,
                  latest.id == streamID,
                  latest.phase == .inserting
            else {
                return
            }
            guard remembered else {
                self.publishFailed(
                    latest,
                    message: AgentStreamUserFacingCopy.clickFirstHint
                )
                return
            }
            target.pasteMarkdownAtSavedEditorCursor(markdown) { [weak self] inserted in
                guard let self,
                      let latest = self.snapshot,
                      latest.id == streamID,
                      latest.phase == .inserting
                else {
                    return
                }
                if inserted {
                    self.finishSuccessfulPaste(of: latest)
                } else {
                    self.publishFailed(
                        latest,
                        message: AgentStreamError.targetChanged().message
                    )
                }
            }
        }
    }

    func stopFromOverlay() {
        guard let current = snapshot, current.occupiesActiveSlot else { return }
        _ = try? cancel(streamID: current.id)
    }

    func dismissFromOverlay() {
        guard let current = snapshot else { return }
        switch current.phase {
        case .ready, .failed, .cancelled, .expired, .inserted:
            clearOverlayAndBuffer(retainingMetadata: current)
        case .receiving, .inserting:
            _ = try? cancel(streamID: current.id)
        }
    }

    func copyAssembledTextToPasteboard(
        pasteboard: NSPasteboard = .general
    ) {
        guard let text = snapshot?.assembledText, !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func prepareForTermination() {
        cancelPendingSuccessReceipt()
        notifier.clearStreamNotifications()
        if let current = snapshot, current.phase == .receiving || current.phase == .ready {
            publish(
                AgentStreamSnapshot(
                    id: current.id,
                    label: current.label,
                    client: current.client,
                    contentType: current.contentType,
                    phase: .cancelled,
                    assembledText: "",
                    nextSequence: current.nextSequence,
                    opaquePageID: current.opaquePageID,
                    errorMessage: nil,
                    canAccept: false,
                    showsOverlay: false
                )
            )
        }
        assembledBuffer = ""
        lastAcceptedSequence = -1
        lastActivityAt = nil
        snapshot = nil
        overlayPresentation = .hidden
    }

    // MARK: - Private

    private func finalizeCancellation(
        of current: AgentStreamSnapshot
    ) -> AgentStreamSnapshot {
        cancelPendingSuccessReceipt()
        notifier.clearStreamNotifications()
        let cancelled = AgentStreamSnapshot(
            id: current.id,
            label: current.label,
            client: current.client,
            contentType: current.contentType,
            phase: .cancelled,
            assembledText: "",
            nextSequence: current.nextSequence,
            opaquePageID: current.opaquePageID,
            errorMessage: nil,
            canAccept: false,
            showsOverlay: false
        )
        assembledBuffer = ""
        lastAcceptedSequence = -1
        publish(cancelled)
        touch()
        return cancelled
    }

    private func finishSuccessfulPaste(of current: AgentStreamSnapshot) {
        notifier.clearStreamNotifications()
        assembledBuffer = ""
        let inserted = AgentStreamSnapshot(
            id: current.id,
            label: current.label,
            client: current.client,
            contentType: current.contentType,
            phase: .inserted,
            assembledText: "",
            nextSequence: current.nextSequence,
            opaquePageID: current.opaquePageID,
            errorMessage: nil,
            canAccept: false,
            showsOverlay: true
        )
        publish(inserted)
        touch()
        cancelSuccessReceipt = receiptScheduler(Self.successReceiptDuration) {
            [weak self] in
            guard let self,
                  let latest = self.snapshot,
                  latest.id == inserted.id,
                  latest.phase == .inserted
            else {
                return
            }
            self.cancelSuccessReceipt = nil
            self.clearOverlayAndBuffer(retainingMetadata: latest)
        }
    }

    private func publishFailed(_ current: AgentStreamSnapshot, message: String) {
        let failed = AgentStreamSnapshot(
            id: current.id,
            label: current.label,
            client: current.client,
            contentType: current.contentType,
            phase: .failed,
            assembledText: assembledBuffer,
            nextSequence: current.nextSequence,
            opaquePageID: current.opaquePageID,
            errorMessage: message,
            canAccept: true,
            showsOverlay: true
        )
        publish(failed)
        touch()
    }

    private func clearOverlayAndBuffer(retainingMetadata current: AgentStreamSnapshot) {
        cancelPendingSuccessReceipt()
        notifier.clearStreamNotifications()
        assembledBuffer = ""
        publish(
            AgentStreamSnapshot(
                id: current.id,
                label: current.label,
                client: current.client,
                contentType: current.contentType,
                phase: current.phase == .inserted ? .inserted : .cancelled,
                assembledText: "",
                nextSequence: current.nextSequence,
                opaquePageID: current.opaquePageID,
                errorMessage: nil,
                canAccept: false,
                showsOverlay: false
            )
        )
    }

    private func publish(_ snapshot: AgentStreamSnapshot) {
        self.snapshot = snapshot
        overlayPresentation = .from(snapshot: snapshot)
    }

    private func touch() {
        lastActivityAt = clock()
    }

    private func expireIfNeeded() {
        guard let current = snapshot, let lastActivityAt else { return }
        let now = clock()
        let elapsed = now.timeIntervalSince(lastActivityAt)

        switch current.phase {
        case .receiving:
            if elapsed >= limits.inactiveExpiration.timeInterval {
                publish(
                    AgentStreamSnapshot(
                        id: current.id,
                        label: current.label,
                        client: current.client,
                        contentType: current.contentType,
                        phase: .expired,
                        assembledText: "",
                        nextSequence: current.nextSequence,
                        opaquePageID: current.opaquePageID,
                        errorMessage: nil,
                        canAccept: false,
                        showsOverlay: false
                    )
                )
                assembledBuffer = ""
                notifier.clearStreamNotifications()
            }
        case .ready, .failed:
            if elapsed >= limits.readyRetention.timeInterval {
                publish(
                    AgentStreamSnapshot(
                        id: current.id,
                        label: current.label,
                        client: current.client,
                        contentType: current.contentType,
                        phase: .expired,
                        assembledText: "",
                        nextSequence: current.nextSequence,
                        opaquePageID: current.opaquePageID,
                        errorMessage: nil,
                        canAccept: false,
                        showsOverlay: false
                    )
                )
                assembledBuffer = ""
                notifier.clearStreamNotifications()
            }
        case .inserted, .cancelled, .expired:
            if elapsed >= limits.terminalRetention.timeInterval {
                snapshot = nil
                overlayPresentation = .hidden
                self.lastActivityAt = nil
            }
        case .inserting:
            break
        }
    }

    private func normalizedLabel(_ label: String?, fallbackClient: String) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return fallbackClient
        }
        if trimmed.utf8.count > 64 {
            let end = trimmed.index(
                trimmed.startIndex,
                offsetBy: 64,
                limitedBy: trimmed.endIndex
            ) ?? trimmed.endIndex
            return String(trimmed[..<end])
        }
        return trimmed
    }

    private func cancelPendingSuccessReceipt() {
        cancelSuccessReceipt?()
        cancelSuccessReceipt = nil
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

@MainActor
private func scheduleAgentStreamReceipt(
    after delay: Duration,
    operation: @escaping @MainActor () -> Void
) -> AgentStreamReceiptCancellation {
    let task = Task { @MainActor in
        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        operation()
    }
    return { task.cancel() }
}
