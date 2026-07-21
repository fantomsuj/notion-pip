import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    @Published var pageURLText = ""
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var validationMessage: String?
    @Published private(set) var validationFailed = false

    func validatePageURL() {
        guard let url = URL(string: pageURLText) else {
            showValidationFailure("Enter a complete Notion page URL.")
            return
        }

        do {
            let page = try NotionPageReference(validating: url)
            pendingPage = page
            validationFailed = false
            validationMessage = page.displayTitle.map { "Ready to pin \($0)." } ?? "Ready to pin this page."
        } catch {
            showValidationFailure("Use an HTTPS notion.so page URL with a page ID.")
        }
    }

    private func showValidationFailure(_ message: String) {
        pendingPage = nil
        validationFailed = true
        validationMessage = message
    }
}
