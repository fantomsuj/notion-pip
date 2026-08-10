import SwiftUI

struct PageSwitcherView: View {
    @ObservedObject var controller: PageSwitcherController
    let onDismiss: () -> Void
    let onSelect: (PageSwitcherSelection) -> Void
    @FocusState private var searchIsFocused: Bool
    @State private var editingPageID: String?
    @State private var roleDraft = ""

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
                                    VStack(spacing: 2) {
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
                                            },
                                            onEditRole: { beginRoleEditing(item) }
                                        )

                                        if editingPageID == item.page.pageID {
                                            PageRoleEditor(
                                                pageTitle: item.page.displayTitle,
                                                existingRole: item.page.role,
                                                draft: $roleDraft,
                                                onSave: { saveRole(for: item.page.pageID) },
                                                onClear: { clearRole(for: item.page.pageID) },
                                                onCancel: cancelRoleEditing
                                            )
                                        }
                                    }
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
            guard editingPageID == nil else { return .ignored }
            controller.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard editingPageID == nil else { return .ignored }
            controller.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard editingPageID == nil else { return .ignored }
            selectCurrent()
            return .handled
        }
        .onKeyPress(.escape) {
            if editingPageID != nil {
                cancelRoleEditing()
                return .handled
            }
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

    private func beginRoleEditing(_ item: PageSwitcherItem) {
        guard item.isPinned else { return }
        controller.select(pageID: item.page.pageID)
        roleDraft = item.page.role ?? ""
        editingPageID = item.page.pageID
        searchIsFocused = false
    }

    private func saveRole(for pageID: String) {
        Task {
            guard await controller.updateRole(roleDraft, pageID: pageID) else { return }
            finishRoleEditing()
        }
    }

    private func clearRole(for pageID: String) {
        Task {
            guard await controller.updateRole(nil, pageID: pageID) else { return }
            finishRoleEditing()
        }
    }

    private func cancelRoleEditing() {
        finishRoleEditing()
    }

    private func finishRoleEditing() {
        editingPageID = nil
        roleDraft = ""
        searchIsFocused = true
    }
}

struct PageSwitcherRow: View {
    let item: PageSwitcherItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onEditRole: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.control) {
            Image(systemName: item.isActive ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(item.isActive ? DesignTokens.Colors.action : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.page.role ?? PageSwitcherAccessibility.pageTitle(for: item))
                    .fontWeight(item.page.role == nil ? .regular : .semibold)
                    .lineLimit(1)
                Text(secondaryText)
                    .font(item.page.role == nil ? .caption2.monospaced() : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.compact)

            if isHovering || isSelected {
                if item.isPinned {
                    Button(action: onEditRole) {
                        Image(systemName: item.page.role == nil ? "tag" : "pencil")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(PageSwitcherAccessibility.roleActionLabel(for: item))
                }

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
        .accessibilityLabel(PageSwitcherAccessibility.rowLabel(for: item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: item.isPinned ? "Unpin page" : "Pin page", onTogglePin)
        .pageRoleAccessibilityAction(item: item, action: onEditRole)
        .accessibilityAction(.default, onSelect)
    }

    private var secondaryText: String {
        item.page.role == nil
            ? item.page.pageID
            : PageSwitcherAccessibility.pageTitle(for: item)
    }
}

private struct PageRoleEditor: View {
    let pageTitle: String?
    let existingRole: String?
    @Binding var draft: String
    let onSave: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            TextField("Role, such as Today", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(onSave)
                .accessibilityLabel(
                    "Role for \(pageTitle ?? "untitled Notion page"), up to 32 characters"
                )

            HStack(spacing: DesignTokens.Spacing.control) {
                Text("Up to \(PinnedPageRole.maximumLength) characters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if existingRole != nil {
                    Button("Clear", action: onClear)
                        .accessibilityLabel(
                            PageSwitcherAccessibility.clearRoleLabel(
                                role: existingRole,
                                pageTitle: pageTitle
                            )
                        )
                }
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, DesignTokens.Spacing.section)
        .padding(.bottom, DesignTokens.Spacing.control)
        .onAppear { isFocused = true }
    }
}

enum PageSwitcherAccessibility {
    static func pageTitle(for item: PageSwitcherItem) -> String {
        item.page.displayTitle ?? "Untitled Notion page"
    }

    static func rowLabel(for item: PageSwitcherItem) -> String {
        [
            item.page.role.map { "Role \($0)" },
            item.page.role == nil
                ? pageTitle(for: item)
                : "Notion page \(pageTitle(for: item))",
            item.isActive ? "Active page" : nil,
            item.isPinned ? "Pinned" : "Recent",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func roleActionLabel(for item: PageSwitcherItem) -> String {
        let title = pageTitle(for: item)
        if let role = item.page.role {
            return "Edit role \(role) for \(title)"
        }
        return "Add role for \(title)"
    }

    static func clearRoleLabel(role: String?, pageTitle: String?) -> String {
        let title = pageTitle ?? "Untitled Notion page"
        guard let role, !role.isEmpty else { return "Clear role from \(title)" }
        return "Clear role \(role) from \(title)"
    }
}

private extension View {
    @ViewBuilder
    func pageRoleAccessibilityAction(
        item: PageSwitcherItem,
        action: @escaping () -> Void
    ) -> some View {
        if item.isPinned {
            accessibilityAction(
                named: PageSwitcherAccessibility.roleActionLabel(for: item),
                action
            )
        } else {
            self
        }
    }
}
