import SwiftUI

/// Brief confirmation at the bottom of the panel after Copy for Agent.
struct AgentPageCopyFeedbackView: View {
    let feedback: AgentPageCopyFeedback

    var symbolName: String {
        feedback.isError ? "exclamationmark.circle" : "doc.on.clipboard"
    }

    var body: some View {
        Label(feedback.message, systemImage: symbolName)
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, DesignTokens.Spacing.section)
            .padding(.vertical, DesignTokens.Spacing.control)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
    }
}
