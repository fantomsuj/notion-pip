import AppKit
import Combine
import QuartzCore

enum StatusMenuContextCommand: Int, Equatable, Sendable {
    case stash = -1
    case show = -2
    case openSettings = -3

    var menuItemTag: Int {
        rawValue
    }

    init?(menuItemTag: Int) {
        self.init(rawValue: menuItemTag)
    }

    init(presentationState: PiPPresentationState) {
        switch presentationState {
        case .unavailable:
            self = .openSettings
        case .visible:
            self = .stash
        case .stashed:
            self = .show
        }
    }

    var title: String {
        switch self {
        case .stash:
            "Stash Perch"
        case .show:
            "Show Perch"
        case .openSettings:
            "Open Settings…"
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let runtime: AppRuntime
    private let commandModel: AppCommandModel
    private let panelSizeController: PanelSizeController?
    private let reducesMotion: @MainActor () -> Bool
    private var cancellables = Set<AnyCancellable>()
    private var currentGlyph: StatusItemGlyph?
    private var isHovered = false
    private var isNodding = false
    private var lastSummonGeneration: UInt = 0
    private var nodRestoreTask: Task<Void, Never>?
    private var hoverTrackingArea: NSTrackingArea?

    private lazy var eventRouter = StatusItemEventRouter(
        holdDuration: runtime.shortcutHoldDuration,
        scheduler: runtime.shortcutGestureScheduler,
        onMenu: { [weak self] in
            self?.showCommandMenu()
        },
        onBeginPeek: { [weak self] in
            self?.runtime.beginStatusItemPeek() ?? false
        },
        onCommitPeek: { [weak self] in
            self?.runtime.commitStatusItemPeek()
        },
        onCancelPeek: { [weak self] in
            self?.runtime.cancelStatusItemPeek()
        }
    )

    init(
        runtime: AppRuntime,
        commandModel: AppCommandModel,
        panelSizeController: PanelSizeController? = nil,
        statusBar: NSStatusBar = .system,
        reducesMotion: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.runtime = runtime
        self.commandModel = commandModel
        self.panelSizeController = panelSizeController
        self.reducesMotion = reducesMotion
        super.init()

        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "Perch"
        button.setAccessibilityHelp(
            "Open commands for the current Notion page and app. Press and hold to peek the panel."
        )
        button.target = self
        button.action = #selector(handleStatusItemAction(_:))
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
        let hoverTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(hoverTrackingArea)
        self.hoverTrackingArea = hoverTrackingArea

        applyGlyph(runtime.statusItemGlyph, animated: false)
        lastSummonGeneration = runtime.statusItemSummonGeneration
        statusItem.isVisible = runtime.effectiveMenuBarIconVisibility

        runtime.$effectiveMenuBarIconVisibility
            .removeDuplicates()
            .sink { [weak statusItem] isVisible in
                statusItem?.isVisible = isVisible
            }
            .store(in: &cancellables)
        runtime.$statusItemGlyph
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] glyph in
                self?.applyGlyph(glyph, animated: true)
            }
            .store(in: &cancellables)
        runtime.$statusItemSummonGeneration
            .sink { [weak self] generation in
                self?.handleSummon(generation)
            }
            .store(in: &cancellables)
    }

    isolated deinit {
        nodRestoreTask?.cancel()
        if let button = statusItem.button, let hoverTrackingArea {
            button.removeTrackingArea(hoverTrackingArea)
        }
    }

    @objc
    func mouseEntered(with event: NSEvent) {
        guard let button = statusItem.button else { return }
        isHovered = true
        if renderImage(on: button).separation > 0 {
            playMorphPulse(on: button)
        }
    }

    @objc
    func mouseExited(with event: NSEvent) {
        guard let button = statusItem.button else { return }
        isHovered = false
        renderImage(on: button)
    }

