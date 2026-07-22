import Foundation
import OSLog

enum PerformanceOperation: String, CaseIterable, Sendable {
    case coldLaunchToStatusItem = "ColdLaunchToStatusItem"
    case firstPiPPresentation = "FirstPiPPresentation"
    case firstQuickCapturePresentation = "FirstQuickCapturePresentation"
}

enum PerformanceOutcome: String, Sendable {
    case success
    case failure
    case cancelled
}

struct PerformanceIntervalToken: Hashable, Sendable {
    fileprivate let id: UUID
}

@MainActor
protocol PerformanceSignposting: AnyObject {
    @discardableResult
    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken?
    func end(_ token: PerformanceIntervalToken?, outcome: PerformanceOutcome)
}

@MainActor
final class AppPerformanceSignposter: PerformanceSignposting {
    static let shared = AppPerformanceSignposter()

    private struct ActiveInterval {
        let operation: PerformanceOperation
        let state: OSSignpostIntervalState
    }

    private let lifecycleSignposter = OSSignposter(
        subsystem: "com.fantomsuj.NotionPiP",
        category: "performance.lifecycle"
    )
    private let presentationSignposter = OSSignposter(
        subsystem: "com.fantomsuj.NotionPiP",
        category: "performance.presentation"
    )
    private var begunOperations: Set<PerformanceOperation> = []
    private var activeIntervals: [PerformanceIntervalToken: ActiveInterval] = [:]

    @discardableResult
    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken? {
        guard begunOperations.insert(operation).inserted else { return nil }

        let state: OSSignpostIntervalState
        switch operation {
        case .coldLaunchToStatusItem:
            state = lifecycleSignposter.beginInterval("ColdLaunchToStatusItem")
        case .firstPiPPresentation:
            state = presentationSignposter.beginInterval("FirstPiPPresentation")
        case .firstQuickCapturePresentation:
            state = presentationSignposter.beginInterval("FirstQuickCapturePresentation")
        }

        let token = PerformanceIntervalToken(id: UUID())
        activeIntervals[token] = ActiveInterval(operation: operation, state: state)
        return token
    }

    func end(_ token: PerformanceIntervalToken?, outcome: PerformanceOutcome) {
        guard let token, let interval = activeIntervals.removeValue(forKey: token) else {
            return
        }

        switch interval.operation {
        case .coldLaunchToStatusItem:
            lifecycleSignposter.endInterval(
                "ColdLaunchToStatusItem",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .firstPiPPresentation:
            presentationSignposter.endInterval(
                "FirstPiPPresentation",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .firstQuickCapturePresentation:
            presentationSignposter.endInterval(
                "FirstQuickCapturePresentation",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        }
    }
}
