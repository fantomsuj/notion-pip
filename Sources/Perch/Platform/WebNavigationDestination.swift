import Foundation

enum WebNavigationDestination: Equatable, Sendable {
    case trustedNotion
    case externalWeb
    case unsupported

    static func classify(_ url: URL?) -> WebNavigationDestination {
        guard let url,
              url.baseURL == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedUser == nil,
              components.percentEncodedPassword == nil,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return .unsupported
        }

        let trustedHosts = [
            "app.notion.com",
            "identity.notion.com",
            "notion.com",
            "www.notion.com",
            "notion.so",
            "www.notion.so",
        ]
        if scheme == "https", trustedHosts.contains(host) {
            return .trustedNotion
        }
        return .externalWeb
    }
}
