import AppKit
import SwiftUI

struct AgentStreamOverlayView: View {
    @ObservedObject var controller: AgentStreamController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        Group {
            switch controller.overlayPresentation {
            case .hidden, .cancelled:
                EmptyView()
            case let .receiving(label, text, contentType, isStreaming):
                card(
                    label: label,
                    text: text,
                    contentType: contentType,
                    stateLabel: isStreaming ? "Streaming" : "Receiving",
                    showsAccept: false,
                    showsStop: true,
                    showsDismiss: false,
                    hint: nil,
                    compactAllowed: false
                )
            case let .ready(label, text, contentType):
                card(
                    label: label,
                    text: text,
                    contentType: contentType,
                    stateLabel: AgentStreamUserFacingCopy.readyTitle,
                    showsAccept: true,
                    showsStop: false,
                    showsDismiss: true,
                    hint: AgentStreamUserFacingCopy.clickFirstHint,
                    compactAllowed: true
                )
            case let .inserting(label, text, contentType):
                card(
                    label: label,
                    text: text,
                    contentType: contentType,
                    stateLabel: "Pasting into Notion…",
                    showsAccept: false,
                    showsStop: false,
                    showsDismiss: false,
                    hint: nil,
                    compactAllowed: false
                )
            case let .success(label):
                card(
                    label: label,
                    text: "",
                    contentType: .markdown,
                    stateLabel: AgentStreamUserFacingCopy.addedReceipt,
                    showsAccept: false,
                    showsStop: false,
                    showsDismiss: false,
                    hint: nil,
                    showsOutput: false,
                    compactAllowed: false
                )
            case let .failed(label, text, contentType, message):
                card(
                    label: label,
                    text: text,
                    contentType: contentType,
                    stateLabel: AgentStreamUserFacingCopy.failedTitle,
                    showsAccept: true,
                    showsStop: false,
                    showsDismiss: true,
                    hint: message ?? AgentStreamUserFacingCopy.clickFirstHint,
                    compactAllowed: true
                )
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: presentationIdentity
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: isExpanded
        )
        .onChange(of: presentationIdentity) { _, _ in
            isExpanded = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AgentStreamAccessibilityLabels.card)
    }

    private var presentationIdentity: String {
        switch controller.overlayPresentation {
        case .hidden: "hidden"
        case .cancelled: "cancelled"
        case .receiving: "receiving"
        case .ready: "ready"
        case .inserting: "inserting"
        case .success: "success"
        case .failed: "failed"
        }
    }

    @ViewBuilder
    private func card(
        label: String,
        text: String,
        contentType: AgentStreamContentType,
        stateLabel: String,
        showsAccept: Bool,
        showsStop: Bool,
        showsDismiss: Bool,
        hint: String?,
        showsOutput: Bool = true,
        compactAllowed: Bool
    ) -> some View {
        let showsCompact = compactAllowed && !isExpanded

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.control) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.control) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateLabel)
                        .font(showsCompact ? .subheadline.weight(.semibold) : .caption)
                        .foregroundStyle(
                            showsCompact
                                ? DesignTokens.Colors.primaryText
                                : DesignTokens.Colors.secondaryText
                        )
                        .accessibilityLabel(AgentStreamAccessibilityLabels.state)
                        .accessibilityValue(stateLabel)
                    if showsCompact {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .lineLimit(1)
                            .accessibilityLabel(AgentStreamAccessibilityLabels.agentLabel)
                            .accessibilityValue(label)
                    } else {
                        Text(label)
                            .font(.headline)
                            .lineLimit(1)
                            .accessibilityLabel(AgentStreamAccessibilityLabels.agentLabel)
                            .accessibilityValue(label)
                    }
                }
                Spacer(minLength: DesignTokens.Spacing.compact)
                if showsAccept {
                    Button(AgentStreamUserFacingCopy.acceptButton) {
                        controller.accept()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel(AgentStreamAccessibilityLabels.accept)
                    .keyboardShortcut(.defaultAction)
                }
                if compactAllowed {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(
                        isExpanded
                            ? AgentStreamAccessibilityLabels.collapseDetails
                            : AgentStreamAccessibilityLabels.expandDetails
                    )
                }
            }

            if !showsCompact {
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsOutput {
                    AgentStreamMarkdownOutput(text: text, contentType: contentType)
                        .frame(maxHeight: 220, alignment: .topLeading)
                        .accessibilityLabel(AgentStreamAccessibilityLabels.output)
                }

                HStack(spacing: DesignTokens.Spacing.control) {
                    if showsStop {
                        Button(AgentStreamUserFacingCopy.stopButton) {
                            controller.stopFromOverlay()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel(AgentStreamAccessibilityLabels.stop)
                    }
                    Button(AgentStreamUserFacingCopy.copyButton) {
                        controller.copyAssembledTextToPasteboard()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(text.isEmpty)
                    .accessibilityLabel(AgentStreamAccessibilityLabels.copy)
                    if showsDismiss {
                        Button(AgentStreamUserFacingCopy.dismissButton) {
                            controller.dismissFromOverlay()
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .accessibilityLabel(AgentStreamAccessibilityLabels.dismiss)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.section)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.border.opacity(0.7), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        .padding(DesignTokens.Spacing.container)
        .transition(.opacity)
    }
}

struct AgentStreamMarkdownOutput: View {
    let text: String
    let contentType: AgentStreamContentType

    var body: some View {
        ScrollView {
            Text(markdownText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusable(false)
    }

    private var markdownText: AttributedString {
        guard contentType == .markdown, !text.isEmpty else {
            return AttributedString(text)
        }
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(text)
        }
    }
}
