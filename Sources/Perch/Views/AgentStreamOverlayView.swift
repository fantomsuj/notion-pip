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

    /// Keeps parsed blocks between renders so a growing stream only re-parses its tail.
    @State private var renderer = AgentStreamMarkdownRenderer()
    @State private var autoScroll = AgentStreamAutoScroll()
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    let blocks = renderer.blocks(for: text, contentType: contentType)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        AgentStreamMarkdownBlockView(block: block)
                    }
                    Color.clear
                        .frame(height: 0)
                        .id(AgentStreamOutputLayout.bottomAnchorID)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .named(AgentStreamOutputLayout.coordinateSpace))
                } action: { frame in
                    let jumpsToBottom = autoScroll.update(
                        contentMinY: frame.minY,
                        contentHeight: frame.height,
                        viewportHeight: viewportHeight
                    )
                    if jumpsToBottom {
                        proxy.scrollTo(AgentStreamOutputLayout.bottomAnchorID, anchor: .bottom)
                    }
                }
            }
            .coordinateSpace(.named(AgentStreamOutputLayout.coordinateSpace))
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                viewportHeight = height
            }
        }
        .focusable(false)
    }
}

/// Not inside the view so the geometry closures, which aren't main-actor isolated, can
/// read them.
private enum AgentStreamOutputLayout {
    static let bottomAnchorID = "agent-stream-output-bottom"
    static let coordinateSpace = "agent-stream-output"
}

/// One rendered block of the stream preview.
struct AgentStreamMarkdownBlockView: View {
    let block: AgentStreamMarkdownBlock

    var body: some View {
        switch block.kind {
        case .paragraph:
            Text(block.content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case let .heading(level):
            Text(block.content)
                .font(Self.headingFont(level: level))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case let .listItem(marker, indentLevel):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityHidden(marker == "•")
                Text(block.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indentLevel) * 14)
        case .quote:
            Text(block.content)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 11)
                .overlay(alignment: .leading) {
                    // Sized by the overlay, so the bar is exactly as tall as the quote.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(DesignTokens.Colors.border)
                        .frame(width: 3)
                }
        case .code:
            Text(block.content)
                .font(.callout.monospaced())
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    DesignTokens.Colors.border.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 4)
                )
        case .divider:
            Divider()
        }
    }

    static func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.semibold)
        case 2: .headline
        default: .subheadline.weight(.semibold)
        }
    }
}
