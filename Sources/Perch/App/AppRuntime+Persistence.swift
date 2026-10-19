import Foundation
import OSLog

extension AppRuntime {
    func prepareForTermination() async {
        cancelShortcutGesture(restashTransientPanel: true)
        while let persistenceTask = persistPinnedPageTask {
            let expectedGeneration = persistenceGeneration
            await persistenceTask.value
            guard expectedGeneration != persistenceGeneration else { return }
        }
    }

    func restorePinnedPageFromRepository() {
        let expectedGeneration = pageSelectionGeneration
        let pageRepository = pageRepository
        let logger = logger
        restorePinnedPageTask?.cancel()
        restorePinnedPageTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            guard let pageRepository else {
                self?.restoreLaunchDestination(
                    page: nil,
                    restoration: nil,
                    expectedGeneration: expectedGeneration
                )
                return
            }
            do {
                let workingSet = try await pageRepository.workingSet()
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
                let page = workingSet.activePage.flatMap {
                    self?.validRestoredPage(from: $0)
                }
                self?.restoreLaunchDestination(
                    page: page,
                    restoration: page.flatMap { workingSet.restoration(for: $0.pageID) },
                    expectedGeneration: expectedGeneration
                )
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Pinned page restore failed category=repository-read")
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
                self?.restoreLaunchDestination(
                    page: nil,
                    restoration: nil,
                    expectedGeneration: expectedGeneration
                )
            }
        }
    }

    /// Picks one launch target before anything is shown: the last custom URL
    /// when one was open, otherwise the saved Notion page. The panel comes back
    /// stashed when it was stashed at quit.
    private func restoreLaunchDestination(
        page: NotionPageReference?,
        restoration: DurablePageRestoration?,
        expectedGeneration: Int
    ) {
        guard expectedGeneration == pageSelectionGeneration, !Task.isCancelled else { return }
        let stashed = panelStashStateStore.load()
        if let customURL = launchCustomPinnedDestination() {
            if let page {
                // Keep the Notion page as the return target without loading it.
                publishActivation(page: page, source: .restored)
            }
            restoreCustomPinnedDestination(customURL, stashed: stashed)
        } else if let page {
            restorePinnedPage(
                page,
                restoration: restoration,
                expectedGeneration: expectedGeneration,
                stashed: stashed
            )
        }
        showSettingsIfRestoreStillEmpty(expectedGeneration: expectedGeneration)
    }

    func persistPanelStashState() {
        switch pipPresentationState {
        case .visible:
            panelStashStateStore.save(false)
        case .stashed:
            panelStashStateStore.save(true)
        case .unavailable:
            break
        }
    }

    private func validRestoredPage(
        from storedPage: StoredPageSnapshot
    ) -> NotionPageReference? {
        guard let page = try? NotionPageReference(validating: storedPage.canonicalURL),
              page.canonicalURL == storedPage.canonicalURL,
              page.pageID == storedPage.pageID
        else {
            logger.error(
                """
                Pinned page restore skipped page_id=\(storedPage.pageID, privacy: .private) \
                category=invalid-stored-value
                """
            )
            return nil
        }
        return page
    }

    private func showSettingsIfRestoreStillEmpty(expectedGeneration: Int) {
        guard expectedGeneration == pageSelectionGeneration,
              activePage == nil,
              activeCustomURL == nil,
              !suppressesAutomaticCurrentPageSetup,
              automaticSettingsPresentationAllowed(),
              !Task.isCancelled
        else {
            return
        }
        presentCurrentPageSetup()
    }

    func enqueuePersistence(of page: NotionPageReference) {
        guard let pageRepository else { return }
        let previousTask = persistPinnedPageTask
        let logger = logger
        persistenceGeneration &+= 1
        persistPinnedPageTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                _ = try await pageRepository.recordVisit(page)
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error(
                    """
                    Pinned page save failed page_id=\(page.pageID, privacy: .private) \
                    category=repository-write
                    """
                )
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
            }
        }
    }
}
