import AppKit
import Combine
import SwiftUI

@MainActor
final class ContextSuggestionPanelController {
    private static let cardSize = CGSize(width: 320, height: 112)
    private static let screenInset: CGFloat = 16

    private let controller: ContextSuggestionController
    private let panel: NSPanel
    private let screenProvider: @MainActor () -> NSScreen?
    private var suggestionCancellable: AnyCancellable?

    init(
        controller: ContextSuggestionController,
        panel: NSPanel? = nil,
        screenProvider: @escaping @MainActor () -> NSScreen? = {
            NSScreen.main ?? NSScreen.screens.first
        }
    ) {
        self.controller = controller
        self.screenProvider = screenProvider
        if let panel {
            self.panel = panel
        } else {
            guard let panel = WindowRole.contextSuggestion.makeWindow() as? NSPanel else {
                preconditionFailure("Context suggestion role must create NSPanel")
            }
            self.panel = panel
        }
        configurePanel()
        suggestionCancellable = controller.$suggestion.sink { [weak self] suggestion in
            Task { @MainActor in
                guard let self else { return }
                if let suggestion {
                    self.present(suggestion)
                } else {
                    self.panel.orderOut(nil)
                }
            }
        }
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.ignoresMouseEvents = false
    }

    private func present(_ suggestion: ContextSuggestion) {
        let presentation = ContextSuggestionCardPresentation(
            applicationName: suggestion.sourceApplicationName,
            sourceDescription: suggestion.sourceDescription,
            pageLabel: suggestion.label
        )
        panel.contentView = NSHostingView(
            rootView: ContextSuggestionCard(
                presentation: presentation,
                onOpen: { [weak controller] in controller?.acceptSuggestion() },
                onDismiss: { [weak controller] in controller?.dismissSuggestion() }
            )
        )
        if let screen = screenProvider() {
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.maxX - Self.cardSize.width - Self.screenInset,
                y: visible.maxY - Self.cardSize.height - Self.screenInset
            )
            panel.setFrame(CGRect(origin: origin, size: Self.cardSize), display: false)
        }
        panel.orderFrontRegardless()
    }
}
