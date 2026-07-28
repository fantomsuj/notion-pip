import Foundation

@MainActor
final class TopControlsHoverController: ObservableObject {
    @Published private(set) var isHovering = false

    private let revealDelay: Duration
    private let dismissalDelay: Duration
    private var revealTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?

    init(
        revealDelay: Duration = .milliseconds(250),
        dismissalDelay: Duration = .milliseconds(500)
    ) {
        self.revealDelay = revealDelay
        self.dismissalDelay = dismissalDelay
    }

    func setHovering(_ isHovering: Bool) {
        if isHovering {
            dismissalTask?.cancel()
            dismissalTask = nil

            guard !self.isHovering else { return }

            revealTask?.cancel()
            revealTask = Task { @MainActor [weak self, revealDelay] in
                do {
                    try await Task.sleep(for: revealDelay)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                self?.isHovering = true
            }
            return
        }

        revealTask?.cancel()
        revealTask = nil

        guard self.isHovering else { return }

        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor [weak self, dismissalDelay] in
            do {
                try await Task.sleep(for: dismissalDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.isHovering = false
        }
    }

    func cancel() {
        revealTask?.cancel()
        revealTask = nil
        dismissalTask?.cancel()
        dismissalTask = nil
        isHovering = false
    }
}
