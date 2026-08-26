import Foundation

enum NotionWebNavigationActionDecision: Equatable {
    case allow
    case cancel
    case openExternally(URL)
}

enum NotionWebNavigationContext: Equatable {
    case mainFrame
    case subframe
    case newWindow
}

enum NotionWebNewWindowDecision: Equatable {
    case createPopup
    case openExternally(URL)
    case ignore
}

enum NotionWebNavigationFailureDecision: Equatable {
    case cancelled
    case offline
    case failed(String)
}

enum WebBrowsingMode: Equatable, Sendable {
    case notion
    case customPinned
}

struct NotionWebNavigationPolicy {
    func actionDecision(
        for url: URL?,
        context: NotionWebNavigationContext,
        mode: WebBrowsingMode = .notion
    ) -> NotionWebNavigationActionDecision {
        guard context != .newWindow else {
            return .allow
        }

        switch WebNavigationDestination.classify(url) {
        case .trustedNotion:
            return .allow
        case .externalWeb where context == .subframe || mode == .customPinned:
            return .allow
        case .externalWeb:
            guard let url else { return .cancel }
            return .openExternally(url)
        case .unsupported:
            return .cancel
        }
    }

    func newWindowDecision(
        for request: URLRequest,
        mode: WebBrowsingMode = .notion
    ) -> NotionWebNewWindowDecision {
        switch WebNavigationDestination.classify(request.url) {
        case .trustedNotion:
            return .createPopup
        case .externalWeb where mode == .customPinned:
            return .createPopup
        case .externalWeb:
            guard let url = request.url else { return .ignore }
            return .openExternally(url)
        case .unsupported:
            return .ignore
        }
    }

    func failureDecision(
        for error: Error,
        mode: WebBrowsingMode = .notion
    ) -> NotionWebNavigationFailureDecision {
        let error = error as NSError
        let failedMessage = mode == .customPinned
            ? "This page couldn't load."
            : "Notion couldn't load this page."
        guard error.domain == NSURLErrorDomain else {
            return .failed(failedMessage)
        }
        if error.code == NSURLErrorCancelled {
            return .cancelled
        }
        if Self.offlineErrorCodes.contains(error.code) {
            return .offline
        }
        return .failed(failedMessage)
    }

    private static let offlineErrorCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        NSURLErrorDataNotAllowed,
    ]
}
