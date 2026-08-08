import AppKit
import AuthenticationServices
import Combine
import Foundation
import WebKit

enum NotionBrowserLoginState: Equatable {
    case idle
    case loginRequired
    case openingBrowser
    case redeeming
    case failed(String)
    case restorationFailed(String)
}

struct NotionBrowserLoginPresentation: Equatable {
    let message: String
    let actionTitle: String
    let actionIsEnabled: Bool
    let showsProgress: Bool

    init?(state: NotionBrowserLoginState) {
        switch state {
        case .idle:
            return nil
        case .loginRequired:
            message = "Continue sign-in in your browser."
            actionTitle = "Continue in Browser"
            actionIsEnabled = true
            showsProgress = false
        case .openingBrowser:
            message = "Finish signing in in your browser."
            actionTitle = "Continue in Browser"
            actionIsEnabled = false
            showsProgress = true
        case .redeeming:
            message = "Finishing sign-in…"
            actionTitle = "Continue in Browser"
            actionIsEnabled = false
            showsProgress = true
        case let .failed(message):
            self.message = message
            actionTitle = "Try Browser Again"
            actionIsEnabled = true
            showsProgress = false
        case let .restorationFailed(message):
            self.message = message
            actionTitle = "Reload Saved Page"
            actionIsEnabled = true
            showsProgress = false
        }
    }
}

enum NotionBrowserHandoffRoute {
    // Notion's desktop handoff is undocumented. Keep every observed route constant here so
    // a server-side change fails closed without broadening the normal WebKit trust policy.
    static let startURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "app.notion.com"
        components.path = "/desktopwithbrowserlogin"
        guard let url = components.url else {
            preconditionFailure("The fixed Notion browser handoff URL must be valid")
        }
        return url
    }()
    static let callbackScheme = "notion"

    private static let loginPaths: Set<String> = [
        "/login",
        "/login/ai",
        "/login/calendar",
        "/login/mail",
    ]
    private static let callbackPaths: Set<String> = [
        "/desktopwithbrowserlogincallback",
        "/browser-session-handoff-to-desktop/callback",
    ]
    private static let trustedLoginHosts: Set<String> = [
        "app.notion.com",
        "notion.so",
        "www.notion.so",
    ]
    // The desktop router currently ignores the authority. Notion PiP accepts only
    // Notion-owned authorities to prevent account-swapping callbacks from other origins.
    private static let trustedCallbackHosts = trustedLoginHosts
    private static let maximumCodeLength = 4_096

    static func isLoginURL(_ url: URL?) -> Bool {
        guard let url,
              url.baseURL == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.percentEncodedUser == nil,
              components.percentEncodedPassword == nil,
              components.port == nil,
              let host = components.host?.lowercased(),
              trustedLoginHosts.contains(host)
        else {
            return false
        }

        return loginPaths.contains(components.path)
    }

    static func code(from callbackURL: URL) -> String? {
        guard callbackURL.absoluteString.utf8.count <= maximumCodeLength + 512,
              callbackURL.baseURL == nil,
              let components = URLComponents(
                url: callbackURL,
                resolvingAgainstBaseURL: false
              ),
              components.scheme?.lowercased() == callbackScheme,
              components.percentEncodedUser == nil,
              components.percentEncodedPassword == nil,
              components.port == nil,
              components.fragment == nil,
              let host = components.host?.lowercased(),
              trustedCallbackHosts.contains(host),
              callbackPaths.contains(components.path),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "code",
              let code = queryItems[0].value,
              !code.isEmpty,
              code.utf8.count <= maximumCodeLength
        else {
            return nil
        }
        return code
    }
}

enum NotionBrowserAuthenticationResult: Sendable {
    case callback(URL)
    case cancelled
    case failed
}

@MainActor
protocol NotionBrowserAuthenticationSession: AnyObject {
    func start() -> Bool
    func cancel()
}

typealias NotionBrowserAuthenticationSessionFactory = @MainActor (
    URL,
    String,
    NSWindow,
    @escaping @Sendable (NotionBrowserAuthenticationResult) -> Void
) -> any NotionBrowserAuthenticationSession

