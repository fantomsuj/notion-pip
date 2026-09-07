import Foundation

enum FlipDestination: Sendable {
    /// The Notion home the occupying face loads. Page pinning is out of scope
    /// for the first prototype; the live editor is still Notion's website.
    static let notionHome: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.notion.so"
        guard let url = components.url else {
            preconditionFailure("Notion home URL is a compile-time invariant")
        }
        return url
    }()
}

enum FlipNavigationPolicy: Sendable {
    static func allows(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https", "about", "notion":
            true
        default:
            false
        }
    }
}
