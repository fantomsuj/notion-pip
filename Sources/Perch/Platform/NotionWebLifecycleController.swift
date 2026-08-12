import Combine

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

    @Published private(set) var state: NotionWebSessionState
    @Published private(set) var visibility: Visibility = .visible

    var onEvictionRequested: (@MainActor () -> Void)?

    private var stateBeforeSuspension: NotionWebSessionState = .unloaded
    private var evictionIsProtected = false

    init(initialState: NotionWebSessionState = .unloaded) {
        state = initialState
    }

    var isVisible: Bool {
        visibility == .visible
    }

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
        return true
    }

    func setEvictionProtected(_ isProtected: Bool) {
        evictionIsProtected = isProtected
    }

    @discardableResult
    func requestEvictionIfEligible(ignoringProtection: Bool = false) -> Bool {
        guard state == .suspended,
              visibility == .hidden,
              ignoringProtection || !evictionIsProtected
        else {
            return false
        }
        onEvictionRequested?()
        return true
    }

    func didEvictWebView() {
        state = .unloaded
    }
}
