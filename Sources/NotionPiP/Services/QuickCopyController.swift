import Combine
import Foundation

enum QuickCopyState: Equatable, Sendable {
    case off
    case requestingPermission
    case permissionNeeded
    case armed
    case inserting
    case warning(String)
    case failed(String)

    var isSessionActive: Bool {
        switch self {
        case .requestingPermission, .armed, .inserting, .warning:
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
    static let missingCursorMessage = "Click in the Notion page first."
    static let staleCursorMessage =
        "The Notion cursor changed. Click in the page, then retry."

    @Published private(set) var state: QuickCopyState = .off

    private let monitor: any QuickCopyMonitoring
    private weak var target: (any QuickCopyInsertionTarget)?
    private let policy: QuickCopyPolicy
    private var pendingCandidates: [QuickCopyCandidate] = []
    private var failedCandidate: QuickCopyCandidate?
    private var lastAcceptedSequence: UInt64?
    private var deferredWarningMessage: String?

    init(
        monitor: any QuickCopyMonitoring,
        target: any QuickCopyInsertionTarget,
        policy: QuickCopyPolicy = QuickCopyPolicy()
    ) {
        self.monitor = monitor
        self.target = target
        self.policy = policy
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
        let wasActive = state.isSessionActive
        if wasActive {
            monitor.stop()
        }
        pendingCandidates.removeAll(keepingCapacity: false)
        failedCandidate = nil
        lastAcceptedSequence = nil
        deferredWarningMessage = nil
        state = .off
    }

    func prepareForTermination() {
        if state.isSessionActive {
            monitor.stop()
        }
        pendingCandidates.removeAll(keepingCapacity: false)
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
        pendingCandidates.removeAll(keepingCapacity: false)
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
                self.pendingCandidates.append(failedCandidate)
                self.insertNextCandidateIfNeeded()
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
            monitor.stop()
            pendingCandidates.removeAll(keepingCapacity: false)
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
            lastAcceptedSequence = candidate.sequence
            pendingCandidates.append(candidate)
            insertNextCandidateIfNeeded()
        case .ignore:
            break
        case let .reject(rejection):
            showWarning(message(for: rejection))
        }
    }

    private func insertNextCandidateIfNeeded() {
        guard state != .inserting, let candidate = pendingCandidates.first else {
            return
        }
        guard let target else {
            failInsertion(of: candidate)
            return
        }
        state = .inserting
        target.insertAtSavedEditorCursor(candidate.text) { [weak self] inserted in
            guard let self, self.state == .inserting,
                  self.pendingCandidates.first == candidate
            else {
                return
            }
            guard inserted else {
                self.failInsertion(of: candidate)
                return
            }
            self.pendingCandidates.removeFirst()
            if let deferredWarningMessage = self.deferredWarningMessage {
                self.deferredWarningMessage = nil
                self.state = .warning(deferredWarningMessage)
            } else {
                self.state = .armed
            }
            self.insertNextCandidateIfNeeded()
        }
    }

    private func failInsertion(of candidate: QuickCopyCandidate) {
        failedCandidate = candidate
        pendingCandidates.removeAll(keepingCapacity: false)
        deferredWarningMessage = nil
        monitor.stop()
        state = .failed(Self.staleCursorMessage)
    }

    private func targetDidInvalidate() {
        guard state.isSessionActive else { return }
        monitor.stop()
        pendingCandidates.removeAll(keepingCapacity: false)
        failedCandidate = nil
        lastAcceptedSequence = nil
        deferredWarningMessage = nil
        state = .off
    }

    private func showWarning(_ message: String) {
        if state == .inserting {
            deferredWarningMessage = message
        } else {
            state = .warning(message)
        }
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
