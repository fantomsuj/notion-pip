import AppKit
import Combine
import Foundation
import WebKit
import XCTest
@testable import NotionPiP

final class NotionBrowserHandoffRouteTests: XCTestCase {
    func testRecognizesOnlyExactTrustedNotionLoginRoutes() throws {
        for rawURL in [
            "https://app.notion.com/login",
            "https://www.notion.com/login?from=redirect",
            "https://notion.com/login/mail",
            "https://www.notion.so/login?from=redirect",
            "https://notion.so/login/mail",
        ] {
            XCTAssertTrue(
                NotionBrowserHandoffRoute.isLoginURL(
                    try XCTUnwrap(URL(string: rawURL))
                )
            )
        }

        for rawURL in [
            "http://app.notion.com/login",
            "https://app.notion.com.evil.example/login",
            "https://notion.com.evil.example/login",
            "https://www.notion.com.evil.example/login",
            "https://user@app.notion.com/login",
            "https://app.notion.com/logins",
            "https://app.notion.com/workspace",
        ] {
            XCTAssertFalse(
                NotionBrowserHandoffRoute.isLoginURL(
                    try XCTUnwrap(URL(string: rawURL))
                )
            )
        }
    }

    func testParsesCurrentAndLegacyCallbacksOnlyForTrustedNotionAuthorities() throws {
        for rawURL in [
            "notion://app.notion.com/desktopwithbrowserlogincallback?code=one-time",
            "notion://www.notion.com/browser-session-handoff-to-desktop/callback?code=current-code",
            "notion://notion.com/desktopwithbrowserlogincallback?code=current-host",
            "notion://www.notion.so/browser-session-handoff-to-desktop/callback?code=new-code",
            "notion://notion.so/desktopwithbrowserlogincallback?code=legacy-host",
        ] {
            XCTAssertNotNil(
                NotionBrowserHandoffRoute.code(
                    from: try XCTUnwrap(URL(string: rawURL))
                )
            )
        }
    }

    func testRejectsMalformedCallbackAndUnexpectedData() throws {
        for rawURL in [
            "notion-pip://app.notion.com/desktopwithbrowserlogincallback?code=value",
            "notion://app.notion.com/other?code=value",
            "notion://user@app.notion.com/desktopwithbrowserlogincallback?code=value",
            "notion://app.notion.com:443/desktopwithbrowserlogincallback?code=value",
            "notion://app.notion.com/desktopwithbrowserlogincallback",
            "notion://app.notion.com/desktopwithbrowserlogincallback?code=",
            "notion://app.notion.com/desktopwithbrowserlogincallback?code=one&code=two",
            "notion://app.notion.com/desktopwithbrowserlogincallback?code=value&next=https://evil.example",
            "notion://app.notion.com/desktopwithbrowserlogincallback?code=value#fragment",
            "notion://desktop/desktopwithbrowserlogincallback?code=value",
            "notion://notion.com.evil.example/desktopwithbrowserlogincallback?code=value",
            "notion://notion.so.evil.example/desktopwithbrowserlogincallback?code=value",
            "notion:///desktopwithbrowserlogincallback?code=value",
        ] {
            XCTAssertNil(
                NotionBrowserHandoffRoute.code(
                    from: try XCTUnwrap(URL(string: rawURL))
                ),
                rawURL
            )
        }
    }

    func testHandoffStartURLIsTheObservedNotionDesktopRoute() {
        XCTAssertEqual(
            NotionBrowserHandoffRoute.startURL.absoluteString,
            "https://app.notion.com/desktopwithbrowserlogin"
        )
        XCTAssertEqual(NotionBrowserHandoffRoute.callbackScheme, "notion")
    }
}

