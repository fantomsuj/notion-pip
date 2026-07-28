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
        guard let currentPage = panelCoordinator.currentPage else {
            panelCoordinator.show(page: page)
            return
        }

        if currentPage.canonicalURL == page.canonicalURL {
            panelCoordinator.show(page: page)
        } else {
            panelCoordinator.replace(page: page)
        }
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        panelCoordinator.reloadPinnedPage(page)
    }

    func toggleCurrentPage() -> Bool {
        panelCoordinator.toggleCurrentPage()
    }

    func stashOrRestoreCurrentPage() -> Bool {
        panelCoordinator.stashOrRestoreCurrentPage()
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
