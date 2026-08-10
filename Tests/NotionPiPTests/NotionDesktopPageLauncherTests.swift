import XCTest

@testable import NotionPiP

@MainActor
final class NotionDesktopPageLauncherTests: XCTestCase {
    func testOpenNewPageUsesNotionDesktopNewPageRoute() {
        var openedURL: URL?
        let launcher = NotionDesktopPageLauncher { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(launcher.openNewPage())
        XCTAssertEqual(openedURL?.absoluteString, "notion://www.notion.so/new")
    }

    func testOpenNewPageReportsWhenTheNativeRouteCannotBeOpened() {
        let launcher = NotionDesktopPageLauncher { _ in false }

        XCTAssertFalse(launcher.openNewPage())
    }
}
