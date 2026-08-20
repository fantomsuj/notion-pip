import Combine
import Foundation
import OSLog

@MainActor
final class AppRuntime: ObservableObject, ApplicationURLHandling {
    @Published private(set) var pendingPage: NotionPageReference?
    @Published private(set) var activePage: NotionPageReference?
    @Published private(set) var lastActivationSource: PageActivationSource?
    @Published private(set) var serviceHealth: ServiceHealthState
    @Published private(set) var globalShortcut: GlobalShortcut
    @Published private(set) var holdToPeekEnabled: Bool
    @Published private(set) var savedMenuBarIconVisibility: Bool
    @Published private(set) var effectiveMenuBarIconVisibility: Bool
    @Published private(set) var isMenuBarIconVisibilityForced: Bool
    @Published private(set) var statusItemGlyph: StatusItemGlyph
    @Published private(set) var statusItemSummonGeneration: UInt = 0

    let pageURLInputState: PageURLInputState

    var pageURLText: String {
        get { pageURLInputState.text }
        set { pageURLInputState.text = newValue }
    }

    var validationMessage: String? { pageURLInputState.validationMessage }
    var validationFailed: Bool { pageURLInputState.validationFailed }
    var pageURLFocusRequest: Int { pageURLInputState.focusRequest }

    var pipPresentationState: PiPPresentationState { pinCoordinator.presentationState }

    var statusMenuContextCommand: StatusMenuContextCommand {
        StatusMenuContextCommand(presentationState: pipPresentationState)
    }

    let logger = Logger(subsystem: "com.fantomsuj.Perch", category: "shortcut")
    let pinCoordinator: PinCoordinator
    let shortcutRegistrar: any GlobalShortcutRegistering
    let shortcutStore: GlobalShortcutStore
    let holdToPeekPreferenceStore: HoldToPeekPreferenceStore
    let peekFocusRestorer: any PeekFocusRestoring
    let performanceSignposter: any PerformanceSignposting
    let menuBarIconPreferenceStore: MenuBarIconPreferenceStore
    let pageRepository: (any PageWorkingSetPersisting)?
    let automaticSettingsPresentationAllowed: @MainActor () -> Bool
    weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    var persistentStoreRecoveryAction: @MainActor () -> Void = {}
    var restorePinnedPageTask: Task<Void, Never>?
    var persistPinnedPageTask: Task<Void, Never>?
    var suppressesAutomaticCurrentPageSetup = false
    var persistenceGeneration = 0
    var pageSelectionGeneration = 0
    let shortcutHoldDuration: Duration
    let shortcutGestureScheduler: any ShortcutGestureScheduling
    let accessibilityAnnouncementPoster: any AccessibilityAnnouncementPosting
    let shortcutLifecycleCoordinatorFactory:
        (@escaping @MainActor (ShortcutRecoveryTrigger) -> Void) -> ShortcutLifecycleCoordinator
    var shortcutLifecycleCoordinator: ShortcutLifecycleCoordinator?
    var shortcutRegistrationGeneration: UInt = 0
    var shortcutGestureTimer: (any ShortcutGestureTimer)?
    var shortcutGestureState = ShortcutPeekGestureState.idle
    var shortcutGestureGeneration: UInt = 0
    var statusItemPeekState = StatusItemPeekState.idle
    var statusItemPeekGeneration: UInt = 0
    var statusItemSessionState: NotionWebSessionState = .unloaded
    var statusItemLoginState: NotionBrowserLoginState = .idle
    private var started = false

    init(
        panelCoordinator: (any PiPPanelCoordinating)? = nil,
        pasteboard: any PasteboardReading = SystemPasteboardReader(),
        shortcutRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        shortcutStore: GlobalShortcutStore = GlobalShortcutStore(),
        menuBarIconPreferenceStore: MenuBarIconPreferenceStore = MenuBarIconPreferenceStore(),
        holdToPeekPreferenceStore: HoldToPeekPreferenceStore = HoldToPeekPreferenceStore(),
        peekFocusRestorer: any PeekFocusRestoring = PeekFocusRestorer(),
        performanceSignposter: any PerformanceSignposting = AppPerformanceSignposter.shared,
        pageRepository: (any PageWorkingSetPersisting)? = nil,
        shortcutHoldDuration: Duration = .milliseconds(300),
        shortcutGestureScheduler: any ShortcutGestureScheduling = TaskShortcutGestureScheduler(),
        accessibilityAnnouncementPoster: any AccessibilityAnnouncementPosting =
            AppAccessibilityAnnouncementPoster(),
        initialServiceHealth: ServiceHealthState = .healthy,
        automaticSettingsPresentationAllowed: @escaping @MainActor () -> Bool = { true },
        shortcutLifecycleCoordinatorFactory:
            @escaping (@escaping @MainActor (ShortcutRecoveryTrigger) -> Void) -> ShortcutLifecycleCoordinator = {
                ShortcutLifecycleCoordinator(onRecovery: $0)
            }
    ) {
        let inputState = PageURLInputState()
        let inputRequestRelay = PageURLInputRequestRelay()

        pageURLInputState = inputState
        pinCoordinator = PinCoordinator(
            panelCoordinator: panelCoordinator ?? PiPPanelCoordinator(),
            pasteboard: pasteboard,
            requestPageURLFocus: inputRequestRelay.request
        )
        self.shortcutRegistrar = shortcutRegistrar
        self.shortcutStore = shortcutStore
        self.holdToPeekPreferenceStore = holdToPeekPreferenceStore
        self.peekFocusRestorer = peekFocusRestorer
        self.performanceSignposter = performanceSignposter
        self.menuBarIconPreferenceStore = menuBarIconPreferenceStore
        self.pageRepository = pageRepository
        self.automaticSettingsPresentationAllowed = automaticSettingsPresentationAllowed
        self.shortcutHoldDuration = shortcutHoldDuration
        self.shortcutGestureScheduler = shortcutGestureScheduler
        self.accessibilityAnnouncementPoster = accessibilityAnnouncementPoster
        self.shortcutLifecycleCoordinatorFactory = shortcutLifecycleCoordinatorFactory
        serviceHealth = initialServiceHealth
        globalShortcut = shortcutStore.load()
        holdToPeekEnabled = holdToPeekPreferenceStore.load()
        let iconState = Self.menuBarIconState(
            store: menuBarIconPreferenceStore,
            serviceHealth: initialServiceHealth
        )
        savedMenuBarIconVisibility = iconState.saved
        effectiveMenuBarIconVisibility = iconState.effective
        isMenuBarIconVisibilityForced = iconState.forced
        statusItemGlyph = StatusItemGlyphPolicy.glyph(
            presentation: .unavailable,
            sessionState: .unloaded,
            loginState: .idle
        )
        pinCoordinator.onExternalPresentationAction = { [weak self] in
            self?.cancelShortcutGesture(restashTransientPanel: false)
        }
        pinCoordinator.onPresentationStateChange = { [weak self] in
            self?.refreshStatusItemGlyph()
        }
        inputRequestRelay.handler = { [weak self] in
            self?.presentCurrentPageSetup()
        }
    }

