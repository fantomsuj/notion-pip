import SwiftUI

struct NativePagePreviewView: View {
    @ObservedObject var document: NativePageDocument
    let openInNotion: () -> Void

    var body: some View {
        Group {
            if let snapshot = document.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                        Label("Read-only Preview", systemImage: "eye")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignTokens.Colors.secondaryText)

                        Text(snapshot.title)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)

                        ForEach(snapshot.blocks) { block in
                            NativePagePreviewBlock(block: block, openInNotion: openInNotion)
                        }

                        Button("Open in Notion", action: openInNotion)
                            .buttonStyle(.bordered)
                    }
                    .padding(DesignTokens.Spacing.container)
                }
            } else {
                ContentUnavailableView(
                    "Preview unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Open this page in Notion to view or edit it.")
                )
            }
        }
        .background(DesignTokens.Colors.background)
    }
}

private struct NativePagePreviewBlock: View {
    let block: NativePageBlock
    let openInNotion: () -> Void

    var body: some View {
        switch block.kind {
        case .divider:
            Divider()
        case .heading(let level):
            Text(block.text)
                .font(level == 1 ? .title2.weight(.semibold) : .title3.weight(.semibold))
                .textSelection(.enabled)
        case .toDo:
            Label(block.text, systemImage: block.checked ? "checkmark.circle.fill" : "circle")
                .textSelection(.enabled)
        case .bulletedList:
            Text("• \(block.text)")
                .textSelection(.enabled)
        case .numberedList:
            Text("1. \(block.text)")
                .textSelection(.enabled)
        case .quote:
            Text(block.text)
                .padding(.leading, DesignTokens.Spacing.control)
                .overlay(alignment: .leading) { Rectangle().fill(DesignTokens.Colors.border).frame(width: 3) }
                .textSelection(.enabled)
        case .code:
            Text(block.text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(DesignTokens.Spacing.compact)
                .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        case .image, .unsupported:
            Button(action: openInNotion) {
                Label("Open this content in Notion", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        case .paragraph, .toggle:
            Text(block.text)
                .textSelection(.enabled)
        }
    }
}
