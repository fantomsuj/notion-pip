import Combine
import Foundation

typealias QuickCopyReceiptCancellation = @MainActor () -> Void
typealias QuickCopyReceiptScheduler = @MainActor (
    _ delay: Duration,
    _ operation: @escaping @MainActor () -> Void
) -> QuickCopyReceiptCancellation

enum QuickCopyState: Equatable, Sendable {
    case off
    case requestingPermission
    case permissionNeeded
    case armed
    case inserting
    case added
    case warning(String)
    case failed(String)

    var isSessionActive: Bool {
        switch self {
        case .requestingPermission, .armed, .inserting, .added, .warning:
            true
        case .off, .permissionNeeded, .failed:
            false
        }
    }
}

enum QuickCopyMonitorEvent: Equatable, Sendable {
    case candidate(QuickCopyCandidate)
    case unsupportedSource(String?)
    case secureSource
    case permissionRevoked
}

@MainActor
protocol QuickCopyMonitoring: AnyObject {
    var onEvent: (@MainActor (QuickCopyMonitorEvent) -> Void)? { get set }
    func requestAccessibilityAccess() -> Bool
    func start()
    func stop()
}

@MainActor
protocol QuickCopyInsertionTarget: AnyObject {
    var onQuickCopyTargetInvalidated: (@MainActor () -> Void)? { get set }

    func rememberCurrentEditorCursor(
        completion: @escaping @MainActor (Bool) -> Void
    )

    func insertAtSavedEditorCursor(
        _ text: String,
        completion: @escaping @MainActor (Bool) -> Void
    )
}

@MainActor
final class QuickCopyController: ObservableObject {
    static let successReceiptDuration: Duration = .milliseconds(650)
    static let missingCursorMessage = "Click in the Notion page first."
    static let staleCursorMessage =
        "The Notion cursor changed. Click in the page, then retry."
    static let busyMessage =
        "Quick Copy is busy. This selection wasn’t added; try again shortly."

    @Published private(set) var state: QuickCopyState = .off

    private let monitor: any QuickCopyMonitoring
    private weak var target: (any QuickCopyInsertionTarget)?
    private let policy: QuickCopyPolicy
    private let receiptScheduler: QuickCopyReceiptScheduler
    private var pendingCandidates: QuickCopyCandidateBuffer
    private var failedCandidate: QuickCopyCandidate?
    private var lastAcceptedSequence: UInt64?
    private var deferredWarningMessage: String?
    private var cancelSuccessReceipt: QuickCopyReceiptCancellation?

    init(
        monitor: any QuickCopyMonitoring,
        target: any QuickCopyInsertionTarget,
        policy: QuickCopyPolicy = QuickCopyPolicy(),
        pendingCandidateCapacity: Int = QuickCopyCandidateBuffer.standardCapacity,
        receiptScheduler: @escaping QuickCopyReceiptScheduler = scheduleQuickCopyReceipt
    ) {
        self.monitor = monitor
        self.target = target
        self.policy = policy
        self.receiptScheduler = receiptScheduler
        pendingCandidates = QuickCopyCandidateBuffer(capacity: pendingCandidateCapacity)
        monitor.onEvent = { [weak self] event in
            self?.handle(event)
        }
        target.onQuickCopyTargetInvalidated = { [weak self] in
            self?.targetDidInvalidate()
        }
    }

    func toggle() {
        if state.isSessionActive {
            disable()
        } else {
            beginEnabling()
        }
    }

    func disable() {
        cancelPendingSuccessReceipt()
        let wasActive = state.isSessionActive
        if wasActive {
            monitor.stop()
        }
        pendingCandidates.removeAll()
        failedCandidate = nil
        lastAcceptedSequence = nil
        deferredWarningMessage = nil
        state = .off
    }

    func prepareForTermination() {
        cancelPendingSuccessReceipt()
        if state.isSessionActive {
            monitor.stop()
        }
        pendingCandidates.removeAll()
        failedCandidate = nil
        lastAcceptedSequence = nil
        deferredWarningMessage = nil
        state = .off
    }

    private func beginEnabling() {
        guard let target else {
            state = .failed(Self.missingCursorMessage)
            return
        }
        pendingCandidates.removeAll()
        lastAcceptedSequence = nil
        deferredWarningMessage = nil
        state = .requestingPermission
        target.rememberCurrentEditorCursor { [weak self] remembered in
            guard let self, self.state == .requestingPermission else { return }
            guard remembered else {
                self.failedCandidate = nil
                self.state = .failed(Self.missingCursorMessage)
                return
            }
            guard self.monitor.requestAccessibilityAccess() else {
                self.state = .permissionNeeded
                return
            }
            self.state = .armed
            self.monitor.start()
            guard self.state == .armed else { return }
            if let failedCandidate = self.failedCandidate {
                self.failedCandidate = nil
                switch self.pendingCandidates.enqueue(failedCandidate) {
                case .accepted:
                    self.insertNextCandidateIfNeeded()
                case .atCapacity:
                    self.failedCandidate = failedCandidate
                    self.monitor.stop()
                    self.state = .failed(Self.staleCursorMessage)
                }
            }
        }
    }

