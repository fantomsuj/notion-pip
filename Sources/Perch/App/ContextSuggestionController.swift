import Combine
import Foundation

enum ContextSuggestionPermissionState: Equatable, Sendable {
    case disabled
    case ready
    case needsPermission
}

@MainActor
final class ContextSuggestionController: ObservableObject {
    static let dismissalDuration: TimeInterval = 30 * 60

    @Published private(set) var isEnabled: Bool
    @Published private(set) var permissionState: ContextSuggestionPermissionState = .disabled
    @Published private(set) var suggestion: ContextSuggestion?

    private let monitor: any ContextMonitoring
    private let store: (any PageWorkingSetPersisting)?
    private let preferenceStore: any ContextSuggestionPreferenceStoring
    private let clock: any DateProviding
    private let activePageID: @MainActor () -> String?
    private let onActivate: @MainActor (NotionPageReference, DurablePageRestoration?) -> Void
    private var matchingTask: Task<Void, Never>?
    private var evaluationGeneration: UInt = 0
    private var lastContextIdentity: String?
    private var suppressedUntil: [String: Date] = [:]
    private var hasStarted = false

    init(
        monitor: any ContextMonitoring,
        store: (any PageWorkingSetPersisting)?,
        preferenceStore: any ContextSuggestionPreferenceStoring,
        clock: any DateProviding = SystemDateProvider(),
        activePageID: @escaping @MainActor () -> String?,
        onActivate: @escaping @MainActor (NotionPageReference, DurablePageRestoration?) -> Void
    ) {
        self.monitor = monitor
        self.store = store
        self.preferenceStore = preferenceStore
        self.clock = clock
        self.activePageID = activePageID
        self.onActivate = onActivate
        isEnabled = preferenceStore.load()
        monitor.onSnapshot = { [weak self] snapshot in
            guard let snapshot else {
                self?.clearCurrentContext()
                return
            }
            self?.evaluate(snapshot)
        }
        monitor.onAuthorizationChange = { [weak self] authorized in
            self?.authorizationDidChange(authorized)
        }
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

    func activePageDidChange() {
        clearCurrentContext()
    }

    private func authorizationDidChange(_ authorized: Bool) {
        guard isEnabled else { return }
        if authorized {
            permissionState = .ready
        } else {
            matchingTask?.cancel()
            matchingTask = nil
            suggestion = nil
            permissionState = .needsPermission
        }
    }

    private func stopMonitoring() {
        evaluationGeneration &+= 1
        matchingTask?.cancel()
        matchingTask = nil
        suggestion = nil
        lastContextIdentity = nil
        monitor.stop()
    }

    private func clearCurrentContext() {
        evaluationGeneration &+= 1
        matchingTask?.cancel()
        matchingTask = nil
        suggestion = nil
        lastContextIdentity = nil
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
