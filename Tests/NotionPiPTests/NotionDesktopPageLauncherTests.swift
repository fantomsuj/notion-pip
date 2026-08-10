import XCTest

@testable import NotionPiP

@MainActor
final class NotionDesktopPageLauncherTests: XCTestCase {
    func testOpenNewPageUsesNotionDesktopNewPageRoute() {
        var openedURL: URL?
        var failureCount = 0
        let launcher = NotionDesktopPageLauncher { url in
            openedURL = url
            return true
        } reportFailure: {
            failureCount += 1
        }

        XCTAssertTrue(launcher.openNewPage())
        XCTAssertEqual(openedURL?.absoluteString, "notion://www.notion.so/new")
        XCTAssertEqual(failureCount, 0)
    }

    func testOpenNewPageReportsWhenTheNativeRouteCannotBeOpened() {
        var failureCount = 0
        let launcher = NotionDesktopPageLauncher(
            openURL: { _ in false },
            reportFailure: { failureCount += 1 }
        )

        XCTAssertFalse(launcher.openNewPage())
        XCTAssertEqual(failureCount, 1)
    }
}
