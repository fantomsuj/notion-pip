import XCTest
@testable import Perch

final class StatusItemPointerPolicyTests: XCTestCase {
    func testClickShowsMenuAndHoldPeeks() {
        assertTransition(
            from: .idle,
            event: .leftMouseDown,
            to: .holding,
            commands: [.beginHold]
        )
        assertTransition(
            from: .holding,
            event: .leftMouseUp(isPointerInside: true),
            to: .idle,
            commands: [.showMenu]
        )
        assertTransition(
            from: .idle,
            event: .leftMouseUp(isPointerInside: true),
            to: .idle,
            commands: [.showMenu]
        )
        assertTransition(
            from: .holding,
            event: .holdElapsed,
            to: .peeking,
            commands: [.beginPeek]
        )
    }

    func testReleaseCommitsOrCancelsAnActivePeek() {
        assertTransition(
            from: .peeking,
            event: .leftMouseUp(isPointerInside: true),
            to: .idle,
            commands: [.commitPeek]
        )
        assertTransition(
            from: .peeking,
            event: .leftMouseUp(isPointerInside: false),
            to: .idle,
            commands: [.cancelPeek]
        )
    }

    func testRightClickCancelsPeekAndAlwaysOpensTheMenu() {
        assertTransition(
            from: .idle,
            event: .rightMouseUp,
            to: .idle,
            commands: [.showMenu]
        )
        assertTransition(
            from: .holding,
            event: .rightMouseUp,
            to: .idle,
            commands: [.showMenu]
        )
        assertTransition(
            from: .peeking,
            event: .rightMouseUp,
            to: .idle,
            commands: [.cancelPeek, .showMenu]
        )
    }

    func testStaleHoldAndRepeatedPressesDoNotChangePhase() {
        assertTransition(
            from: .idle,
            event: .holdElapsed,
            to: .idle,
            commands: []
        )
        assertTransition(
            from: .peeking,
            event: .holdElapsed,
            to: .peeking,
            commands: []
        )
        assertTransition(
            from: .holding,
            event: .leftMouseDown,
            to: .holding,
            commands: []
        )
        assertTransition(
            from: .peeking,
            event: .leftMouseDown,
            to: .peeking,
            commands: []
        )
    }

    private func assertTransition(
        from phase: StatusItemPointerPhase,
        event: StatusItemPointerEvent,
        to expectedPhase: StatusItemPointerPhase,
        commands expectedCommands: [StatusItemPointerCommand],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (nextPhase, commands) = StatusItemPointerPolicy.handle(
            phase: phase,
            event: event
        )
        XCTAssertEqual(nextPhase, expectedPhase, file: file, line: line)
        XCTAssertEqual(commands, expectedCommands, file: file, line: line)
    }
}
