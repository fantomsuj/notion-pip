import Foundation
import OSLog

extension AppRuntime {
    func prepareForTermination() async {
        cancelShortcutGesture(restashTransientPanel: true)
        flushPendingPageMetadataSave()
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
                self?.restoreCustomPinnedDestinationIfNeeded()
                self?.showSettingsIfRestoreStillEmpty(expectedGeneration: expectedGeneration)
                return
            }
            do {
                let workingSet = try await pageRepository.workingSet()
                let storedPage = workingSet.activePage
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
                guard self?.pageSelectionGeneration == expectedGeneration else { return }
                if let storedPage,
                   let page = self?.validRestoredPage(from: storedPage)
                {
                    self?.restorePinnedPage(
                        page,
                        restoration: workingSet.restoration(for: page.pageID),
                        expectedGeneration: expectedGeneration
                    )
                }
                self?.restoreCustomPinnedDestinationIfNeeded()
                self?.showSettingsIfRestoreStillEmpty(
                    expectedGeneration: expectedGeneration
                )
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Pinned page restore failed category=repository-read")
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
                self?.restoreCustomPinnedDestinationIfNeeded()
                self?.showSettingsIfRestoreStillEmpty(expectedGeneration: expectedGeneration)
            }
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

    func schedulePageMetadataSave(of page: NotionPageReference) {
        guard pageRepository != nil else { return }
        pendingPageMetadataSave = page
        pageMetadataSaveTimer?.cancel()
        pageMetadataSaveTimer = pageMetadataSaveScheduler.schedule(
            after: pageMetadataSaveDelay
        ) { [weak self] in
            self?.flushPendingPageMetadataSave()
        }
    }

    func flushPendingPageMetadataSave() {
        pageMetadataSaveTimer?.cancel()
        pageMetadataSaveTimer = nil
        guard let page = pendingPageMetadataSave else { return }
        pendingPageMetadataSave = nil
        enqueueMetadataPersistence(of: page)
    }

    private func enqueueMetadataPersistence(of page: NotionPageReference) {
        guard let pageRepository else { return }
        let previousTask = persistPinnedPageTask
        let logger = logger
        persistenceGeneration &+= 1
        persistPinnedPageTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await pageRepository.updatePageMetadata(page)
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error(
                    """
                    Page title save failed page_id=\(page.pageID, privacy: .private) \
                    category=repository-write
                    """
                )
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
            }
        }
    }
}
