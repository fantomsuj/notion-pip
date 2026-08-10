import Foundation

extension AppRuntime {
    @discardableResult
    func applyGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        do {
            try shortcutRegistrar.register(shortcut: shortcut) { [weak self] event in
                self?.handleGlobalShortcut(event)
            }
            cancelShortcutGesture(restashTransientPanel: true)
            publishGlobalShortcut(shortcut)
            shortcutStore.save(shortcut)
            shortcutRegistrationDidChange()
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
        cancelShortcutGesture(restashTransientPanel: true)
        holdToPeekPreferenceStore.save(enabled)
        publishHoldToPeekEnabled(enabled)
    }

    func recoverShortcut(trigger: ShortcutRecoveryTrigger) {
        let expectedGeneration = shortcutRegistrationGeneration
        let panelFailure = revalidationFailure(from: shortcutRegistrar)
        guard expectedGeneration == shortcutRegistrationGeneration else { return }

        updateShortcutHealth(
            issue: .globalShortcutUnavailable,
            failure: panelFailure
        )
        if panelFailure != nil {
            cancelShortcutGesture(restashTransientPanel: true)
        }
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
        cancelShortcutGesture(restashTransientPanel: false)
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
        cancelShortcutGesture(restashTransientPanel: false)
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
        cancelShortcutGesture(restashTransientPanel: false)
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
                handleImmediateShortcutPress()
                return
            }
            handlePeekShortcutPress()
        case .released:
            handleShortcutRelease()
        }
    }

    private func handlePeekShortcutPress() {
        switch shortcutGestureState {
        case let .awaitingSecondPress(generation):
            shortcutGestureTimer?.cancel()
            shortcutGestureTimer = nil
            shortcutGestureState = .persistent(generation: generation)
            peekFocusRestorer.cancelPeek()
            accessibilityAnnouncementPoster.announce("Notion PiP will stay open")
        case .idle:
            switch pinCoordinator.presentationState {
            case .unavailable:
                handleImmediateShortcutPress()
            case .visible:
                beginSuppressingRelease()
                _ = pinCoordinator.stashOrRestoreCurrentPage()
            case .stashed:
                beginTransientPeek()
            }
        case .peeking, .persistent, .suppressingRelease:
            break
        }
    }

    private func beginTransientPeek() {
        shortcutGestureGeneration &+= 1
        let generation = shortcutGestureGeneration
        let measurement = ShortcutPresentationMeasurement(
            signposter: performanceSignposter,
            requestToken: performanceSignposter.begin(.shortcutPressToPresentationRequest),
            usefulContentToken: performanceSignposter.begin(.shortcutPressToUsefulContent)
        )
        peekFocusRestorer.beginPeek()
        guard pinCoordinator.showCurrentPageFromShortcut(measurement: measurement) else {
            peekFocusRestorer.cancelPeek()
            shortcutGestureState = .idle
            return
        }
        shortcutGestureState = .peeking(
            generation: generation,
            deadlineElapsed: false
        )
        shortcutGestureTimer = shortcutGestureScheduler.schedule(
            after: shortcutHoldDuration
        ) { [weak self] in
            self?.shortcutGestureDeadlineReached(generation: generation)
        }
    }

    private func handleShortcutRelease() {
        switch shortcutGestureState {
        case let .peeking(generation, deadlineElapsed):
            if deadlineElapsed {
                finishTransientPeek(generation: generation)
            } else {
                shortcutGestureState = .awaitingSecondPress(generation: generation)
            }
        case .persistent, .suppressingRelease:
            shortcutGestureState = .idle
        case .idle, .awaitingSecondPress:
            break
        }
    }

    private func shortcutGestureDeadlineReached(generation: UInt) {
        switch shortcutGestureState {
        case let .peeking(activeGeneration, _) where activeGeneration == generation:
            shortcutGestureTimer = nil
            shortcutGestureState = .peeking(
                generation: generation,
                deadlineElapsed: true
            )
        case let .awaitingSecondPress(activeGeneration) where activeGeneration == generation:
            shortcutGestureTimer = nil
            finishTransientPeek(generation: generation)
        default:
            break
        }
    }

    private func finishTransientPeek(generation: UInt) {
        guard shortcutGestureState.generation == generation else { return }
        shortcutGestureTimer?.cancel()
        shortcutGestureTimer = nil
        shortcutGestureState = .idle
        if pinCoordinator.presentationState == .visible,
           pinCoordinator.stashCurrentPageImmediately()
        {
            peekFocusRestorer.finishPeek()
        } else {
            peekFocusRestorer.cancelPeek()
        }
    }

    func cancelShortcutGesture(restashTransientPanel: Bool) {
        let wasTransient = shortcutGestureState.isTransient
        shortcutGestureGeneration &+= 1
        shortcutGestureTimer?.cancel()
        shortcutGestureTimer = nil
        shortcutGestureState = .idle
        guard wasTransient else { return }
        guard restashTransientPanel,
              pinCoordinator.presentationState == .visible,
              pinCoordinator.stashCurrentPageImmediately()
        else {
            peekFocusRestorer.cancelPeek()
            return
        }
        peekFocusRestorer.finishPeek()
    }

    private func beginSuppressingRelease() {
        shortcutGestureGeneration &+= 1
        shortcutGestureState = .suppressingRelease(
            generation: shortcutGestureGeneration
        )
    }

    private func handleImmediateShortcutPress() {
        guard shortcutGestureState == .idle else { return }
        beginSuppressingRelease()
        handleGlobalShortcutTap()
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

    private func shortcutRegistrationDidChange() {
        cancelShortcutGesture(restashTransientPanel: true)
        shortcutRegistrationGeneration &+= 1
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

private extension ShortcutPeekGestureState {
    var generation: UInt? {
        switch self {
        case .idle:
            nil
        case let .peeking(generation, _),
             let .awaitingSecondPress(generation),
             let .persistent(generation),
             let .suppressingRelease(generation):
            generation
        }
    }

    var isTransient: Bool {
        switch self {
        case .peeking, .awaitingSecondPress:
            true
        case .idle, .persistent, .suppressingRelease:
            false
        }
    }
}
