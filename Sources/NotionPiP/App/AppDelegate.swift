import AppKit
import OSLog

@MainActor
protocol ApplicationURLHandling: AnyObject {
    func handleOpenURLs(_ urls: [URL])
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.fantomsuj.NotionPiP", category: "lifecycle")
    private let replyToApplicationShouldTerminate: @MainActor (NSApplication, Bool) -> Void
    private var urlHandler: (any ApplicationURLHandling)?
    private var bufferedOpenURLs: [URL] = []
    private var terminationHandler: (@MainActor () async -> Void)?
    private var terminationTask: Task<Void, Never>?
    private var performanceSignposter: (any PerformanceSignposting)?
    private var coldLaunchToken: PerformanceIntervalToken?

    override init() {
        replyToApplicationShouldTerminate = { application, shouldTerminate in
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        super.init()
    }

    init(
        replyToApplicationShouldTerminate: @escaping @MainActor (NSApplication, Bool) -> Void
    ) {
        self.replyToApplicationShouldTerminate = replyToApplicationShouldTerminate
        super.init()
    }

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

    func bind(terminationHandler: @escaping @MainActor () async -> Void) {
        guard self.terminationHandler == nil else { return }
        self.terminationHandler = terminationHandler
    }

    func bind(
        coldLaunchToken: PerformanceIntervalToken?,
        performanceSignposter: any PerformanceSignposting
    ) {
        guard let coldLaunchToken, self.coldLaunchToken == nil else { return }
        self.coldLaunchToken = coldLaunchToken
        self.performanceSignposter = performanceSignposter
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application launched in accessory mode")
        performanceSignposter?.end(coldLaunchToken, outcome: .success)
        coldLaunchToken = nil
        performanceSignposter = nil
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let urlHandler else {
            bufferedOpenURLs.append(contentsOf: urls)
            return
        }

        urlHandler.handleOpenURLs(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        let terminationHandler = terminationHandler
        let replyToApplicationShouldTerminate = replyToApplicationShouldTerminate
        terminationTask = Task { @MainActor in
            if let terminationHandler {
                await terminationHandler()
            }
            replyToApplicationShouldTerminate(sender, true)
        }
        return .terminateLater
    }
}
