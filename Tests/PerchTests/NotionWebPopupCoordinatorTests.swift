import Foundation
import WebKit
import XCTest
@testable import Perch

final class NotionWebPopupCoordinatorTests: XCTestCase {
    @MainActor
    func testPresentUsesSuppliedConfigurationAndPresentsDistinctWebView() {
        let expectedConfiguration = WKWebViewConfiguration()
        let window = PopupWindowSpy()
        var receivedConfiguration: WKWebViewConfiguration?
        let coordinator = NotionWebPopupCoordinator(
            makeWebView: { configuration in
                receivedConfiguration = configuration
                return WKWebView(frame: .zero, configuration: configuration)
            },
            makeWindow: { window }
        )

        let popup = coordinator.present(using: expectedConfiguration)

        XCTAssertTrue(receivedConfiguration === expectedConfiguration)
        XCTAssertTrue(window.presentedWebView === popup)
        XCTAssertTrue(popup.navigationDelegate === coordinator)
        XCTAssertTrue(popup.uiDelegate === coordinator)
    }

    @MainActor
    func testPresentClosesAndDetachesExistingPopup() {
        let firstWindow = PopupWindowSpy()
        let secondWindow = PopupWindowSpy()
        var windows: [PopupWindowSpy] = [firstWindow, secondWindow]
        let coordinator = NotionWebPopupCoordinator(makeWindow: { windows.removeFirst() })
        let firstPopup = coordinator.present(using: WKWebViewConfiguration())

        let secondPopup = coordinator.present(using: WKWebViewConfiguration())

        XCTAssertEqual(firstWindow.closeCallCount, 1)
        XCTAssertNil(firstPopup.navigationDelegate)
        XCTAssertNil(firstPopup.uiDelegate)
        XCTAssertTrue(secondWindow.presentedWebView === secondPopup)
    }

    @MainActor
    func testWindowCloseDetachesPopupDelegatesWithoutClosingWindowAgain() {
        let window = PopupWindowSpy()
        let coordinator = NotionWebPopupCoordinator(makeWindow: { window })
        let popup = coordinator.present(using: WKWebViewConfiguration())

        window.simulateUserClose()

        XCTAssertNil(popup.navigationDelegate)
        XCTAssertNil(popup.uiDelegate)
        XCTAssertEqual(window.closeCallCount, 0)
    }

    @MainActor
    func testWebViewCloseDetachesPopupAndClosesWindow() {
        let window = PopupWindowSpy()
        let coordinator = NotionWebPopupCoordinator(makeWindow: { window })
        let popup = coordinator.present(using: WKWebViewConfiguration())

        coordinator.webViewDidClose(popup)

        XCTAssertNil(popup.navigationDelegate)
        XCTAssertNil(popup.uiDelegate)
        XCTAssertEqual(window.closeCallCount, 1)
    }

    @MainActor
    func testRendererTerminationDetachesPopupAndClosesWindow() {
        let window = PopupWindowSpy()
        let coordinator = NotionWebPopupCoordinator(makeWindow: { window })
        let popup = coordinator.present(using: WKWebViewConfiguration())

        coordinator.webViewWebContentProcessDidTerminate(popup)

        XCTAssertNil(popup.navigationDelegate)
        XCTAssertNil(popup.uiDelegate)
        XCTAssertEqual(window.closeCallCount, 1)
    }

    @MainActor
    func testPopupAllowsWebIdentityProviderAndRejectsUnsupportedScheme() throws {
        let coordinator = NotionWebPopupCoordinator()

        for rawURL in [
            "https://accounts.google.com/signin",
            "https://appleid.apple.com/auth/authorize",
            "https://login.example.com/saml",
        ] {
            XCTAssertEqual(
                coordinator.navigationPolicy(
                    for: try XCTUnwrap(URL(string: rawURL))
                ),
                .allow
            )
        }
        XCTAssertEqual(
            coordinator.navigationPolicy(
                for: try XCTUnwrap(URL(string: "file:///tmp/credentials"))
            ),
            .cancel
        )
        for rawURL in [
            "http://app.notion.com/login",
            "http://login.example.com/saml",
        ] {
            XCTAssertEqual(
                coordinator.navigationPolicy(
                    for: try XCTUnwrap(URL(string: rawURL))
                ),
                .cancel
            )
        }
        XCTAssertEqual(coordinator.navigationPolicy(for: nil), .cancel)
    }

    @MainActor
    func testNestedWindowLoadsTrustedNotionAndOpensExternalOnce() throws {
        var loadedRequests: [URLRequest] = []
        var openedURLs: [URL] = []
        let window = PopupWindowSpy()
        let coordinator = NotionWebPopupCoordinator(
            openURL: { openedURLs.append($0) },
            loadRequest: { _, request in loadedRequests.append(request) },
            makeWindow: { window }
        )
        let popup = coordinator.present(using: WKWebViewConfiguration())
        let trustedRequest = URLRequest(
            url: try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        )
        let externalURL = try XCTUnwrap(URL(string: "https://example.com/help"))

        XCTAssertNil(coordinator.handleNewWindowRequest(trustedRequest, in: popup))
        XCTAssertNil(
            coordinator.handleNewWindowRequest(
                URLRequest(url: externalURL),
                in: popup
            )
        )

        XCTAssertEqual(loadedRequests, [trustedRequest])
        XCTAssertEqual(openedURLs, [externalURL])
    }
}

@MainActor
private final class PopupWindowSpy: NotionWebPopupWindowing {
    var onClose: (@MainActor () -> Void)?
    private(set) weak var presentedWebView: WKWebView?
    private(set) var closeCallCount = 0

    func present(webView: WKWebView) {
        presentedWebView = webView
    }

    func close() {
        closeCallCount += 1
    }

    func simulateUserClose() {
        onClose?()
    }
}
