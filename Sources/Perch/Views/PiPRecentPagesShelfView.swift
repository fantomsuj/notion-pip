import SwiftUI

enum PiPRecentPagesShelfAccessibility {
    static func rowLabel(title: String, recency: String, isCurrent: Bool) -> String {
        if isCurrent {
            return "\(title), \(recency), active Perch page"
        }
        return "\(title), \(recency)"
    }

    static func rowHint(isCurrent: Bool) -> String {
        isCurrent
            ? "Restore the current Perch page without reloading"
            : "Restore this recent page in Perch"
    }
}

struct PiPRecentPagesShelfView: View {
    @ObservedObject var controller: PiPRecentPagesShelfController
    let onSelect: (String) -> Void
    let onHoverChanged: (Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent in PiP")
                .font(.headline)
                .frame(height: PanelStashShelfPolicy.headerHeight)
                .padding(.horizontal, DesignTokens.Spacing.container)
                .accessibilityAddTraits(.isHeader)

            ForEach(controller.items) { item in
                PiPRecentPageShelfRow(item: item) {
                    onSelect(item.id)
                }
            }
        }
        .padding(.vertical, PanelStashShelfPolicy.verticalPadding)
        .frame(width: PanelStashShelfPolicy.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                .stroke(DesignTokens.Colors.border.opacity(0.55), lineWidth: 0.5)
        }
        .onHover(perform: onHoverChanged)
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent in PiP")
    }
}

private struct PiPRecentPageShelfRow: View {
    let item: PiPRecentPageShelfItem
    let action: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var isHovering = false

    private var title: String {
        let value = item.page.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Notion page"
    }

    private var recencyLabel: String {
        item.recency.label(locale: locale, calendar: calendar)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.control) {
                Image(systemName: "doc.text")
                    .foregroundStyle(item.isCurrent ? DesignTokens.Colors.action : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(recencyLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: DesignTokens.Spacing.compact)

                if item.isCurrent {
                    Circle()
                        .fill(DesignTokens.Colors.action)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }

                Image(systemName: "arrow.turn.down.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DesignTokens.Spacing.container)
            .frame(maxWidth: .infinity, minHeight: PanelStashShelfPolicy.rowHeight)
            .background(item.isCurrent ? DesignTokens.Colors.action.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            PiPRecentPagesShelfAccessibility.rowLabel(
                title: title,
                recency: recencyLabel,
                isCurrent: item.isCurrent
            )
        )
        .accessibilityHint(
            PiPRecentPagesShelfAccessibility.rowHint(isCurrent: item.isCurrent)
        )
        .accessibilityAddTraits(item.isCurrent ? .isSelected : [])
    }
}
