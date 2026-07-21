import WebKit

@MainActor
protocol NotionPageLoading: AnyObject {
    func load(page: NotionPageReference)
}

@MainActor
final class NotionWebSession: NotionPageLoading {
    let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

    func load(page: NotionPageReference) {
        webView.load(URLRequest(url: page.canonicalURL))
    }
}
