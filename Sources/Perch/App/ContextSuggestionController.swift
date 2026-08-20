import Combine
import Foundation

enum ContextSuggestionPermissionState: Equatable, Sendable {
    case disabled
    case ready
    case needsPermission
}

@MainActor
final class ContextualPageActionState: ObservableObject {
    @Published private(set) var action: ContextualPageAction?

    private var acceptHandler: @MainActor () -> Void = {}
    private var dismissHandler: @MainActor () -> Void = {}

    func accept() {
        acceptHandler()
    }

    func dismiss() {
        dismissHandler()
    }

    func bind(
        onAccept: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        acceptHandler = onAccept
        dismissHandler = onDismiss
    }

    func publish(_ action: ContextualPageAction?) {
        self.action = action
    }
}

@MainActor
final class ContextSuggestionController: ObservableObject {
    static let dismissalDuration: TimeInterval = 30 * 60

    @Published private(set) var isEnabled: Bool
    @Published private(set) var permissionState: ContextSuggestionPermissionState = .disabled
    @Published private(set) var suggestion: ContextSuggestion?
    let contextualPageActionState: ContextualPageActionState

    private let monitor: any ContextMonitoring
    private let store: (any PageWorkingSetPersisting)?
    private let preferenceStore: any ContextSuggestionPreferenceStoring
    private let clock: any DateProviding
    private let exactCaptureTimeout: Duration
    private let activePageID: @MainActor () -> String?
    private let onActivate: @MainActor (NotionPageReference, DurablePageRestoration?) -> Void
    private var matchingTask: Task<Void, Never>?
    private var exactCaptureTimeoutTask: Task<Void, Never>?
    private var evaluationGeneration: UInt = 0
    private var exactCaptureGeneration: UInt = 0
    private var pendingExactCaptureGeneration: UInt?
    private var pendingEmptyFallback: (@MainActor () -> Void)?
    private var preparedContextualRevealSource: PreparedContextualRevealSource?
    private var lastContextIdentity: String?
    private var suppressedUntil: [String: Date] = [:]
    private var hasStarted = false

    private enum PreparedContextualRevealSource {
        case captured(ContextSourceIdentity?)
    }

    init(
        monitor: any ContextMonitoring,
        store: (any PageWorkingSetPersisting)?,
        preferenceStore: any ContextSuggestionPreferenceStoring,
        clock: any DateProviding = SystemDateProvider(),
        exactCaptureTimeout: Duration = .milliseconds(250),
        contextualPageActionState: ContextualPageActionState = ContextualPageActionState(),
        activePageID: @escaping @MainActor () -> String?,
        onActivate: @escaping @MainActor (NotionPageReference, DurablePageRestoration?) -> Void
    ) {
        self.monitor = monitor
        self.store = store
        self.preferenceStore = preferenceStore
        self.clock = clock
        self.exactCaptureTimeout = exactCaptureTimeout
        self.contextualPageActionState = contextualPageActionState
        self.activePageID = activePageID
        self.onActivate = onActivate
        isEnabled = preferenceStore.load()
        monitor.onSnapshot = { [weak self] snapshot in
            guard let snapshot else {
                self?.clearGeneralContext()
                return
            }
            self?.evaluate(snapshot)
        }
        monitor.onAuthorizationChange = { [weak self] authorized in
            self?.authorizationDidChange(authorized)
        }
        contextualPageActionState.bind(
            onAccept: { [weak self] in self?.acceptContextualPageAction() },
            onDismiss: { [weak self] in self?.dismissContextualPageAction() }
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard isEnabled else {
            permissionState = .disabled
            return
        }
        refreshPermission()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            if enabled { refreshPermission(requestIfNeeded: true) }
            return
        }
        isEnabled = enabled
        preferenceStore.save(enabled)
        guard enabled else {
            stopMonitoring()
            permissionState = .disabled
            return
        }
        refreshPermission(requestIfNeeded: true)
    }

    func refreshPermission(requestIfNeeded: Bool = false) {
        guard isEnabled else {
            permissionState = .disabled
            return
        }
        let authorized = monitor.isAuthorized || (requestIfNeeded && monitor.requestAccess())
        guard authorized else {
            stopMonitoring()
            permissionState = .needsPermission
            return
        }
        permissionState = .ready
        monitor.start()
    }

    func acceptSuggestion() {
        guard let suggestion else { return }
        guard suggestion.page.pageID.caseInsensitiveCompare(activePageID() ?? "") != .orderedSame
        else {
            self.suggestion = nil
            return
        }
        self.suggestion = nil
        lastContextIdentity = nil
        onActivate(suggestion.page, suggestion.restoration)
    }

    func dismissSuggestion() {
        guard let suggestion else { return }
        suppressedUntil[suggestion.suppressionKey] = clock.now().addingTimeInterval(
            Self.dismissalDuration
        )
        self.suggestion = nil
    }

