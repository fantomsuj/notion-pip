import Combine

@MainActor
protocol PanelPositioning: AnyObject {
    var canPositionPanel: Bool { get }
    var selectedCorner: PanelCorner? { get }
    var onPanelPositionChange: (@MainActor () -> Void)? { get set }

    @discardableResult
    func movePanel(to corner: PanelCorner) -> Bool
}

@MainActor
final class PanelPositionController: ObservableObject {
    @Published private(set) var selectedCorner: PanelCorner?
    @Published private(set) var canPosition = false

    private weak var target: (any PanelPositioning)?

    func bind(to target: any PanelPositioning) {
        self.target = target
        target.onPanelPositionChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    @discardableResult
    func move(to corner: PanelCorner) -> Bool {
        guard canPosition, target?.movePanel(to: corner) == true else {
            return false
        }
        refresh()
        return true
    }

    func refresh() {
        // Panel moves call this on every drag event; only publish real
        // changes so SwiftUI isn't invalidated 60-120 times a second.
        let canPosition = target?.canPositionPanel == true
        if self.canPosition != canPosition {
            self.canPosition = canPosition
        }
        let selectedCorner = target?.selectedCorner
        if self.selectedCorner != selectedCorner {
            self.selectedCorner = selectedCorner
        }
    }
}