    private func handle(_ event: QuickCopyMonitorEvent) {
        guard state.isSessionActive else { return }
        switch event {
        case let .candidate(candidate):
            handle(candidate)
        case let .unsupportedSource(applicationName):
            showWarning(unsupportedMessage(applicationName))
        case .secureSource:
            showWarning("Quick Copy ignores secure text fields.")
        case .permissionRevoked:
            cancelPendingSuccessReceipt()
            monitor.stop()
            pendingCandidates.removeAll()
            failedCandidate = nil
            lastAcceptedSequence = nil
            deferredWarningMessage = nil
            state = .permissionNeeded
        }
    }

    private func handle(_ candidate: QuickCopyCandidate) {
        switch policy.decision(
            for: candidate,
            lastAcceptedSequence: lastAcceptedSequence
        ) {
        case .accept:
            switch pendingCandidates.enqueue(candidate) {
            case .accepted:
                lastAcceptedSequence = candidate.sequence
                insertNextCandidateIfNeeded()
            case .atCapacity:
                showWarning(Self.busyMessage)
            }
        case .ignore:
            break
        case let .reject(rejection):
            showWarning(message(for: rejection))
        }
    }

    private func insertNextCandidateIfNeeded() {
        guard state != .inserting, let candidate = pendingCandidates.front else {
            return
        }
        beginInsertion(of: candidate)
    }

    private func beginInsertion(of candidate: QuickCopyCandidate) {
        cancelPendingSuccessReceipt()
        guard let target else {
            failInsertion(of: candidate)
            return
        }
        state = .inserting
        target.insertAtSavedEditorCursor(candidate.text) { [weak self] inserted in
            guard let self, self.state == .inserting,
                  self.pendingCandidates.front == candidate
            else {
                return
            }
            guard inserted else {
                self.failInsertion(of: candidate)
                return
            }
            _ = self.pendingCandidates.dequeue()
            if let nextCandidate = self.pendingCandidates.front {
                self.beginInsertion(of: nextCandidate)
            } else {
                self.finishCandidateDrain()
            }
        }
    }

    private func finishCandidateDrain() {
        if let deferredWarningMessage {
            self.deferredWarningMessage = nil
            state = .warning(deferredWarningMessage)
        } else {
            state = .added
            cancelSuccessReceipt = receiptScheduler(Self.successReceiptDuration) {
                [weak self] in
                guard let self, state == .added else { return }
                cancelSuccessReceipt = nil
                state = .armed
            }
        }
    }

    private func failInsertion(of candidate: QuickCopyCandidate) {
        failedCandidate = candidate
        pendingCandidates.removeAll()
        deferredWarningMessage = nil
        monitor.stop()
        state = .failed(Self.staleCursorMessage)
    }

    private func targetDidInvalidate() {
        guard state.isSessionActive else { return }
        cancelPendingSuccessReceipt()
        monitor.stop()
        pendingCandidates.removeAll()
        failedCandidate = nil
        lastAcceptedSequence = nil
        deferredWarningMessage = nil
        state = .off
    }

    private func showWarning(_ message: String) {
        if state == .inserting {
            deferredWarningMessage = message
        } else {
            cancelPendingSuccessReceipt()
            state = .warning(message)
        }
    }

    private func cancelPendingSuccessReceipt() {
        cancelSuccessReceipt?()
        cancelSuccessReceipt = nil
    }

    private func message(for rejection: QuickCopyRejection) -> String {
        switch rejection {
        case .secureField:
            "Quick Copy ignores secure text fields."
        case let .unsupportedSource(applicationName):
            unsupportedMessage(applicationName)
        case .oversized:
            "That selection is too large for Quick Copy."
        }
    }

    private func unsupportedMessage(_ applicationName: String?) -> String {
        if let applicationName, !applicationName.isEmpty {
            return "\(applicationName) doesn’t expose selected text."
        }
        return "This app doesn’t expose selected text."
    }
}

@MainActor
private func scheduleQuickCopyReceipt(
    after delay: Duration,
    operation: @escaping @MainActor () -> Void
) -> QuickCopyReceiptCancellation {
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
