import Foundation

protocol LegacyNativePageCacheCleaning {
    func removeLegacyCache(at directory: URL) throws
}

struct FileSystemLegacyNativePageCacheCleaner: LegacyNativePageCacheCleaning {
    static var defaultDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("NotionPiP", isDirectory: true)
            .appendingPathComponent("NativePageCache", isDirectory: true)
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func removeLegacyCache(at directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
