import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class SetupOptionsPresenterTests: XCTestCase {
    func testShowHideAndToggleUseAttachedStatusItemAnchor() {
        let popover = FakeSetupOptionsPopover()
        let presenter = SetupOptionsPopoverPresenter(popover: popover)
        let anchor = NSView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        presenter.attach(to: anchor)

        presenter.show()
        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(popover.lastAnchor === anchor)

        presenter.toggle()
        XCTAssertFalse(popover.isShown)

        presenter.toggle()
        XCTAssertTrue(popover.isShown)

        presenter.hide()
        XCTAssertFalse(popover.isShown)
    }
}

@MainActor
private final class FakeSetupOptionsPopover: SetupOptionsPopover {
    private(set) var isShown = false
    private(set) weak var lastAnchor: NSView?

    func show(relativeTo anchor: NSView) {
        lastAnchor = anchor
        isShown = true
    }

    func close() {
        isShown = false
    }
}
