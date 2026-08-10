import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class WindowRolePolicyTests: XCTestCase {
    func testOnboardingRoleCreatesRetainedNormalKeyWindow() {
        let window = WindowRole.onboarding.makeWindow()

        XCTAssertTrue(type(of: window) == KeyCapableAppWindow.self)
        XCTAssertEqual(window.styleMask, [.titled, .closable, .resizable])
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(
            window.collectionBehavior,
            [.moveToActiveSpace, .fullScreenAuxiliary]
        )
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).size,
            CGSize(width: 760, height: 520)
        )
        XCTAssertEqual(window.contentMinSize, CGSize(width: 680, height: 480))
    }

    func testSettingsRoleCreatesRetainedNormalKeyWindow() {
        let window = WindowRole.settings.makeWindow()

        XCTAssertTrue(type(of: window) == KeyCapableAppWindow.self)
        XCTAssertEqual(window.styleMask, [.titled, .closable, .resizable])
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(
            window.collectionBehavior,
            [.moveToActiveSpace, .fullScreenAuxiliary]
        )
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, CGSize(width: 480, height: 460))
        XCTAssertEqual(window.contentMinSize, CGSize(width: 440, height: 420))
    }

    func testPinPageRoleCreatesRetainedFixedFloatingKeyWindow() {
        let window = WindowRole.pinPage.makeWindow()

        XCTAssertTrue(type(of: window) == KeyCapableAppWindow.self)
        XCTAssertEqual(window.styleMask, [.titled, .closable])
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(
            window.collectionBehavior,
            [.moveToActiveSpace, .fullScreenAuxiliary]
        )
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, CGSize(width: 440, height: 180))
        XCTAssertEqual(window.contentMinSize, CGSize(width: 440, height: 180))
        XCTAssertEqual(window.contentMaxSize, CGSize(width: 440, height: 180))
    }

    func testPiPRoleCreatesRetainedFloatingKeyOverlayPanel() {
        let window = WindowRole.pictureInPicture.makeWindow()

        XCTAssertTrue(type(of: window) == KeyCapablePiPPanel.self)
        XCTAssertEqual(window.styleMask, [.titled, .closable, .resizable])
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(
            window.collectionBehavior,
            [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        )
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, CGSize(width: 480, height: 720))
        XCTAssertEqual(window.contentMinSize, CGSize(width: 360, height: 420))
    }

    func testStashHandleRoleCreatesRetainedNonactivatingOverlayPanel() {
        let window = WindowRole.stashHandle.makeWindow()

        XCTAssertTrue(type(of: window) == NSPanel.self)
        XCTAssertEqual(window.styleMask, [.borderless, .nonactivatingPanel])
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(
            window.collectionBehavior,
            [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        )
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, .zero)
        XCTAssertEqual(window.contentMinSize, .zero)
    }
}
