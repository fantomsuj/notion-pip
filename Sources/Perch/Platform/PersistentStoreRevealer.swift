import AppKit
import Foundation

struct PersistentStoreRevealer {
    private let storeDirectory: URL
    private let fileExists: (URL) -> Bool
    private let reveal: ([URL]) -> Void

    init(
        storeDirectory: URL,
        fileExists: @escaping (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        },
        reveal: @escaping ([URL]) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting($0)
        }
    ) {
        self.storeDirectory = storeDirectory
        self.fileExists = fileExists
        self.reveal = reveal
    }

    func revealStore() {
        let storeURL = storeDirectory.appendingPathComponent("Perch.store")
        reveal([fileExists(storeURL) ? storeURL : storeDirectory])
    }
}
