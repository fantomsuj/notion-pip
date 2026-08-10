import Combine
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case unregistered
    case registered
    case requiresApproval
    case unavailable

    var isRegistered: Bool {
        switch self {
        case .registered, .requiresApproval:
            true
        case .unregistered, .unavailable:
            false
        }
    }
}

@MainActor
protocol LaunchAtLoginRegistering: AnyObject {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState
    @Published private(set) var failureMessage: String?

    private let registration: any LaunchAtLoginRegistering

    init(
        registration: any LaunchAtLoginRegistering = SystemLaunchAtLoginRegistration()
    ) {
        self.registration = registration
        state = Self.state(for: registration.status)
    }

    var isRegistered: Bool {
        state.isRegistered
    }

    func setEnabled(_ enabled: Bool) {
        state = Self.state(for: registration.status)
        failureMessage = nil
        guard state.isRegistered != enabled else { return }

        do {
            if enabled {
                try registration.register()
            } else {
                try registration.unregister()
            }
        } catch {
            state = Self.state(for: registration.status)
            let action = enabled ? "enable" : "disable"
            failureMessage = "Could not \(action) Launch at Login. \(error.localizedDescription)"
            return
        }

        state = Self.state(for: registration.status)
    }

    func refresh() {
        state = Self.state(for: registration.status)
        failureMessage = nil
    }

    func openSystemSettings() {
        registration.openSystemSettingsLoginItems()
    }

    static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered:
            .unregistered
        case .enabled:
            .registered
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}

@MainActor
final class SystemLaunchAtLoginRegistration: LaunchAtLoginRegistering {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
