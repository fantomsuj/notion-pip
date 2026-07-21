import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?

    let pageURLInputState: PageURLInputState

    var pageURLText: String {
        get { pageURLInputState.text }
        set { pageURLInputState.text = newValue }
    }

    var validationMessage: String? {
        pageURLInputState.validationMessage
    }

    var validationFailed: Bool {
        pageURLInputState.validationFailed
    }

    var pageURLFocusRequest: Int {
        pageURLInputState.focusRequest
    }

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "shortcut")
    private let pinCoordinator: PinCoordinator
    private let shortcutRegistrar: any GlobalShortcutRegistering
    private let pageURLInputPresenter: any PageURLInputPresenting
    private var started = false

    init(
        panelCoordinator: any PiPPanelCoordinating = PiPPanelCoordinator(),
        pasteboard: any PasteboardReading = SystemPasteboardReader(),
        shortcutRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        pageURLInputPresenter: (any PageURLInputPresenting)? = nil
    ) {
        let inputState = PageURLInputState()
        let submissionRelay = PageURLInputSubmissionRelay()
        let inputPresenter = pageURLInputPresenter ?? PageURLInputPresenter(
            state: inputState,
            onSubmit: submissionRelay.submit
        )

        pageURLInputState = inputState
        self.pageURLInputPresenter = inputPresenter
        pinCoordinator = PinCoordinator(
            panelCoordinator: panelCoordinator,
            pasteboard: pasteboard,
            requestPageURLFocus: inputPresenter.presentAndFocus
        )
        self.shortcutRegistrar = shortcutRegistrar
        submissionRelay.handler = { [weak self] in
            self?.validatePageURL()
        }
    }

    func start() {
        guard !started else {
            return
        }

        do {
            try shortcutRegistrar.register { [weak self] in
                self?.pinFromClipboard()
            }
            started = true
        } catch {
            logger.error("Global shortcut registration failed")
        }
    }

    func validatePageURL() {
        switch pinCoordinator.pin(urlString: pageURLText) {
        case let .success(page):
            pendingPage = page
            activePage = page
            pageURLInputState.showPinned(page: page)
            pageURLInputPresenter.hide()
        case .failure:
            showValidationFailure("Use an HTTPS notion.so page URL with a page ID.")
        }
    }

    func pin(page: NotionPageReference) {
        pinCoordinator.pin(page: page)
        activePage = pinCoordinator.currentPage
        pendingPage = activePage
    }

    func handleOpenURLs(_ urls: [URL]) {
        pinCoordinator.handleOpenURLs(urls)
        activePage = pinCoordinator.currentPage
        pendingPage = activePage
    }

    private func pinFromClipboard() {
        pinCoordinator.pinFromClipboard()
        activePage = pinCoordinator.currentPage
        pendingPage = activePage
    }

    private func showValidationFailure(_ message: String) {
        pageURLInputState.showValidationFailure(message)
    }
}

@MainActor
private final class PageURLInputSubmissionRelay {
    var handler: () -> Void = {}

    func submit() {
        handler()
    }
}
