import AppKit
import WebKit

@MainActor
final class FlipNotionHost: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    init(dataStore: WKWebsiteDataStore = .default()) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, FlipNavigationPolicy.allows(url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
