import Combine
import Foundation

/// Owns the hosting, suspension, and eviction policy for the live Notion web view.
///
/// The controller deliberately does not retain WebKit objects. `NotionWebSession` remains
/// responsible for creating and retiring those MainActor-bound objects and executes the
/// commands produced by this policy boundary.
@MainActor
final class NotionWebLifecycleController: ObservableObject {
    enum Visibility: Equatable {
        case visible
        case hidden
    }

    enum ResumeCommand: Equatable {
        case none
        case restorePreviousState(NotionWebSessionState)
        case loadActivePage
    }

    static let defaultWarmRetentionInterval: TimeInterval = 60

    @Published private(set) var state: NotionWebSessionState
    @Published private(set) var visibility: Visibility = .visible

    var onEvictionRequested: (@MainActor () -> Void)?

    private let warmRetentionInterval: TimeInterval
    private let scheduleEviction: NotionWebEvictionScheduler
    private var stateBeforeSuspension: NotionWebSessionState = .unloaded
    private var evictionCancellable: AnyCancellable?
    private var evictionIsProtected = false

    init(
        initialState: NotionWebSessionState = .unloaded,
        warmRetentionInterval: TimeInterval = defaultWarmRetentionInterval,
        scheduleEviction: @escaping NotionWebEvictionScheduler
    ) {
        state = initialState
        self.warmRetentionInterval = warmRetentionInterval
        self.scheduleEviction = scheduleEviction
    }

    var isVisible: Bool { visibility == .visible }

    func shouldHostWebView(hasWebView: Bool) -> Bool {
        isVisible && state != .suspended && hasWebView
    }

    func setState(_ state: NotionWebSessionState) {
        self.state = state
    }

    func publishNavigationState(_ navigationState: NotionWebSessionState) {
        if state == .suspended {
            stateBeforeSuspension = navigationState
        } else {
            state = navigationState
        }
    }

    func panelDidHide() {
        visibility = .hidden
    }

    func panelDidShow(hasWebView: Bool, hasActivePage: Bool) -> ResumeCommand {
        visibility = .visible
        evictionCancellable?.cancel()
        evictionCancellable = nil

        guard state == .suspended else {
            return !hasWebView && hasActivePage ? .loadActivePage : .none
        }
        guard hasActivePage else {
            let restoredState: NotionWebSessionState = hasWebView
                ? stateBeforeSuspension
                : .unloaded
            state = restoredState
            return .restorePreviousState(restoredState)
        }
        guard hasWebView else {
            return .loadActivePage
        }
        let restoredState = stateBeforeSuspension == .suspended
            ? NotionWebSessionState.active
            : stateBeforeSuspension
        state = restoredState
        return .restorePreviousState(restoredState)
    }

    @discardableResult
    func suspend(hasWebView: Bool) -> Bool {
        guard hasWebView, state != .suspended else { return false }
        stateBeforeSuspension = state
        state = .suspended
        evictionCancellable?.cancel()
        evictionCancellable = scheduleEviction(warmRetentionInterval) { [weak self] in
            self?.requestEvictionIfEligible()
        }
        return true
    }

    func setEvictionProtected(_ isProtected: Bool) {
        evictionIsProtected = isProtected
    }

    @discardableResult
    func requestEvictionIfEligible() -> Bool {
        guard state == .suspended, visibility == .hidden, !evictionIsProtected else {
            return false
        }
        evictionCancellable?.cancel()
        evictionCancellable = nil
        onEvictionRequested?()
        return true
    }

    func didEvictWebView() {
        state = .unloaded
    }

    func cancelWarmRetention() {
        evictionCancellable?.cancel()
        evictionCancellable = nil
    }
}
