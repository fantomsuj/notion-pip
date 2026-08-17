enum StorageRecoveryAction: CaseIterable, Equatable {
    case revealStore
    case continueWithoutSaving
    case archiveStoreAndQuit

    var label: String {
        switch self {
        case .revealStore:
            "Reveal Store in Finder"
        case .continueWithoutSaving:
            "Continue Without Saving"
        case .archiveStoreAndQuit:
            "Archive Store and Quit…"
        }
    }

    var accessibilityHelp: String {
        switch self {
        case .revealStore:
            "Selects the local Perch store, or its containing folder when the primary store is missing."
        case .continueWithoutSaving:
            "Closes this window and uses Perch for this session without saving local page history."
        case .archiveStoreAndQuit:
            "Confirms moving only Perch store artifacts into Recovery before quitting."
        }
    }

    var isDefault: Bool {
        self == .continueWithoutSaving
    }
}

enum StorageRecoveryPresentation {
    static let title = "Perch Couldn’t Open Local Storage"
    static let explanation =
        "Notion pages and account data are unaffected. You can keep using the embedded Notion site, but Perch will not save local page history during this session."
    static let archiveConfirmationTitle = "Archive Local Store and Quit Perch?"
    static let archiveConfirmationMessage =
        "Perch will move any existing Perch.store, Perch.store-wal, Perch.store-shm, Perch.store-journal, and Perch.store_SUPPORT artifacts into a new dated Recovery folder, then quit. No files are deleted or overwritten. Reopening Perch starts with empty local page history. Notion pages and account data are unaffected."
}
