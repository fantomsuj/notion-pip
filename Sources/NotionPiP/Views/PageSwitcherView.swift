import SwiftUI

struct PageSwitcherView: View {
    @ObservedObject var controller: PageSwitcherController
    let onDismiss: () -> Void
    let onSelect: (PageSwitcherSelection) -> Void
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search pages", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .padding(DesignTokens.Spacing.control)
                .accessibilityLabel("Search pinned and recent Notion pages")

            Divider()

            if controller.sections.isEmpty {
                ContentUnavailableView(
                    "No matching pages",
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(controller.sections) { section in
                                Text(section.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, DesignTokens.Spacing.section)
                                    .padding(.top, DesignTokens.Spacing.control)
                                    .accessibilityAddTraits(.isHeader)

                                ForEach(section.items) { item in
                                    PageSwitcherRow(
                                        item: item,
                                        isSelected: controller.selectedPageID == item.page.pageID,
                                        onSelect: { select(item) },
                                        onTogglePin: {
                                            Task {
                                                await controller.setPinned(
                                                    !item.isPinned,
                                                    pageID: item.page.pageID
                                                )
                                            }
                                        }
                                    )
                                    .id(item.page.pageID)
                                }
                            }
                        }
                        .padding(.bottom, DesignTokens.Spacing.control)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: controller.selectedPageID) { _, pageID in
                        guard let pageID else { return }
                        proxy.scrollTo(pageID, anchor: .center)
                    }
                }
            }

            if let feedback = controller.inlineFeedback {
                Divider()
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.control)
                    .accessibilityLabel(feedback)
            }
        }
        .frame(width: 320)
        .task {
            await controller.load()
            searchIsFocused = true
        }
        .onKeyPress(.downArrow) {
            controller.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            controller.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            selectCurrent()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func select(_ item: PageSwitcherItem) {
        controller.select(pageID: item.page.pageID)
        selectCurrent()
    }

    private func selectCurrent() {
        guard let selection = controller.selectCurrent() else { return }
        switch selection {
        case .dismiss:
            onDismiss()
        case .activate:
            onSelect(selection)
        }
    }
}

private struct PageSwitcherRow: View {
    let item: PageSwitcherItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.control) {
            Image(systemName: item.isActive ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(item.isActive ? DesignTokens.Colors.action : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.page.displayTitle ?? "Untitled Notion page")
                    .lineLimit(1)
                Text(item.page.pageID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.compact)

            if isHovering || isSelected {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isPinned ? "Unpin page" : "Pin page")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.section)
        .padding(.vertical, 6)
        .background(
            isSelected ? DesignTokens.Colors.action.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: item.isPinned ? "Unpin page" : "Pin page", onTogglePin)
        .accessibilityAction(.default, onSelect)
    }

    private var accessibilityLabel: String {
        [
            item.page.displayTitle ?? "Untitled Notion page",
            item.isActive ? "Active page" : nil,
            item.isPinned ? "Pinned" : "Recent",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
