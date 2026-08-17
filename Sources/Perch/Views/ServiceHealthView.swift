import SwiftUI

struct ServiceHealthView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        ForEach(runtime.serviceHealth.issues) { issue in
            HStack(alignment: .top, spacing: DesignTokens.Spacing.control) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.error)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    Text(issue.title)
                        .font(.callout.weight(.semibold))
                    Text(issue.recoveryMessage)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(issue.recoveryTitle) {
                        runtime.retryRecovery(for: issue)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

private extension ServiceHealthIssue {
    var title: String {
        switch self {
        case .persistentStoreUnavailable:
            "Local storage is unavailable"
        case .pinnedPagePersistenceUnavailable:
            "Current page is not being saved"
        case .globalShortcutUnavailable:
            "Global shortcut is unavailable"
        }
    }

    var recoveryMessage: String {
        switch self {
        case .persistentStoreUnavailable:
            "Local page history is not being saved. Review the preserved store and recovery options."
        case .pinnedPagePersistenceUnavailable:
            "Your current page works for this session. Retry saving it locally."
        case .globalShortcutUnavailable:
            "Use the menu-bar icon for now, or retry shortcut registration."
        }
    }

    var recoveryTitle: String {
        switch self {
        case .persistentStoreUnavailable:
            "Review Recovery Options"
        case .pinnedPagePersistenceUnavailable,
             .globalShortcutUnavailable:
            "Retry"
        }
    }
}
