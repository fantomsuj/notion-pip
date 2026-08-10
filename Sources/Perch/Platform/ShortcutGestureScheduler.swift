import AppKit
import Foundation

@MainActor
protocol ShortcutGestureTimer: AnyObject {
    func cancel()
}

@MainActor
protocol ShortcutGestureScheduling: AnyObject {
    func schedule(
        after duration: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any ShortcutGestureTimer
}

@MainActor
final class TaskShortcutGestureScheduler: ShortcutGestureScheduling {
    func schedule(
        after duration: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any ShortcutGestureTimer {
        ShortcutGestureTaskTimer(
            task: Task {
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return
                }
                action()
            }
        )
    }
}

@MainActor
private final class ShortcutGestureTaskTimer: ShortcutGestureTimer {
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
protocol AccessibilityAnnouncementPosting: AnyObject {
    func announce(_ message: String)
}

@MainActor
final class AppAccessibilityAnnouncementPoster: AccessibilityAnnouncementPosting {
    func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority:
                    NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}
