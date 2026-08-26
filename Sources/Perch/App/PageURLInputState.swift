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

    func showOpened(page: NotionPageReference) {
        showOpened(
            page.displayTitle.map { "Opened \($0) in Perch." }
                ?? "Opened this page in Perch."
        )
    }

    func showOpened(_ message: String) {
        validationFailed = false
        validationMessage = message
    }

    func showValidationFailure(_ message: String) {
        validationFailed = true
        validationMessage = message
    }
}
