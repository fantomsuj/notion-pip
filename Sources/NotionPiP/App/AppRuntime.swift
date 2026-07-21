import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published var pageURLText = ""
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?
    @Published private(set) var validationMessage: String?
    @Published private(set) var validationFailed = false
    @Published private(set) var pageURLFocusRequest = 0

    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "shortcut")
    private let pinCoordinator: PinCoordinator
    private let shortcutRegistrar: any GlobalShortcutRegistering
    private var started = false

    init(
        panelCoordinator: any PiPPanelCoordinating = PiPPanelCoordinator(),
        pasteboard: any PasteboardReading = SystemPasteboardReader(),
        shortcutRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar()
    ) {
        let focusRelay = PageURLFocusRelay()
        pinCoordinator = PinCoordinator(
            panelCoordinator: panelCoordinator,
            pasteboard: pasteboard,
            requestPageURLFocus: { focusRelay.request() }
        )
        self.shortcutRegistrar = shortcutRegistrar
        focusRelay.handler = { [weak self] in
            self?.requestPageURLFocus()
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
            validationFailed = false
            validationMessage = page.displayTitle.map { "Pinned \($0)." } ?? "Pinned this page."
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

    private func requestPageURLFocus() {
        pageURLFocusRequest += 1
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showValidationFailure(_ message: String) {
        validationFailed = true
        validationMessage = message
    }
}

@MainActor
private final class PageURLFocusRelay {
    var handler: () -> Void = {}

    func request() {
        handler()
    }
}