    func requestContextualReveal(
        emptyFallback: (@MainActor () -> Void)? = nil
    ) {
        invalidateExactCapture(runEmptyFallback: false)
        contextualPageActionState.publish(nil)
        guard isEnabled,
              permissionState == .ready,
              monitor.isAuthorized
        else {
            discardPreparedContextualRevealSource()
            emptyFallback?()
            return
        }

        exactCaptureGeneration &+= 1
        let generation = exactCaptureGeneration
        pendingExactCaptureGeneration = generation
        pendingEmptyFallback = emptyFallback
        exactCaptureTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: exactCaptureTimeout)
            guard !Task.isCancelled else { return }
            completeExactCapture(nil, generation: generation)
        }
        let completion: @MainActor (ContextSnapshot?) -> Void = { [weak self] snapshot in
            self?.completeExactCapture(snapshot, generation: generation)
        }
        if let preparedContextualRevealSource {
            self.preparedContextualRevealSource = nil
            switch preparedContextualRevealSource {
            case let .captured(source):
                guard let source else {
                    completeExactCapture(nil, generation: generation)
                    return
                }
                monitor.captureExactPage(from: source, completion: completion)
            }
        } else {
            monitor.captureExactPage(completion: completion)
        }
    }

    func prepareContextualRevealSource() {
        guard isEnabled,
              permissionState == .ready,
              monitor.isAuthorized
        else {
            preparedContextualRevealSource = nil
            return
        }
        preparedContextualRevealSource = .captured(monitor.captureSourceIdentity())
    }

    func discardPreparedContextualRevealSource() {
        preparedContextualRevealSource = nil
    }

    func activePageDidChange() {
        clearGeneralContext()
        discardPreparedContextualRevealSource()
        invalidateExactCapture(runEmptyFallback: false)
        contextualPageActionState.publish(nil)
    }

    private func authorizationDidChange(_ authorized: Bool) {
        guard isEnabled else { return }
        if authorized {
            permissionState = .ready
        } else {
            matchingTask?.cancel()
            matchingTask = nil
            suggestion = nil
            discardPreparedContextualRevealSource()
            invalidateExactCapture(runEmptyFallback: true)
            contextualPageActionState.publish(nil)
            permissionState = .needsPermission
        }
    }

    private func stopMonitoring() {
        evaluationGeneration &+= 1
        matchingTask?.cancel()
        matchingTask = nil
        suggestion = nil
        lastContextIdentity = nil
        discardPreparedContextualRevealSource()
        invalidateExactCapture(runEmptyFallback: true)
        contextualPageActionState.publish(nil)
        monitor.stop()
    }

    private func clearGeneralContext() {
        evaluationGeneration &+= 1
        matchingTask?.cancel()
        matchingTask = nil
        suggestion = nil
        lastContextIdentity = nil
    }

    private func completeExactCapture(
        _ snapshot: ContextSnapshot?,
        generation: UInt
    ) {
        guard pendingExactCaptureGeneration == generation else { return }
        pendingExactCaptureGeneration = nil
        exactCaptureTimeoutTask?.cancel()
        exactCaptureTimeoutTask = nil
        let emptyFallback = pendingEmptyFallback
        pendingEmptyFallback = nil

        guard let snapshot,
              let exactPage = snapshot.exactPage,
              snapshot.bundleIdentifier != (Bundle.main.bundleIdentifier ?? "")
        else {
            emptyFallback?()
            return
        }
        guard exactPage.pageID.caseInsensitiveCompare(activePageID() ?? "") != .orderedSame
        else {
            return
        }
        guard activePageID() != nil else {
            onActivate(exactPage, nil)
            return
        }
        contextualPageActionState.publish(
            ContextualPageAction(
                page: exactPage,
                sourceApplicationName: snapshot.applicationName
            )
        )
    }

    private func acceptContextualPageAction() {
        guard let action = contextualPageActionState.action else { return }
        contextualPageActionState.publish(nil)
        guard action.page.pageID.caseInsensitiveCompare(activePageID() ?? "") != .orderedSame
        else {
            return
        }
        onActivate(action.page, nil)
    }

    private func dismissContextualPageAction() {
        contextualPageActionState.publish(nil)
    }

    private func invalidateExactCapture(runEmptyFallback: Bool) {
        exactCaptureGeneration &+= 1
        pendingExactCaptureGeneration = nil
        exactCaptureTimeoutTask?.cancel()
        exactCaptureTimeoutTask = nil
        let emptyFallback = pendingEmptyFallback
        pendingEmptyFallback = nil
        if runEmptyFallback {
            emptyFallback?()
        }
    }

    private func evaluate(_ context: ContextSnapshot) {
        guard isEnabled, permissionState == .ready,
              context.bundleIdentifier != (Bundle.main.bundleIdentifier ?? ""),
              context.identity != lastContextIdentity
        else { return }
        lastContextIdentity = context.identity
        evaluationGeneration &+= 1
        let generation = evaluationGeneration
        matchingTask?.cancel()
        guard let store else {
            suggestion = nil
            return
        }
        let currentPageID = activePageID()
        matchingTask = Task { [weak self] in
            let snapshot = try? await store.workingSet()
            guard let self, !Task.isCancelled, generation == self.evaluationGeneration,
                  let snapshot
            else { return }
            let candidate = ContextSuggestionMatcher.bestSuggestion(
                in: snapshot,
                context: context,
                activePageID: currentPageID
            )
            guard let candidate else {
                self.suggestion = nil
                return
            }
            guard candidate.page.pageID.caseInsensitiveCompare(self.activePageID() ?? "")
                != .orderedSame
            else {
                self.suggestion = nil
                return
            }
            let now = self.clock.now()
            self.suppressedUntil = self.suppressedUntil.filter { $0.value > now }
            guard self.suppressedUntil[candidate.suppressionKey, default: .distantPast] <= now
            else {
                self.suggestion = nil
                return
            }
            self.suggestion = candidate
        }
    }
}