    @objc
    private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let location = sender.convert(event.locationInWindow, from: nil)
        eventRouter.handle(
            eventType: event.type,
            isPointerInside: sender.bounds.contains(location)
        )
    }

    private func handleSummon(_ generation: UInt) {
        guard generation != lastSummonGeneration else { return }
        lastSummonGeneration = generation
        playSummonNod()
    }

    private func applyGlyph(_ glyph: StatusItemGlyph, animated: Bool) {
        guard let button = statusItem.button else { return }
        currentGlyph = glyph
        renderImage(on: button)
        button.setAccessibilityLabel(glyph.accessibilityLabel)
        guard animated, StatusItemMotionPolicy.shouldAnimate(reducesMotion: reducesMotion()) else {
            return
        }
        playMorphPulse(on: button)
    }

    private func playSummonNod() {
        guard let button = statusItem.button, currentGlyph != nil else { return }
        nodRestoreTask?.cancel()
        isNodding = true
        guard renderImage(on: button).verticalOffset != 0 else {
            isNodding = false
            return
        }
        nodRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(StatusItemMotionPolicy.nodDuration))
            guard let self, !Task.isCancelled else { return }
            self.isNodding = false
            self.renderImage(on: button)
        }
    }

    @discardableResult
    private func renderImage(
        on button: NSStatusBarButton
    ) -> (separation: CGFloat, verticalOffset: CGFloat) {
        guard let currentGlyph else { return (0, 0) }
        let shouldReduceMotion = reducesMotion()
        let separation = isHovered
            ? StatusItemMotionPolicy.hoverSeparation(reducesMotion: shouldReduceMotion)
            : 0
        let verticalOffset = isNodding
            ? StatusItemMotionPolicy.nodOffset(reducesMotion: shouldReduceMotion)
            : 0
        button.image = StatusItemGlyphPolicy.makeImage(
            for: currentGlyph,
            separation: separation,
            verticalOffset: verticalOffset
        )
        return (separation, verticalOffset)
    }

    private func playMorphPulse(on button: NSStatusBarButton) {
        button.wantsLayer = true
        let layer = button.layer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.transform = CATransform3DMakeScale(StatusItemMotionPolicy.morphScale, StatusItemMotionPolicy.morphScale, 1)
        CATransaction.commit()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = StatusItemMotionPolicy.morphDuration
            context.allowsImplicitAnimation = true
            layer?.transform = CATransform3DIdentity
        }
    }

    private func showCommandMenu() {
        guard let button = statusItem.button else { return }
        let menu = AppKitCommandMenuFactory.makeStatusItemMenu(
            commandModel: commandModel,
            contextualCommand: runtime.statusMenuContextCommand,
            panelSizeController: panelSizeController
        )
        configureActions(in: menu)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.minX, y: button.bounds.minY),
            in: button
        )
    }

    @objc
    private func performCommand(_ sender: NSMenuItem) {
        guard let id = AppCommandID(rawValue: sender.tag) else { return }
        commandModel.perform(id)
    }

    private func configureActions(in menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            if let submenu = item.submenu {
                configurePanelSizeActions(in: submenu)
            } else if item.representedObject as? String
                == AppKitCommandMenuFactory.managePanelSizesMarker
            {
                item.target = self
                item.action = #selector(managePanelSizes(_:))
            } else if StatusMenuContextCommand(menuItemTag: item.tag) != nil {
                item.target = self
                item.action = #selector(performContextualCommand(_:))
            } else if AppCommandID(rawValue: item.tag) != nil {
                item.target = self
                item.action = #selector(performCommand(_:))
            }
        }
    }

    private func configurePanelSizeActions(in menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            item.target = self
            switch item.representedObject as? String {
            case AppKitCommandMenuFactory.resetPanelSizeMarker:
                item.action = #selector(resetPanelSize(_:))
            case AppKitCommandMenuFactory.managePanelSizesMarker:
                item.action = #selector(managePanelSizes(_:))
            case .some:
                item.action = #selector(applyPanelSizePreset(_:))
            case nil:
                item.target = nil
            }
        }
    }

    @objc
    private func applyPanelSizePreset(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
            let id = PanelSizePresetID(rawValue: rawID)
        else {
            return
        }
        panelSizeController?.apply(id)
    }

    @objc
    private func resetPanelSize(_ sender: NSMenuItem) {
        panelSizeController?.resetToDefault()
    }

    @objc
    private func managePanelSizes(_ sender: NSMenuItem) {
        panelSizeController?.managePanelSizes()
    }

    @objc
    private func performContextualCommand(_ sender: NSMenuItem) {
        guard let command = StatusMenuContextCommand(menuItemTag: sender.tag) else { return }
        runtime.performStatusMenuContextCommand(command)
    }
}
