import Foundation
import OSLog

enum PerformanceOperation: String, CaseIterable, Sendable {
    case coldLaunchToReady = "ColdLaunchToReady"
    case firstPiPPresentation = "FirstPiPPresentation"
    case notionSessionRestoration = "NotionSessionRestoration"
    case webViewEviction = "WebViewEviction"

    var isFirstOnly: Bool {
        switch self {
        case .coldLaunchToReady, .firstPiPPresentation:
            true
        case .notionSessionRestoration, .webViewEviction:
            false
        }
    }
}

enum PerformanceOutcome: String, Sendable {
    case success
    case failure
    case cancelled
}

struct PerformanceIntervalToken: Hashable, Sendable {
    fileprivate let id: UUID
}

struct PerformanceMetadata: Equatable, Sendable {
    var cacheEntryCount: Int?

    init(cacheEntryCount: Int? = nil) {
        self.cacheEntryCount = cacheEntryCount
    }
}

@MainActor
protocol PerformanceSignposting: AnyObject {
    @discardableResult
    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken?
    func end(
        _ token: PerformanceIntervalToken?,
        outcome: PerformanceOutcome,
        metadata: PerformanceMetadata
    )
}

extension PerformanceSignposting {
    func end(_ token: PerformanceIntervalToken?, outcome: PerformanceOutcome) {
        end(token, outcome: outcome, metadata: PerformanceMetadata())
    }
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
    private let webViewSignposter = OSSignposter(
        subsystem: "com.fantomsuj.NotionPiP",
        category: "performance.webview"
    )
    private var begunOperations: Set<PerformanceOperation> = []
    private var activeIntervals: [PerformanceIntervalToken: ActiveInterval] = [:]

    @discardableResult
    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken? {
        if operation.isFirstOnly {
            guard begunOperations.insert(operation).inserted else { return nil }
        }

        let state: OSSignpostIntervalState
        switch operation {
        case .coldLaunchToReady:
            state = lifecycleSignposter.beginInterval("ColdLaunchToReady")
        case .firstPiPPresentation:
            state = presentationSignposter.beginInterval("FirstPiPPresentation")
        case .notionSessionRestoration:
            state = webViewSignposter.beginInterval("NotionSessionRestoration")
        case .webViewEviction:
            state = webViewSignposter.beginInterval("WebViewEviction")
        }

        let token = PerformanceIntervalToken(id: UUID())
        activeIntervals[token] = ActiveInterval(operation: operation, state: state)
        return token
    }

    func end(
        _ token: PerformanceIntervalToken?,
        outcome: PerformanceOutcome,
        metadata: PerformanceMetadata
    ) {
        guard let token, let interval = activeIntervals.removeValue(forKey: token) else {
            return
        }

        switch interval.operation {
        case .coldLaunchToReady:
            lifecycleSignposter.endInterval(
                "ColdLaunchToReady",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .firstPiPPresentation:
            presentationSignposter.endInterval(
                "FirstPiPPresentation",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .notionSessionRestoration:
            webViewSignposter.endInterval(
                "NotionSessionRestoration",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .webViewEviction:
            webViewSignposter.endInterval(
                "WebViewEviction",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public) cache_entries=\(metadata.cacheEntryCount ?? 0, privacy: .public)"
            )
        }
    }
}
