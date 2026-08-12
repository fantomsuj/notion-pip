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
    private let reportFailure: @MainActor () -> Void

    init(
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        reportFailure: @escaping @MainActor () -> Void =
            NotionDesktopPageLauncher.showFailureAlert
    ) {
        self.openURL = openURL
        self.reportFailure = reportFailure
    }

    @discardableResult
    func openNewPage() -> Bool {
        guard openURL(Self.newPageURL) else {
            reportFailure()
            return false
        }
        return true
    }

    private static func showFailureAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Notion couldn’t be opened"
        alert.informativeText = "Make sure the Notion app is installed, then try again."
        alert.runModal()
    }
}