@MainActor
final class NotionBrowserLoginSessionTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testLoginRouteShowsNativeBrowserActionPresentation() throws {
        let session = NotionWebSession(loadRequest: { _, _ in })
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))

        session.browserLoginRouteDidChange(
            to: try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        )

        XCTAssertEqual(session.browserLoginState, .loginRequired)
        XCTAssertEqual(
            NotionBrowserLoginPresentation(state: session.browserLoginState),
            NotionBrowserLoginPresentation(
                state: .loginRequired
            )
        )
        XCTAssertEqual(
            NotionBrowserLoginPresentation(state: session.browserLoginState)?.actionTitle,
            "Continue in Browser"
        )
    }

    func testBrowserCallbackRedeemsInExistingWebViewAndRestoresOriginalPage() async throws {
        var loadedRequests: [URLRequest] = []
        var factoryInput: (URL, String, NSWindow)?
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redeemedCodes: [String] = []
        var redemptionCompletion: (@MainActor (Result<Bool, Error>) -> Void)?
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { url, scheme, anchor, completion in
                factoryInput = (url, scheme, anchor)
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            browserHandoffRedeemer: { _, code, completion in
                redeemedCodes.append(code)
                redemptionCompletion = completion
                return AnyCancellable {}
            },
            loadRequest: { _, request in loadedRequests.append(request) }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)
        session.browserLoginRouteDidChange(
            to: loginURL
        )

        session.continueLoginInBrowser()

        XCTAssertEqual(factoryInput?.0, NotionBrowserHandoffRoute.startURL)
        XCTAssertEqual(factoryInput?.1, "notion")
        XCTAssertTrue(factoryInput?.2 === anchor)
        XCTAssertEqual(fakeAuthenticationSession.startCount, 1)
        XCTAssertEqual(session.browserLoginState, .openingBrowser)

        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://app.notion.com/desktopwithbrowserlogincallback?code=single-use"
                    )
                )
            )
        )
        await Task.yield()

        XCTAssertEqual(redeemedCodes, ["single-use"])
        XCTAssertEqual(session.browserLoginState, .redeeming)

        redemptionCompletion?(.success(true))

        XCTAssertEqual(loadedRequests.map(\.url), [page.canonicalURL, page.canonicalURL])
        XCTAssertTrue(session.webView === webView)
        XCTAssertEqual(session.activePage, page)
        XCTAssertEqual(session.browserLoginState, .redeeming)

        session.finishBrowserLoginRestorationIfNeeded(at: page.canonicalURL)

        XCTAssertEqual(session.browserLoginState, .idle)
    }

    func testCancelledBrowserSessionReturnsToLoginRequiredWithoutRedeeming() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redeemCount = 0
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            browserHandoffRedeemer: { _, _, _ in
                redeemCount += 1
                return AnyCancellable {}
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.browserLoginRouteDidChange(
            to: loginURL
        )
        session.continueLoginInBrowser()

        authenticationCompletion?(.cancelled)
        await Task.yield()

        XCTAssertEqual(session.browserLoginState, .loginRequired)
        XCTAssertEqual(redeemCount, 0)
    }

    func testAuthenticationSessionStartFailureIsRetryable() throws {
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        fakeAuthenticationSession.startResult = false
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, _ in
                fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            loadRequest: { _, _ in }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.browserLoginRouteDidChange(to: loginURL)

        session.continueLoginInBrowser()

        XCTAssertEqual(fakeAuthenticationSession.startCount, 1)
        guard case .failed = session.browserLoginState else {
            return XCTFail("Expected start failure to remain retryable")
        }
    }

    func testSwitchingPagesCancelsAndIgnoresStaleBrowserCallback() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redeemCount = 0
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            browserHandoffRedeemer: { _, _, _ in
                redeemCount += 1
                return AnyCancellable {}
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.browserLoginRouteDidChange(
            to: loginURL
        )
        session.continueLoginInBrowser()

        session.activate(page: try makePage(id: secondPageID, title: "Notes"))
        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://desktop/desktopwithbrowserlogincallback?code=stale"
                    )
                )
            )
        )
        await Task.yield()

        XCTAssertEqual(fakeAuthenticationSession.cancelCount, 1)
        XCTAssertEqual(redeemCount, 0)
        XCTAssertEqual(session.browserLoginState, .idle)
        XCTAssertEqual(session.activePage?.pageID, secondPageID)
    }

    func testMalformedCallbackFailsClosedAndLeavesWebLoginAvailable() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redeemCount = 0
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            browserHandoffRedeemer: { _, _, _ in
                redeemCount += 1
                return AnyCancellable {}
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        session.browserLoginRouteDidChange(
            to: loginURL
        )
        session.continueLoginInBrowser()

        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://desktop/desktopwithbrowserlogincallback?code=one&next=https://evil.example"
                    )
                )
            )
        )
        await Task.yield()

        guard case .failed = session.browserLoginState else {
            return XCTFail("Expected an invalid callback to fail closed")
        }
        XCTAssertEqual(redeemCount, 0)
        XCTAssertTrue(session.webView === webView)
    }

    func testLeavingLoginRouteCancelsOpeningAttemptAndClearsBanner() throws {
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, _ in
                fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            loadRequest: { _, _ in }
        )
        session.activate(page: page)
        session.browserLoginRouteDidChange(to: loginURL)
        session.continueLoginInBrowser()

        session.browserLoginRouteDidChange(to: page.canonicalURL)

        XCTAssertEqual(fakeAuthenticationSession.cancelCount, 1)
        XCTAssertEqual(session.browserLoginState, .idle)
    }

    func testCallbackDoesNotRedeemAfterCurrentDocumentLeavesLogin() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var currentURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        var redeemCount = 0
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in currentURL },
            browserHandoffRedeemer: { _, _, _ in
                redeemCount += 1
                return AnyCancellable {}
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: page)
        session.browserLoginRouteDidChange(to: currentURL)
        session.continueLoginInBrowser()
        currentURL = page.canonicalURL

        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://app.notion.com/desktopwithbrowserlogincallback?code=stale-origin"
                    )
                )
            )
        )
        await Task.yield()

        XCTAssertEqual(redeemCount, 0)
        guard case .failed = session.browserLoginState else {
            return XCTFail("Expected changed WebKit origin to fail closed")
        }
    }

    func testDuplicateAuthenticationCompletionRedeemsOnlyOnce() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redeemCount = 0
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            browserHandoffRedeemer: { _, _, _ in
                redeemCount += 1
                return AnyCancellable {}
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.browserLoginRouteDidChange(to: loginURL)
        session.continueLoginInBrowser()
        let callback = try XCTUnwrap(
            URL(
                string: "notion://app.notion.com/desktopwithbrowserlogincallback?code=single"
            )
        )

        authenticationCompletion?(.callback(callback))
        await Task.yield()
        authenticationCompletion?(.callback(callback))
        await Task.yield()

        XCTAssertEqual(redeemCount, 1)
        XCTAssertEqual(session.browserLoginState, .redeeming)
    }

    func testLeavingLoginRouteCancelsDispatchedRedemption() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var currentURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        var redemptionCancelCount = 0
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in currentURL },
            browserHandoffRedeemer: { _, _, _ in
                AnyCancellable { redemptionCancelCount += 1 }
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: page)
        session.browserLoginRouteDidChange(to: currentURL)
        session.continueLoginInBrowser()
        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://app.notion.com/desktopwithbrowserlogincallback?code=dispatched"
                    )
                )
            )
        )
        await Task.yield()
        currentURL = page.canonicalURL

        session.browserLoginRouteDidChange(to: currentURL)

        XCTAssertEqual(redemptionCancelCount, 1)
        XCTAssertEqual(session.browserLoginState, .idle)
    }

    func testRestorationTimeoutOffersWorkingSavedPageReload() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redemptionCompletion: (@MainActor (Result<Bool, Error>) -> Void)?
        var timeoutAction: (@MainActor () -> Void)?
        var loadedRequests: [URLRequest] = []
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        var currentURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in currentURL },
            browserHandoffRedeemer: { _, _, completion in
                redemptionCompletion = completion
                return AnyCancellable {}
            },
            scheduleBrowserLoginTimeout: { interval, action in
                XCTAssertEqual(interval, 15)
                timeoutAction = action
                return AnyCancellable {}
            },
            loadRequest: { _, request in loadedRequests.append(request) }
        )
        session.activate(page: page)
        session.browserLoginRouteDidChange(to: currentURL)
        session.continueLoginInBrowser()
        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://app.notion.com/desktopwithbrowserlogincallback?code=accepted"
                    )
                )
            )
        )
        await Task.yield()
        redemptionCompletion?(.success(true))
        currentURL = page.canonicalURL

        timeoutAction?()

        guard case .restorationFailed = session.browserLoginState else {
            return XCTFail("Expected restoration timeout to offer a saved-page reload")
        }
        XCTAssertEqual(
            NotionBrowserLoginPresentation(state: session.browserLoginState)?.actionTitle,
            "Reload Saved Page"
        )

        session.performBrowserLoginAction()

        XCTAssertEqual(loadedRequests.map(\.url), [
            page.canonicalURL,
            page.canonicalURL,
            page.canonicalURL,
        ])
        XCTAssertEqual(session.browserLoginState, .idle)
    }

    func testLoginFinishAfterReportedRedemptionFailsInsteadOfStayingBusy() async throws {
        var authenticationCompletion:
            (@Sendable (NotionBrowserAuthenticationResult) -> Void)?
        var redemptionCompletion: (@MainActor (Result<Bool, Error>) -> Void)?
        let fakeAuthenticationSession = FakeBrowserAuthenticationSession()
        let anchor = NSWindow()
        let loginURL = try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        let session = NotionWebSession(
            browserAuthenticationSessionFactory: { _, _, _, completion in
                authenticationCompletion = completion
                return fakeAuthenticationSession
            },
            browserLoginPresentationAnchor: { _ in anchor },
            browserLoginCurrentURL: { _ in loginURL },
            browserHandoffRedeemer: { _, _, completion in
                redemptionCompletion = completion
                return AnyCancellable {}
            },
            loadRequest: { _, _ in }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.browserLoginRouteDidChange(to: loginURL)
        session.continueLoginInBrowser()
        authenticationCompletion?(
            .callback(
                try XCTUnwrap(
                    URL(
                        string: "notion://app.notion.com/desktopwithbrowserlogincallback?code=rejected"
                    )
                )
            )
        )
        await Task.yield()
        redemptionCompletion?(.success(true))

        session.finishBrowserLoginRestorationIfNeeded(at: loginURL)

        guard case .failed = session.browserLoginState else {
            return XCTFail("Expected a login redirect to leave a retryable failure")
        }
    }

    func testPageNavigationCompletionExcludesLoginDocument() throws {
        let session = NotionWebSession(loadRequest: { _, _ in })
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)

        XCTAssertFalse(
            session.finishedNavigationMatchesLoadedPage(
                at: try XCTUnwrap(URL(string: "https://app.notion.com/login"))
            )
        )
        XCTAssertTrue(session.finishedNavigationMatchesLoadedPage(at: page.canonicalURL))
    }

    func testRedemptionUsesSameOriginJSONRequestAndRequiresSuccessfulUser() async throws {
        let webView = WKWebView()
        webView.loadHTMLString(
            """
            <!doctype html>
            <script>
              window.__pageFetchCount = 0;
              window.fetch = async () => {
                window.__pageFetchCount += 1;
                throw new Error('page-world fetch must not observe handoff');
              };
              window.__handoffReady = true;
            </script>
            """,
            baseURL: try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        )
        for _ in 0..<100 {
            if try await webView.evaluateJavaScript("window.__handoffReady === true") as? Bool
                == true
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await webView.callAsyncJavaScript(
            """
            globalThis.__handoffRequest = null;
            globalThis.fetch = async (path, options) => {
              globalThis.__handoffRequest = { path, options };
              return {
                ok: true,
                json: async () => ({
                  type: 'success',
                  data: { success: true, userId: 'user-id' },
                }),
              };
            };
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        )

        var redemptionCancellable: AnyCancellable?
        let result = await withCheckedContinuation { continuation in
            redemptionCancellable = NotionBrowserHandoffRedemption.redeem(
                in: webView,
                code: "single-use-code"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        guard case .success(true) = result else {
            return XCTFail("Expected the mocked Notion redemption to succeed")
        }
        let requestValue = try await webView.callAsyncJavaScript(
            "return globalThis.__handoffRequest;",
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        )
        let request = try XCTUnwrap(requestValue as? [String: Any])
        let options = try XCTUnwrap(request["options"] as? [String: Any])
        let body = try XCTUnwrap(options["body"] as? String)
        let decodedBody = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(body.utf8))
                as? [String: String]
        )

        XCTAssertEqual(request["path"] as? String, "/api/v3/loginWithDesktopBrowserToken")
        XCTAssertEqual(options["method"] as? String, "POST")
        XCTAssertEqual(options["credentials"] as? String, "include")
        XCTAssertEqual(decodedBody["code"], "single-use-code")
        XCTAssertEqual(decodedBody["loginRouteOrigin"], "login")
        let pageFetchCount = try await webView.evaluateJavaScript(
            "window.__pageFetchCount"
        ) as? Int
        XCTAssertEqual(pageFetchCount, 0)
        withExtendedLifetime(redemptionCancellable) {}
    }

    func testRedemptionScriptRefusesNonLoginDocumentBeforeUsingFetch() async throws {
        let webView = WKWebView()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        webView.loadHTMLString(
            """
            <!doctype html>
            <script>
              window.__handoffReady = true;
            </script>
            """,
            baseURL: page.canonicalURL
        )
        for _ in 0..<100 {
            if try await webView.evaluateJavaScript("window.__handoffReady === true") as? Bool
                == true
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await webView.callAsyncJavaScript(
            """
            globalThis.__fetchCount = 0;
            globalThis.fetch = async () => {
              globalThis.__fetchCount += 1;
              throw new Error('fetch must not run');
            };
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        )

        var redemptionCancellable: AnyCancellable?
        let result = await withCheckedContinuation { continuation in
            redemptionCancellable = NotionBrowserHandoffRedemption.redeem(
                in: webView,
                code: "must-not-be-redeemed"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        guard case .success(false) = result else {
            return XCTFail("Expected a non-login document to fail before fetch")
        }
        let fetchCount = try await webView.callAsyncJavaScript(
            "return globalThis.__fetchCount;",
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        ) as? Int
        XCTAssertEqual(fetchCount, 0)
        withExtendedLifetime(redemptionCancellable) {}
    }

    func testCancellingRedemptionAbortsIsolatedWorldFetch() async throws {
        let webView = WKWebView()
        webView.loadHTMLString(
            "<!doctype html><script>window.__handoffReady = true;</script>",
            baseURL: try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        )
        for _ in 0..<100 {
            if try await webView.evaluateJavaScript("window.__handoffReady === true") as? Bool
                == true
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await webView.callAsyncJavaScript(
            """
            globalThis.__fetchStarted = false;
            globalThis.__abortObserved = false;
            globalThis.fetch = async (path, options) => {
              globalThis.__fetchStarted = true;
              return await new Promise((resolve, reject) => {
                options.signal.addEventListener('abort', () => {
                  globalThis.__abortObserved = true;
                  reject(new DOMException('Aborted', 'AbortError'));
                }, { once: true });
              });
            };
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        )
        var completionCalled = false
        let redemptionCancellable = NotionBrowserHandoffRedemption.redeem(
            in: webView,
            code: "cancelled-code"
        ) { _ in
            completionCalled = true
        }
        for _ in 0..<100 {
            let started = try await webView.callAsyncJavaScript(
                "return globalThis.__fetchStarted === true;",
                arguments: [:],
                in: nil,
                contentWorld: NotionBrowserHandoffRedemption.contentWorld
            ) as? Bool
            if started == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        redemptionCancellable.cancel()

        var abortObserved = false
        for _ in 0..<100 {
            abortObserved = try await webView.callAsyncJavaScript(
                "return globalThis.__abortObserved === true;",
                arguments: [:],
                in: nil,
                contentWorld: NotionBrowserHandoffRedemption.contentWorld
            ) as? Bool == true
            if abortObserved { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(abortObserved)
        XCTAssertFalse(completionCalled)
    }

    func testImmediateCancellationPreventsFetchBeforeControllerRegistration() async throws {
        let webView = WKWebView()
        webView.loadHTMLString(
            "<!doctype html><script>window.__handoffReady = true;</script>",
            baseURL: try XCTUnwrap(URL(string: "https://app.notion.com/login"))
        )
        for _ in 0..<100 {
            if try await webView.evaluateJavaScript("window.__handoffReady === true") as? Bool
                == true
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await webView.callAsyncJavaScript(
            """
            globalThis.__fetchCount = 0;
            globalThis.fetch = async () => {
              globalThis.__fetchCount += 1;
              return {
                ok: true,
                json: async () => ({ success: true, userId: 'unexpected' }),
              };
            };
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        )
        var completionCalled = false
        let redemptionCancellable = NotionBrowserHandoffRedemption.redeem(
            in: webView,
            code: "cancel-before-start"
        ) { _ in
            completionCalled = true
        }

        redemptionCancellable.cancel()
        try await Task.sleep(for: .milliseconds(100))

        let fetchCount = try await webView.callAsyncJavaScript(
            "return globalThis.__fetchCount;",
            arguments: [:],
            in: nil,
            contentWorld: NotionBrowserHandoffRedemption.contentWorld
        ) as? Int
        XCTAssertEqual(fetchCount, 0)
        XCTAssertFalse(completionCalled)
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }

}

@MainActor
private final class FakeBrowserAuthenticationSession:
    NotionBrowserAuthenticationSession
{
    var startResult = true
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func start() -> Bool {
        startCount += 1
        return startResult
    }

    func cancel() {
        cancelCount += 1
    }
}
