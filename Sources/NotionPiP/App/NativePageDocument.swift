import Combine
import Foundation

enum NativePagePreviewState: Equatable {
    case idle
    case cached
    case unavailable
}

@MainActor
final class NativePageDocument: ObservableObject {
    @Published private(set) var snapshot: NativePageSnapshot?
    @Published private(set) var previewState: NativePagePreviewState = .idle
    private let cache: any NativePageCaching

    init(cache: any NativePageCaching = FileNativePageCache()) {
        self.cache = cache
    }

    func load(_ snapshot: NativePageSnapshot) {
        self.snapshot = snapshot
        previewState = .cached
        try? cache.save(snapshot)
    }

    func restoreCachedPage(pageID: String) {
        guard let cachedSnapshot = try? cache.load(pageID: pageID) else {
            snapshot = nil
            previewState = .idle
            return
        }
        snapshot = cachedSnapshot
        previewState = .cached
    }

    func markUnavailable() {
        previewState = .unavailable
    }

    func clearLocalPages() {
        try? cache.removeAll()
        snapshot = nil
        previewState = .idle
    }
}
