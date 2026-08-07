import Foundation

enum NotionWebNavigationActionDecision: Equatable {
    case allow
    case cancel
    case openExternally(URL)
}

enum NotionWebNewWindowDecision: Equatable {
    case loadInExistingWebView(URLRequest)
    case openExternally(URL)
    case ignore
}

enum NotionWebNavigationFailureDecision: Equatable {
    case cancelled
    case offline
    case failed(String)
}

struct NotionWebNavigationPolicy {
    func actionDecision(
        for url: URL?,
        targetFrameIsPresent: Bool
    ) -> NotionWebNavigationActionDecision {
        guard targetFrameIsPresent else {
            return .allow
        }

        switch WebNavigationDestination.classify(url) {
        case .trustedNotion:
            return .allow
        case .externalWeb:
            guard let url else { return .cancel }
            return .openExternally(url)
        case .unsupported:
            return .cancel
        }
    }

    func newWindowDecision(for request: URLRequest) -> NotionWebNewWindowDecision {
        switch WebNavigationDestination.classify(request.url) {
        case .trustedNotion:
            return .loadInExistingWebView(request)
        case .externalWeb:
            guard let url = request.url else { return .ignore }
            return .openExternally(url)
        case .unsupported:
            return .ignore
        }
    }

    func failureDecision(for error: Error) -> NotionWebNavigationFailureDecision {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else {
            return .failed("Notion couldn't load this page.")
        }
        if error.code == NSURLErrorCancelled {
            return .cancelled
        }
        if Self.offlineErrorCodes.contains(error.code) {
            return .offline
        }
        return .failed("Notion couldn't load this page.")
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
