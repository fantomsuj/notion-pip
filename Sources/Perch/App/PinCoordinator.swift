import Foundation

enum PinInputError: Error, Equatable {
    case invalidURL
    case invalidPage(NotionPageReferenceError)
}

@MainActor
final class PinCoordinator {
    private let panelCoordinator: any PiPPanelCoordinating
    private let pasteboard: any PasteboardReading
    private let requestPageURLFocus: () -> Void

    var currentPage: NotionPageReference? {
        panelCoordinator.currentPage
    }

    var presentationState: PiPPresentationState {
        panelCoordinator.presentationState
    }

    var onExternalPresentationAction: (@MainActor () -> Void)? {
        get { panelCoordinator.onExternalPresentationAction }
        set { panelCoordinator.onExternalPresentationAction = newValue }
    }

    var onPresentationStateChange: (@MainActor () -> Void)? {
        get { panelCoordinator.onPresentationStateChange }
        set { panelCoordinator.onPresentationStateChange = newValue }
    }

    var currentCustomURL: CustomPinnedURL? {
        panelCoordinator.currentCustomURL
    }

    init(
        panelCoordinator: any PiPPanelCoordinating,
        pasteboard: any PasteboardReading,
        requestPageURLFocus: @escaping () -> Void
    ) {
        self.panelCoordinator = panelCoordinator
        self.pasteboard = pasteboard
        self.requestPageURLFocus = requestPageURLFocus
    }

    func pin(page: NotionPageReference) {
        pin(page: page, restoration: nil)
    }

    func pin(
        page: NotionPageReference,
        restoration: DurablePageRestoration?
    ) {
        guard let currentPage = panelCoordinator.currentPage else {
            panelCoordinator.show(page: page, restoration: restoration)
            return
        }

        if currentPage.canonicalURL == page.canonicalURL, currentCustomURL == nil {
            panelCoordinator.show(page: page)
        } else {
            panelCoordinator.replace(page: page, restoration: restoration)
        }
    }

    func pin(customURL: CustomPinnedURL) {
        panelCoordinator.show(customURL: customURL)
    }

    func reloadCustomPinnedURL(_ url: CustomPinnedURL) {
        panelCoordinator.reloadCustomPinnedURL(url)
    }

    func createNewPage() {
        panelCoordinator.createNewPage()
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        panelCoordinator.reloadPinnedPage(page)
    }

    func stashOrRestoreCurrentPage() -> Bool {
        panelCoordinator.stashOrRestoreCurrentPage()
    }

    func showCurrentPage() -> Bool {
        panelCoordinator.showCurrentPage()
    }

    func showCurrentPageFromShortcut(
        measurement: ShortcutPresentationMeasurement
    ) -> Bool {
        panelCoordinator.showCurrentPageFromShortcut(measurement: measurement)
    }

    func stashCurrentPageImmediately() -> Bool {
        panelCoordinator.stashCurrentPageImmediately()
    }

    func performGlobalShortcutAction() -> Bool {
        panelCoordinator.performGlobalShortcutAction()
    }

    func setStashHandleHidden(_ hidden: Bool) {
        panelCoordinator.setStashHandleHidden(hidden)
    }

    func page(from urlString: String) -> Result<NotionPageReference, PinInputError> {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), !trimmedURL.isEmpty else {
            return .failure(.invalidURL)
        }

        do {
            return .success(try NotionPageReference(validating: url))
        } catch let error as NotionPageReferenceError {
            return .failure(.invalidPage(error))
        } catch {
            return .failure(.invalidURL)
        }
    }

    func pageFromClipboard() -> NotionPageReference? {
        guard let clipboardValue = pasteboard.readString(),
              case let .success(page) = page(from: clipboardValue)
        else {
            requestPageURLFocus()
            return nil
        }
        return page
    }

    func externalPages(from urls: [URL]) -> [(NotionPageReference, ExternalURLSource)] {
        urls.compactMap { url in
            guard case let .success(.pin(page, source)) = ExternalURLRoute.parse(url) else {
                return nil
            }
            return (page, source)
        }
    }

}
