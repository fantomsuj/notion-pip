import SwiftUI

struct ContextSuggestionCardPresentation: Equatable, Sendable {
    let source: String
    let title: String
    let accessibilityLabel: String

    init(
        applicationName: String,
        sourceDescription: String?,
        pageLabel: String
    ) {
        if let sourceDescription, !sourceDescription.isEmpty {
            source = "\(applicationName) · \(sourceDescription)"
            accessibilityLabel = "Perch suggests opening \(pageLabel) for \(applicationName), \(sourceDescription)"
        } else {
            source = applicationName
            accessibilityLabel = "Perch suggests opening \(pageLabel) for \(applicationName)"
        }
        title = "Open \(pageLabel)?"
    }
}

struct ContextSuggestionCard: View {
    let presentation: ContextSuggestionCardPresentation
    let onOpen: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.control) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(presentation.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.compact)

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss page suggestion")
            Button("Open", action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(presentation.title)
        }
        .padding(DesignTokens.Spacing.control)
        .frame(width: 320, height: 112)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.border.opacity(0.7), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