    func start() {
        guard !started else { return }
        started = true

        registerGlobalShortcut()
        let shortcutLifecycleCoordinator = shortcutLifecycleCoordinatorFactory { [weak self] trigger in
            self?.recoverShortcut(trigger: trigger)
        }
        self.shortcutLifecycleCoordinator = shortcutLifecycleCoordinator
        shortcutLifecycleCoordinator.start()
        restorePinnedPageFromRepository()
    }

    func bind(settingsWindowPresenter: any SettingsWindowPresenting) {
        self.settingsWindowPresenter = settingsWindowPresenter
    }

    func bindPersistentStoreRecoveryAction(
        _ action: @escaping @MainActor () -> Void
    ) {
        persistentStoreRecoveryAction = action
    }

    func presentCurrentPageSetup() {
        settingsWindowPresenter?.show()
        pageURLInputState.requestFocus()
    }

    func suppressAutomaticCurrentPageSetup() {
        suppressesAutomaticCurrentPageSetup = true
    }

    func retryRecovery(for issue: ServiceHealthIssue) {
        switch issue {
        case .globalShortcutUnavailable:
            registerGlobalShortcut()
        case .pinnedPagePersistenceUnavailable:
            if let activePage {
                enqueuePersistence(of: activePage)
            } else {
                restorePinnedPageFromRepository()
            }
        case .persistentStoreUnavailable:
            persistentStoreRecoveryAction()
        }
    }

    func publishActivation(
        page: NotionPageReference,
        source: PageActivationSource
    ) {
        activePage = page
        pendingPage = page
        lastActivationSource = source
    }

    func publishHoldToPeekEnabled(_ enabled: Bool) {
        holdToPeekEnabled = enabled
    }

    func publishGlobalShortcut(_ shortcut: GlobalShortcut) {
        globalShortcut = shortcut
    }

    func publishMenuBarIconVisibility(_ isVisible: Bool) {
        savedMenuBarIconVisibility = isVisible
        updateEffectiveMenuBarIconVisibility()
    }

    func publishStatusItemSession(
        sessionState: NotionWebSessionState,
        loginState: NotionBrowserLoginState
    ) {
        statusItemSessionState = sessionState
        statusItemLoginState = loginState
        refreshStatusItemGlyph()
    }

    func acknowledgeSummon() {
        statusItemSummonGeneration &+= 1
    }

    func refreshStatusItemGlyph() {
        let glyph = StatusItemGlyphPolicy.glyph(
            presentation: pipPresentationState,
            sessionState: statusItemSessionState,
            loginState: statusItemLoginState
        )
        guard glyph != statusItemGlyph else { return }
        statusItemGlyph = glyph
    }

    func reportServiceIssue(_ issue: ServiceHealthIssue) {
        serviceHealth.report(issue)
        if issue == .globalShortcutUnavailable {
            updateEffectiveMenuBarIconVisibility()
        }
    }

    func resolveServiceIssue(_ issue: ServiceHealthIssue) {
        serviceHealth.resolve(issue)
        if issue == .globalShortcutUnavailable {
            updateEffectiveMenuBarIconVisibility()
        }
    }

    private func updateEffectiveMenuBarIconVisibility() {
        let isForced = serviceHealth.issues.contains(.globalShortcutUnavailable)
            && !savedMenuBarIconVisibility
        isMenuBarIconVisibilityForced = isForced
        effectiveMenuBarIconVisibility = savedMenuBarIconVisibility || isForced
    }

    private static func menuBarIconState(
        store: MenuBarIconPreferenceStore,
        serviceHealth: ServiceHealthState
    ) -> MenuBarIconState {
        let saved = store.load()
        let forced = serviceHealth.issues.contains(.globalShortcutUnavailable) && !saved
        return MenuBarIconState(saved: saved, effective: saved || forced, forced: forced)
    }

    isolated deinit {
        shortcutLifecycleCoordinator?.stop()
    }
}

private struct MenuBarIconState {
    let saved: Bool
    let effective: Bool
    let forced: Bool
}

@MainActor
private final class PageURLInputRequestRelay {
    var handler: (@MainActor () -> Void)?

    func request() {
        handler?()
    }
}
