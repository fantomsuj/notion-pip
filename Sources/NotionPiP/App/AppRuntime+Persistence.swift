import Foundation
import OSLog

extension AppRuntime {
    func presentPageURLInputAfterRestoreIfNeeded() {
        guard activePage == nil, firstPageHandoffTask == nil else { return }
        isFirstPageHandoffPending = true
        let restoreTask = restorePinnedPageTask
        firstPageHandoffTask = Task { [weak self] in
            await restoreTask?.value
            guard let self else { return }
            defer {
                isFirstPageHandoffPending = false
                firstPageHandoffTask = nil
            }
            guard !Task.isCancelled, activePage == nil else { return }
            pageURLInputPresenter.presentAndFocus()
        }
    }

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
                self?.showSettingsIfRestoreStillEmpty(expectedGeneration: expectedGeneration)
                return
            }
            do {
                let workingSet = try await pageRepository.workingSet()
                let storedPage = workingSet.activePage
                guard !Task.isCancelled else { return }
                self?.resolveServiceIssue(.pinnedPagePersistenceUnavailable)
                guard let storedPage else {
                    self?.showSettingsIfRestoreStillEmpty(
                        expectedGeneration: expectedGeneration
                    )
                    return
                }
                guard let page = self?.validRestoredPage(from: storedPage) else {
                    self?.showSettingsIfRestoreStillEmpty(
                        expectedGeneration: expectedGeneration
                    )
                    return
                }
                guard !Task.isCancelled else { return }
                self?.restorePinnedPage(
                    page,
                    restoration: workingSet.restoration(for: page.pageID),
                    expectedGeneration: expectedGeneration
                )
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Pinned page restore failed category=repository-read")
                self?.reportServiceIssue(.pinnedPagePersistenceUnavailable)
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
              !isFirstPageHandoffPending,
              automaticSettingsPresentationAllowed(),
              !Task.isCancelled
        else {
            return
        }
        settingsWindowPresenter?.show()
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