@MainActor
final class SystemNotionBrowserAuthenticationSession: NSObject,
    NotionBrowserAuthenticationSession,
    ASWebAuthenticationPresentationContextProviding
{
    private let anchor: NSWindow
    private var authenticationSession: ASWebAuthenticationSession?

    init(
        url: URL,
        callbackScheme: String,
        anchor: NSWindow,
        completion: @escaping @Sendable (NotionBrowserAuthenticationResult) -> Void
    ) {
        self.anchor = anchor
        super.init()
        let authenticationSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            if let callbackURL {
                completion(.callback(callbackURL))
            } else if let error = error as? ASWebAuthenticationSessionError,
                      error.code == .canceledLogin
            {
                completion(.cancelled)
            } else {
                completion(.failed)
            }
        }
        authenticationSession.presentationContextProvider = self
        authenticationSession.prefersEphemeralWebBrowserSession = false
        self.authenticationSession = authenticationSession
    }

    func start() -> Bool {
        authenticationSession?.start() == true
    }

    func cancel() {
        authenticationSession?.cancel()
    }

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        anchor
    }
}

typealias NotionBrowserHandoffRedeemer = @MainActor (
    WKWebView,
    String,
    @escaping @MainActor (Result<Bool, Error>) -> Void
) -> AnyCancellable

enum NotionBrowserHandoffRedemption {
    @MainActor
    static let contentWorld = WKContentWorld.world(
        name: "com.fantomsuj.NotionPiP.browser-handoff"
    )

    @MainActor
    static func redeem(
        in webView: WKWebView,
        code: String,
        completion: @escaping @MainActor (Result<Bool, Error>) -> Void
    ) -> AnyCancellable {
        // Run the desktop token exchange in the committed login document so response
        // cookies stay in this WKWebView's persistent website data store. The code is an
        // argument to WebKit, never interpolated into source or copied into native cookies.
        let attemptID = UUID().uuidString
        let script = """
            const allowedHosts = new Set([
              'app.notion.com',
              'notion.so',
              'www.notion.so',
            ]);
            const allowedPaths = new Set([
              '/login',
              '/login/ai',
              '/login/calendar',
              '/login/mail',
            ]);
            if (location.protocol !== 'https:' ||
                !allowedHosts.has(location.hostname.toLowerCase()) ||
                !allowedPaths.has(location.pathname)) {
              return false;
            }

            const cancelledAttempts =
              globalThis.__notionPiPCancelledHandoffAttempts || new Set();
            globalThis.__notionPiPCancelledHandoffAttempts = cancelledAttempts;
            if (cancelledAttempts.delete(attemptID)) return false;

            const controller = new AbortController();
            const controllers = globalThis.__notionPiPHandoffControllers || new Map();
            globalThis.__notionPiPHandoffControllers = controllers;
            controllers.set(attemptID, controller);
            const timeout = setTimeout(() => controller.abort(), 15000);
            try {
              const response = await fetch('/api/v3/loginWithDesktopBrowserToken', {
                method: 'POST',
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  code: code,
                  loginRouteOrigin: 'login',
                }),
                signal: controller.signal,
              });
              if (!response.ok) return false;
              const envelope = await response.json();
              const data = envelope && envelope.type === 'success'
                ? envelope.data
                : envelope;
              return Boolean(data && data.success === true && data.userId);
            } finally {
              clearTimeout(timeout);
              controllers.delete(attemptID);
            }
            """
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return }
            do {
                let value = try await webView.callAsyncJavaScript(
                    script,
                    arguments: [
                        "attemptID": attemptID,
                        "code": code,
                    ],
                    in: nil,
                    contentWorld: contentWorld
                )
                guard !Task.isCancelled else { return }
                completion(.success(value as? Bool == true))
            } catch {
                guard !Task.isCancelled else { return }
                completion(.failure(error))
            }
        }
        return AnyCancellable { [weak webView] in
            task.cancel()
            Task { @MainActor in
                guard let webView else { return }
                _ = try? await webView.callAsyncJavaScript(
                    """
                    const controllers = globalThis.__notionPiPHandoffControllers;
                    const controller = controllers && controllers.get(attemptID);
                    if (!controller) {
                      const cancelledAttempts =
                        globalThis.__notionPiPCancelledHandoffAttempts || new Set();
                      globalThis.__notionPiPCancelledHandoffAttempts = cancelledAttempts;
                      cancelledAttempts.add(attemptID);
                      setTimeout(() => cancelledAttempts.delete(attemptID), 30000);
                      return false;
                    }
                    controller.abort();
                    controllers.delete(attemptID);
                    return true;
                    """,
                    arguments: ["attemptID": attemptID],
                    in: nil,
                    contentWorld: contentWorld
                )
            }
        }
    }
}
