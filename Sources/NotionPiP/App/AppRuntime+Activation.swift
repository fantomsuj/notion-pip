import Foundation

extension AppRuntime {
    @discardableResult
    func applyGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        do {
            try shortcutRegistrar.register(shortcut: shortcut) { [weak self] event in
                self?.handleGlobalShortcut(event)
            }
            publishGlobalShortcut(shortcut)
            shortcutStore.save(shortcut)
            shortcutConfigurationDidChange()
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

    func setHoldToPeekEnabled(_ enabled: Bool) {
        guard enabled != holdToPeekEnabled else { return }
        cancelShortcutHold()
        holdToPeekPreferenceStore.save(enabled)
        publishHoldToPeekEnabled(enabled)
    }

    func recoverShortcuts(trigger: ShortcutRecoveryTrigger) {
        let expectedGeneration = shortcutConfigurationGeneration
        let panelFailure = revalidationFailure(from: shortcutRegistrar)
        guard expectedGeneration == shortcutConfigurationGeneration else { return }

        updateShortcutHealth(
            issue: .globalShortcutUnavailable,
            failure: panelFailure
        )
        if trigger == .lifecycleEvent,
           panelFailure == .transient
        {
            shortcutLifecycleCoordinator?.requestRetry()
        }
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

    private func handleGlobalShortcut(_ event: GlobalShortcutEvent) {
        switch event {
        case .pressed:
            guard holdToPeekEnabled else {
                handleGlobalShortcutTap()
                return
            }
            guard shortcutHoldTask == nil else { return }
            shortcutHoldTriggered = false
            shortcutPeekRestoredPanel = false
            shortcutHoldTask = Task { [weak self, shortcutHoldDuration] in
                do {
                    try await Task.sleep(for: shortcutHoldDuration)
                } catch {
                    return
                }
                guard let self else { return }
                shortcutHoldTriggered = true
                if pinCoordinator.presentationState == .stashed {
                    peekFocusRestorer.beginPeek()
                    shortcutPeekRestoredPanel = pinCoordinator.stashOrRestoreCurrentPage()
                    if !shortcutPeekRestoredPanel {
                        peekFocusRestorer.cancelPeek()
                    }
                }
            }
        case .released:
            guard holdToPeekEnabled else { return }
            guard let holdTask = shortcutHoldTask else { return }
            shortcutHoldTask = nil
            if shortcutHoldTriggered {
                shortcutHoldTriggered = false
                if shortcutPeekRestoredPanel {
                    shortcutPeekRestoredPanel = false
                    _ = pinCoordinator.stashOrRestoreCurrentPage()
                    peekFocusRestorer.finishPeek()
                }
            } else {
                holdTask.cancel()
                handleGlobalShortcutTap()
            }
        }
    }

    private func cancelShortcutHold() {
        shortcutHoldTask?.cancel()
        shortcutHoldTask = nil
        shortcutHoldTriggered = false
        if shortcutPeekRestoredPanel {
            shortcutPeekRestoredPanel = false
            _ = pinCoordinator.stashOrRestoreCurrentPage()
            peekFocusRestorer.finishPeek()
        } else {
            peekFocusRestorer.cancelPeek()
        }
    }

    private func handleGlobalShortcutTap() {
        guard pinCoordinator.performGlobalShortcutAction() else {
            pageURLInputPresenter.presentAndFocus()
            return
        }
    }

    private func showValidationFailure(_ message: String) {
        pageURLInputState.showValidationFailure(message)
    }

    private func shortcutConfigurationDidChange() {
        shortcutConfigurationGeneration &+= 1
        shortcutLifecycleCoordinator?.invalidatePendingRecovery()
    }

    private func revalidationFailure(
        from registrar: any GlobalShortcutRegistering
    ) -> GlobalShortcutRegistrationFailure? {
        do {
            try registrar.revalidate()
            return nil
        } catch let failure as GlobalShortcutRegistrationFailure {
            return failure
        } catch {
            return .transient
        }
    }

    private func updateShortcutHealth(
        issue: ServiceHealthIssue,
        failure: GlobalShortcutRegistrationFailure?
    ) {
        if failure == nil {
            resolveServiceIssue(issue)
        } else {
            reportServiceIssue(issue)
        }
    }
}
