import Combine
import AppKit
import WebKit

@MainActor
protocol NotionPageLoading: AnyObject {
    func activate(page: NotionPageReference)
}

@MainActor
enum NotionWebSessionState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
final class NotionWebSession: NSObject, NotionPageLoading, ObservableObject {
    let webView: WKWebView
    @Published private(set) var state: NotionWebSessionState = .idle
    private(set) var activePage: NotionPageReference?
    private let openURL: @MainActor (URL) -> Void

    init(
        webView: WKWebView? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.webView = webView ?? Self.makeWebView()
        self.openURL = openURL
        super.init()
        self.webView.navigationDelegate = self
    }

    func activate(page: NotionPageReference) {
        guard activePage?.pageID != page.pageID else {
            return
        }

        activePage = page
        state = .loading
        webView.load(URLRequest(url: page.canonicalURL))
    }

    func reload() {
        guard activePage != nil else {
            return
        }

        state = .loading
        webView.reload()
    }

    func openInBrowser() {
        guard let activePage else {
            return
        }

        openURL(activePage.canonicalURL)
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        return WKWebView(frame: .zero, configuration: configuration)
    }
}

extension NotionWebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        state = .loading
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .ready
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        state = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state = .failed(error.localizedDescription)
    }
}
