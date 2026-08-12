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
        canPosition = target?.canPositionPanel == true
        selectedCorner = target?.selectedCorner
    }
}
