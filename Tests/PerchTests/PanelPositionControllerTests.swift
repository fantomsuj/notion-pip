import Combine
import XCTest

@testable import Perch

@MainActor
final class PanelPositionControllerTests: XCTestCase {
    func testBindingPublishesAvailabilityAndSelectedCorner() {
        let target = PanelPositioningSpy(
            canPositionPanel: true,
            selectedCorner: .topRight
        )
        let controller = PanelPositionController()

        controller.bind(to: target)

        XCTAssertTrue(controller.canPosition)
        XCTAssertEqual(controller.selectedCorner, .topRight)
    }

    func testMoveRoutesOneActionAndRefreshesSelectedCorner() {
        let target = PanelPositioningSpy(
            canPositionPanel: true,
            selectedCorner: .topRight
        )
        let controller = PanelPositionController()
        controller.bind(to: target)

        XCTAssertTrue(controller.move(to: .bottomLeft))

        XCTAssertEqual(target.moves, [.bottomLeft])
        XCTAssertEqual(controller.selectedCorner, .bottomLeft)
    }

    func testTargetChangeClearsSelectedCorner() {
        let target = PanelPositioningSpy(
            canPositionPanel: true,
            selectedCorner: .topRight
        )
        let controller = PanelPositionController()
        controller.bind(to: target)

        target.selectedCorner = nil
        target.onPanelPositionChange?()

        XCTAssertNil(controller.selectedCorner)
    }

    func testRepeatedPositionChangesWithoutNewValuesDoNotPublish() {
        let target = PanelPositioningSpy(
            canPositionPanel: true,
            selectedCorner: .topRight
        )
        let controller = PanelPositionController()
        controller.bind(to: target)
        var changeCount = 0
        let subscription = controller.objectWillChange.sink { changeCount += 1 }

        for _ in 0..<120 {
            target.onPanelPositionChange?()
        }

        XCTAssertEqual(changeCount, 0)

        target.selectedCorner = nil
        target.onPanelPositionChange?()
        target.onPanelPositionChange?()

        XCTAssertEqual(changeCount, 1)
        XCTAssertNil(controller.selectedCorner)
        subscription.cancel()
    }

    func testMoveIsDisabledWithoutAPositionablePanel() {
        let target = PanelPositioningSpy(
            canPositionPanel: false,
            selectedCorner: nil
        )
        let controller = PanelPositionController()
        controller.bind(to: target)

        XCTAssertFalse(controller.move(to: .topLeft))
        XCTAssertTrue(target.moves.isEmpty)
    }
}

@MainActor
private final class PanelPositioningSpy: PanelPositioning {
    var canPositionPanel: Bool
    var selectedCorner: PanelCorner?
    var onPanelPositionChange: (@MainActor () -> Void)?
    private(set) var moves: [PanelCorner] = []

    init(canPositionPanel: Bool, selectedCorner: PanelCorner?) {
        self.canPositionPanel = canPositionPanel
        self.selectedCorner = selectedCorner
    }

    func movePanel(to corner: PanelCorner) -> Bool {
        moves.append(corner)
        selectedCorner = corner
        onPanelPositionChange?()
        return true
    }
}
