import Combine

@MainActor
final class PageURLInputState: ObservableObject {
    @Published var text = ""
    @Published private(set) var validationMessage: String?
    @Published private(set) var validationFailed = false
    @Published private(set) var focusRequest = 0

    func requestFocus() {
        focusRequest += 1
    }

    func showPinned(page: NotionPageReference) {
        validationFailed = false
        validationMessage = page.displayTitle.map { "Pinned \($0)." } ?? "Pinned this page."
    }

    func showValidationFailure(_ message: String) {
        validationFailed = true
        validationMessage = message
    }
}
