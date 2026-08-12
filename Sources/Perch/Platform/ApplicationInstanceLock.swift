import Darwin
import Foundation

enum ApplicationInstanceLockError: Error, Equatable {
    case unableToOpenLockFile(Int32)
}

final class ApplicationInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        _ = Darwin.close(fileDescriptor)
    }

    static func acquire(at lockFileURL: URL) throws -> ApplicationInstanceLock? {
        try FileManager.default.createDirectory(
            at: lockFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fileDescriptor = lockFileURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK,
                S_IRUSR | S_IWUSR
            )
        }
        guard fileDescriptor >= 0 else {
            let openError = errno
            if openError == EWOULDBLOCK {
                return nil
            }
            throw ApplicationInstanceLockError.unableToOpenLockFile(openError)
        }

        return ApplicationInstanceLock(fileDescriptor: fileDescriptor)
    }
}
