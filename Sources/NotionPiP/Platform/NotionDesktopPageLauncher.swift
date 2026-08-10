import AppKit

@MainActor
final class NotionDesktopPageLauncher {
    private static let newPageURL: URL = {
        guard let url = URL(string: "notion://www.notion.so/new") else {
            preconditionFailure("The static Notion new-page route must be a valid URL")
        }
        return url
    }()

    private let openURL: (URL) -> Bool

    init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    @discardableResult
    func openNewPage() -> Bool {
        openURL(Self.newPageURL)
    }
}
