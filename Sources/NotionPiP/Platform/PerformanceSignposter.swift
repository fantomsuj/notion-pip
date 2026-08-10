import Foundation
import OSLog

enum PerformanceOperation: String, CaseIterable, Sendable {
    case coldLaunchToReady = "ColdLaunchToReady"
    case firstPiPPresentation = "FirstPiPPresentation"
    case notionSessionRestoration = "NotionSessionRestoration"
    case webViewEviction = "WebViewEviction"
    case webViewConstruction = "WebViewConstruction"
    case navigationRequestToCommit = "NavigationRequestToCommit"
    case commitToUsefulContent = "CommitToUsefulContent"
    case interactionStateRestoreToUsefulContent = "InteractionStateRestoreToUsefulContent"
    case rendererRecoveryToUsefulContent = "RendererRecoveryToUsefulContent"
    case hiddenPanelWarmResume = "HiddenPanelWarmResume"
    case shortcutPressToPresentationRequest = "ShortcutPressToPresentationRequest"
    case shortcutPressToUsefulContent = "ShortcutPressToUsefulContent"
    case peekRestash = "PeekRestash"

    var isFirstOnly: Bool {
        switch self {
        case .coldLaunchToReady, .firstPiPPresentation:
            true
        case .notionSessionRestoration, .webViewEviction,
             .webViewConstruction, .navigationRequestToCommit,
             .commitToUsefulContent, .interactionStateRestoreToUsefulContent,
             .rendererRecoveryToUsefulContent, .hiddenPanelWarmResume,
             .shortcutPressToPresentationRequest, .shortcutPressToUsefulContent,
             .peekRestash:
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
    var webViewRetention: WebViewRetention?

    init(
        cacheEntryCount: Int? = nil,
        webViewRetention: WebViewRetention? = nil
    ) {
        self.cacheEntryCount = cacheEntryCount
        self.webViewRetention = webViewRetention
    }
}

enum WebViewRetention: String, Equatable, Sendable {
    case warm
    case evicted
    case unknown
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

@MainActor
struct ShortcutPresentationMeasurement {
    let signposter: any PerformanceSignposting
    let requestToken: PerformanceIntervalToken?
    let usefulContentToken: PerformanceIntervalToken?
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
        case .webViewConstruction:
            state = webViewSignposter.beginInterval("WebViewConstruction")
        case .navigationRequestToCommit:
            state = webViewSignposter.beginInterval("NavigationRequestToCommit")
        case .commitToUsefulContent:
            state = webViewSignposter.beginInterval("CommitToUsefulContent")
        case .interactionStateRestoreToUsefulContent:
            state = webViewSignposter.beginInterval("InteractionStateRestoreToUsefulContent")
        case .rendererRecoveryToUsefulContent:
            state = webViewSignposter.beginInterval("RendererRecoveryToUsefulContent")
        case .hiddenPanelWarmResume:
            state = webViewSignposter.beginInterval("HiddenPanelWarmResume")
        case .shortcutPressToPresentationRequest:
            state = presentationSignposter.beginInterval("ShortcutPressToPresentationRequest")
        case .shortcutPressToUsefulContent:
            state = presentationSignposter.beginInterval("ShortcutPressToUsefulContent")
        case .peekRestash:
            state = presentationSignposter.beginInterval("PeekRestash")
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
        let retention = metadata.webViewRetention?.rawValue
            ?? WebViewRetention.unknown.rawValue

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
        case .webViewConstruction:
            webViewSignposter.endInterval(
                "WebViewConstruction",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .navigationRequestToCommit:
            webViewSignposter.endInterval(
                "NavigationRequestToCommit",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .commitToUsefulContent:
            webViewSignposter.endInterval(
                "CommitToUsefulContent",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .interactionStateRestoreToUsefulContent:
            webViewSignposter.endInterval(
                "InteractionStateRestoreToUsefulContent",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .rendererRecoveryToUsefulContent:
            webViewSignposter.endInterval(
                "RendererRecoveryToUsefulContent",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .hiddenPanelWarmResume:
            webViewSignposter.endInterval(
                "HiddenPanelWarmResume",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        case .shortcutPressToPresentationRequest:
            presentationSignposter.endInterval(
                "ShortcutPressToPresentationRequest",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public) retention=\(retention, privacy: .public)"
            )
        case .shortcutPressToUsefulContent:
            presentationSignposter.endInterval(
                "ShortcutPressToUsefulContent",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public) retention=\(retention, privacy: .public)"
            )
        case .peekRestash:
            presentationSignposter.endInterval(
                "PeekRestash",
                interval.state,
                "outcome=\(outcome.rawValue, privacy: .public)"
            )
        }
    }
}
