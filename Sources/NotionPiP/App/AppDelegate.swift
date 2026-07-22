import AppKit
import OSLog

@MainActor
protocol ApplicationURLHandling: AnyObject {
    func handleOpenURLs(_ urls: [URL])
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "lifecycle")
    private var urlHandler: (any ApplicationURLHandling)?
    private var bufferedOpenURLs: [URL] = []

    func bind(urlHandler: any ApplicationURLHandling) {
        guard self.urlHandler == nil else {
            return
        }

        self.urlHandler = urlHandler
        let bufferedOpenURLs = self.bufferedOpenURLs
        self.bufferedOpenURLs.removeAll(keepingCapacity: false)
        if !bufferedOpenURLs.isEmpty {
            urlHandler.handleOpenURLs(bufferedOpenURLs)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application launched in accessory mode")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let urlHandler else {
            bufferedOpenURLs.append(contentsOf: urls)
            return
        }

        urlHandler.handleOpenURLs(urls)
    }
}
