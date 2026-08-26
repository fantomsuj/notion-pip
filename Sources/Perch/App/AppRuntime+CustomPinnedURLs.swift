import Foundation

extension AppRuntime {
    var isShowingCustomURL: Bool {
        activeCustomURL != nil
    }

    func setCustomPinnedURLsEnabled(_ enabled: Bool) {
        guard enabled != customPinnedURLsEnabled else { return }
        publishCustomPinnedURLsEnabled(enabled)
        persistCustomPinnedURLs()
        if !enabled, activeCustomURL != nil {
            returnToNotionPage()
        }
    }

    @discardableResult
    func addCustomPinnedURL() -> Bool {
        let raw = customPinnedURLInputState.text
        if case let .success(page) = pinCoordinator.page(from: raw) {
            activate(page: page, source: .typedURL)
            customPinnedURLInputState.showOpened(page: page)
            customPinnedURLInputState.text = ""
            return true
        }

        do {
            let pin = try CustomPinnedURL(validatingString: raw)
            guard addAndActivate(pin, source: .customPinnedURL) else {
                return false
            }
            customPinnedURLInputState.showOpened("Opened \(pin.displayTitle) in Perch.")
            customPinnedURLInputState.text = ""
            return true
        } catch let error as CustomPinnedURLError {
            customPinnedURLInputState.showValidationFailure(
                CustomPinnedURLPolicy.validationMessage(for: error)
            )
            return false
        } catch {
            customPinnedURLInputState.showValidationFailure("Enter a valid HTTPS URL.")
            return false
        }
    }

    func activateCustomPinnedURL(_ pin: CustomPinnedURL) {
        guard customPinnedURLsEnabled else { return }
        activate(customURL: pin, persist: true)
    }

    func removeCustomPinnedURL(_ pin: CustomPinnedURL) {
        publishCustomPinnedURLs(customPinnedURLs.filter { $0.id != pin.id })
        let wasActive = activeCustomURL?.id == pin.id
        persistCustomPinnedURLs()
        if wasActive {
            returnToNotionPage()
        }
    }

    func returnToNotionPage() {
        guard let activePage else {
            presentCurrentPageSetup()
            return
        }
        clearActiveCustomURL(persistDestination: true)
        pinCoordinator.pin(page: activePage)
    }

    func createNewNotionPage() {
        clearActiveCustomURL(persistDestination: true)
        pinCoordinator.createNewPage()
    }

    func restoreCustomPinnedDestinationIfNeeded() {
        guard customPinnedURLsEnabled,
              let pin = customPinnedURLStore.load().lastActivePin
        else {
            return
        }
        activate(customURL: pin, persist: false)
    }

    @discardableResult
    private func addAndActivate(
        _ pin: CustomPinnedURL,
        source: PageActivationSource
    ) -> Bool {
        var pins = customPinnedURLs.filter { $0.id != pin.id }
        if pins.count >= CustomPinnedURLPolicy.pinLimit {
            customPinnedURLInputState.showValidationFailure(
                "You can pin up to \(CustomPinnedURLPolicy.pinLimit) custom URLs."
            )
            return false
        }
        pins.insert(pin, at: 0)
        publishCustomPinnedURLs(pins)
        publishCustomPinnedURLsEnabled(true)
        persistCustomPinnedURLs()
        activate(customURL: pin, persist: true, source: source)
        return true
    }

    private func activate(
        customURL: CustomPinnedURL,
        persist: Bool,
        source: PageActivationSource = .customPinnedURL
    ) {
        cancelShortcutGesture(restashTransientPanel: false)
        pageSelectionGeneration &+= 1
        pinCoordinator.pin(customURL: customURL)
        publishActiveCustomURL(customURL, source: source)
        if persist {
            persistCustomPinnedURLs()
        }
    }

    func clearActiveCustomURL(persistDestination: Bool) {
        guard activeCustomURL != nil else { return }
        publishActiveCustomURL(nil)
        if persistDestination {
            persistCustomPinnedURLs()
        }
    }

    func persistCustomPinnedURLs() {
        customPinnedURLStore.save(
            CustomPinnedURLSnapshot(
                isEnabled: customPinnedURLsEnabled,
                pins: customPinnedURLs,
                lastActiveID: activeCustomURL?.id
            )
        )
    }
}
