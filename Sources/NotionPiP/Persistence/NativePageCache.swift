import Foundation

protocol NativePageCaching: AnyObject {
    func load(pageID: String) throws -> NativePageSnapshot?
    func save(_ snapshot: NativePageSnapshot) throws
    func remove(pageID: String) throws
    func removeAll() throws
}

final class FileNativePageCache: NativePageCaching {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = appSupport.appending(path: "NotionPiP/NativePageCache", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(pageID: String) throws -> NativePageSnapshot? {
        let url = fileURL(pageID: pageID)
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return nil
        }
        return try decoder.decode(NativePageSnapshot.self, from: Data(contentsOf: url))
    }

    func save(_ snapshot: NativePageSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(pageID: snapshot.pageID), options: .atomic)
    }

    func remove(pageID: String) throws {
        let url = fileURL(pageID: pageID)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func removeAll() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path()) else { return }
        try fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(pageID: String) -> URL {
        directory.appending(path: "\(pageID).json", directoryHint: .notDirectory)
    }
}
