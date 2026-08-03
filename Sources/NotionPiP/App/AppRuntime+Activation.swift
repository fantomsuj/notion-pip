import Foundation

extension AppRuntime {
    @discardableResult
    func applyGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid, shortcut != quickCaptureShortcut else { return false }
        do {
            try shortcutRegistrar.register(shortcut: shortcut) { [weak self] in
                self?.handleGlobalShortcut()
            }
            publishGlobalShortcut(shortcut)
            shortcutStore.save(shortcut)
            resolveServiceIssue(.globalShortcutUnavailable)
            return true
        } catch {
            logger.error("Global shortcut registration failed")
            reportServiceIssue(.globalShortcutUnavailable)
            return false
        }
    }

    func resetGlobalShortcut() {
        _ = applyGlobalShortcut(.default)
    }

    @discardableResult
    func applyQuickCaptureShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid, shortcut != globalShortcut else { return false }
        do {
            try quickCaptureShortcutRegistrar.register(shortcut: shortcut) { [weak self] in
                self?.handleQuickCaptureShortcut()
            }
            quickCaptureShortcut = shortcut
            quickCaptureShortcutStore.save(shortcut)
            return true
        } catch {
            logger.error("Quick Capture shortcut registration failed")
            return false
        }
    }

    func resetQuickCaptureShortcut() { _ = applyQuickCaptureShortcut(.defaultQuickCapture) }

    func setQuickCapturePrefillsClipboard(_ enabled: Bool) {
        trustedCapturePreferenceStore.setPrefillsClipboard(enabled)
        quickCapturePrefillsClipboard = enabled
    }

    func setQuickCaptureInsertsAtNotionCursor(_ enabled: Bool) {
        trustedCapturePreferenceStore.setInsertsAtNotionCursor(enabled)
        quickCaptureInsertsAtNotionCursor = enabled
    }

    func registerQuickCaptureShortcut() { _ = applyQuickCaptureShortcut(quickCaptureShortcut) }

    private func handleQuickCaptureShortcut() {
        let prefill = quickCapturePrefillsClipboard ? pasteboard.readString() : nil
        quickCaptureAction(prefill, quickCaptureInsertsAtNotionCursor)
    }

    func setMenuBarIconVisibility(_ isVisible: Bool) {
        menuBarIconPreferenceStore.save(isVisible)
        publishMenuBarIconVisibility(isVisible)
    }

    func performStatusMenuContextCommand(_ command: StatusMenuContextCommand) {
        switch command {
        case .openSettings:
            settingsWindowPresenter?.show()
        case .stash:
            guard pipPresentationState == .visible else { return }
            _ = pinCoordinator.stashOrRestoreCurrentPage()
        case .show:
            guard pipPresentationState == .stashed else { return }
            _ = pinCoordinator.stashOrRestoreCurrentPage()
        }
    }

    func handleMenuBarActivation() {
        guard pinCoordinator.stashOrRestoreCurrentPage() else {
            settingsWindowPresenter?.show()
            return
        }
    }

    func validatePageURL() {
        switch pinCoordinator.page(from: pageURLText) {
        case let .success(page):
            activate(page: page, source: .typedURL)
            pageURLInputState.showPinned(page: page)
            pageURLInputPresenter.hide()
        case .failure:
            showValidationFailure("Use an HTTPS Notion page URL with a page ID.")
        }
    }

    func pin(page: NotionPageReference) {
        activate(page: page, source: .pagePicker)
    }

    func reloadSavedPin() {
        guard let activePage else { return }
        pinCoordinator.reloadPinnedPage(activePage)
    }

    func activate(page: NotionPageReference, source: PageActivationSource) {
        activate(page: page, source: source, restoration: nil)
    }

    func activate(
        page: NotionPageReference,
        source: PageActivationSource,
        restoration: DurablePageRestoration?
    ) {
        activate(page: page, source: source, persist: true, restoration: restoration)
    }

    func handleOpenURLs(_ urls: [URL]) {
        for (page, source) in pinCoordinator.externalPages(from: urls) {
            activate(page: page, source: .externalRoute(source))
        }
    }

    func registerGlobalShortcut() {
        _ = applyGlobalShortcut(globalShortcut)
    }

    func restorePinnedPage(
        _ page: NotionPageReference,
        restoration: DurablePageRestoration?,
        expectedGeneration: Int
    ) {
        guard expectedGeneration == pageSelectionGeneration, !Task.isCancelled else { return }
        activate(
            page: page,
            source: .restored,
            persist: false,
            restoration: restoration
        )
    }

    private func activate(
        page: NotionPageReference,
        source: PageActivationSource,
        persist: Bool,
        restoration: DurablePageRestoration? = nil
    ) {
        pageSelectionGeneration &+= 1
        if persist {
            restorePinnedPageTask?.cancel()
            restorePinnedPageTask = nil
        }
        pinCoordinator.pin(page: page, restoration: restoration)
        publishActivation(page: page, source: source)

        if persist {
            enqueuePersistence(of: page)
        }
    }

    private func handleGlobalShortcut() {
        guard pinCoordinator.stashOrRestoreCurrentPage() else {
            pageURLInputPresenter.presentAndFocus()
            return
        }
    }

    private func showValidationFailure(_ message: String) {
        pageURLInputState.showValidationFailure(message)
    }
}
