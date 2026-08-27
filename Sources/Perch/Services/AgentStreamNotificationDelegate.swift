import Foundation
import UserNotifications

/// Routes notification Accept/Dismiss actions to the shared stream controller.
///
/// `UNUserNotificationCenterDelegate` methods are called off the main actor.
/// Actions hop to the main actor and only affect the stream matching the
/// notification's `streamID`.
@MainActor
final class AgentStreamNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var controller: AgentStreamController?

    init(controller: AgentStreamController) {
        self.controller = controller
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let streamIDString = (userInfo["streamID"] as? String)
            ?? response.notification.request.identifier
        let streamID = UUID(uuidString: streamIDString)
        completionHandler()
        Task { @MainActor in
            guard let streamID else { return }
            switch actionIdentifier {
            case AgentStreamUserNotifier.acceptActionIdentifier,
                UNNotificationDefaultActionIdentifier:
                controller?.accept(streamID: streamID)
            case AgentStreamUserNotifier.dismissActionIdentifier:
                controller?.dismissFromOverlay(streamID: streamID)
            default:
                break
            }
        }
    }
}
