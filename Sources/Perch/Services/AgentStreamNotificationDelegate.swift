import Foundation
import UserNotifications

/// Routes notification Accept/Dismiss actions to the shared stream controller.
///
/// `UNUserNotificationCenterDelegate` methods are called off the main actor.
/// The controller reference is only used after hopping to the main queue.
final class AgentStreamNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) private weak var controller: AgentStreamController?

    init(controller: AgentStreamController) {
        self.controller = controller
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let controller = controller
        completionHandler()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch actionIdentifier {
                case AgentStreamUserNotifier.acceptActionIdentifier,
                    UNNotificationDefaultActionIdentifier:
                    controller?.accept()
                case AgentStreamUserNotifier.dismissActionIdentifier:
                    controller?.dismissFromOverlay()
                default:
                    break
                }
            }
        }
    }
}
