import XCTest
@testable import Perch

@MainActor
final class StatusItemEventRouterTests: XCTestCase {
    func testClickOpensMenuAndHoldPeeksUntilRelease() {
        let scheduler = RuntimeShortcutGestureScheduler()
        var menuCount = 0
        var peekCount = 0
        var commitCount = 0
        var cancelCount = 0
        let router = StatusItemEventRouter(
            holdDuration: .milliseconds(300),
            scheduler: scheduler,
            onMenu: { menuCount += 1 },
            onBeginPeek: {
                peekCount += 1
                return true
            },
            onCommitPeek: { commitCount += 1 },
            onCancelPeek: { cancelCount += 1 }
        )

        router.handle(eventType: .leftMouseUp)
        XCTAssertEqual(menuCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)

        router.handle(eventType: .leftMouseDown)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(peekCount, 0)

        router.handle(eventType: .leftMouseUp, isPointerInside: true)
        XCTAssertEqual(menuCount, 2)
        XCTAssertEqual(peekCount, 0)

        router.handle(eventType: .leftMouseDown)
        scheduler.fireNext()
        XCTAssertEqual(peekCount, 1)

        router.handle(eventType: .leftMouseUp, isPointerInside: true)
        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(cancelCount, 0)

        router.handle(eventType: .leftMouseDown)
        scheduler.fireNext()
        router.handle(eventType: .leftMouseUp, isPointerInside: false)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(menuCount, 2)
    }

    func testFailedPeekKeepsTheClickAsAMenu() {
        let scheduler = RuntimeShortcutGestureScheduler()
        var menuCount = 0
        let router = StatusItemEventRouter(
            scheduler: scheduler,
            onMenu: { menuCount += 1 },
            onBeginPeek: { false }
        )

        router.handle(eventType: .leftMouseDown)
        scheduler.fireNext()
        router.handle(eventType: .leftMouseUp, isPointerInside: true)

        XCTAssertEqual(menuCount, 1)
    }
}
