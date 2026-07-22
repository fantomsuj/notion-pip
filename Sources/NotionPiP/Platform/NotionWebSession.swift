import Combine
import AppKit
import WebKit

typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void

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
    static let newPageURL = URL(string: "https://www.notion.so/new")!

    let webView: WKWebView
    @Published private(set) var state: NotionWebSessionState = .idle
    @Published private(set) var isCreatingNewPage = false
    private(set) var activePage: NotionPageReference?
    var onPageResolved: (@MainActor (NotionPageReference) -> Void)?
    private let openURL: @MainActor (URL) -> Void
    private let loadRequest: NotionWebRequestLoader

    init(
        webView: WKWebView? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        loadRequest: @escaping NotionWebRequestLoader = { webView, request in
            webView.load(request)
        }
    ) {
        self.webView = webView ?? Self.makeWebView()
        self.openURL = openURL
        self.loadRequest = loadRequest
        super.init()
        self.webView.navigationDelegate = self
    }

    func activate(page: NotionPageReference) {
        guard activePage?.pageID != page.pageID else {
            return
        }

        activePage = page
        state = .loading
        loadRequest(webView, URLRequest(url: page.canonicalURL))
    }

    func createNewPage() {
        guard !isCreatingNewPage else {
            return
        }

        isCreatingNewPage = true
        state = .loading
        loadRequest(webView, URLRequest(url: Self.newPageURL))
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
        isCreatingNewPage = false
        guard let url = webView.url,
              let resolvedPage = try? NotionPageReference(validating: url),
              resolvedPage.pageID != activePage?.pageID
        else {
            return
        }

        activePage = resolvedPage
        onPageResolved?(resolvedPage)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isCreatingNewPage = false
        state = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isCreatingNewPage = false
        state = .failed(error.localizedDescription)
    }
}
