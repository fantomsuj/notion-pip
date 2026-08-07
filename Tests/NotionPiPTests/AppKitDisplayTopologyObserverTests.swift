import AppKit
import XCTest

@testable import NotionPiP

@MainActor
final class AppKitDisplayTopologyObserverTests: XCTestCase {
    func testNotificationsCaptureIncreasingRevisionsAndCurrentDescriptors() {
        let center = NotificationCenter()
        let name = Notification.Name("DisplayTopologyObserverTests.change")
        let displays = MutableDisplayDescriptors([makeDisplay(id: 11, x: 0)])
        let observer = AppKitDisplayTopologyObserver(
            notificationCenter: center,
            notificationName: name,
            displaysProvider: { displays.value }
        )
        var received: [DisplayTopology] = []
        observer.start { received.append($0) }

        displays.value = [makeDisplay(id: 11, x: 0), makeDisplay(id: 22, x: 1_440)]
        center.post(name: name, object: nil)
        displays.value = [makeDisplay(id: 11, x: 0), makeDisplay(id: 77, x: -1_440)]
        center.post(name: name, object: nil)

        XCTAssertEqual(received.map(\.revision), [1, 2])
        XCTAssertEqual(received[0].displays.map(\.identifier), [11, 22])
        XCTAssertEqual(received[1].displays.map(\.identifier), [11, 77])
        XCTAssertEqual(observer.currentTopology, received.last)
    }

    func testStopPreventsFurtherTopologyDelivery() {
        let center = NotificationCenter()
        let name = Notification.Name("DisplayTopologyObserverTests.stop")
        let observer = AppKitDisplayTopologyObserver(
            notificationCenter: center,
            notificationName: name,
            displaysProvider: { [self.makeDisplay(id: 11, x: 0)] }
        )
        var received: [DisplayTopology] = []
        observer.start { received.append($0) }

        observer.stop()
        center.post(name: name, object: nil)

        XCTAssertTrue(received.isEmpty)
    }

    private func makeDisplay(id: UInt32, x: CGFloat) -> DisplayDescriptor {
        DisplayDescriptor(
            identifier: id,
            frame: CGRect(x: x, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: x, y: 0, width: 1_440, height: 875),
            backingScaleFactor: 2,
            isPrimary: x == 0
        )
    }
}

@MainActor
private final class MutableDisplayDescriptors {
    var value: [DisplayDescriptor]

    init(_ value: [DisplayDescriptor]) {
        self.value = value
    }
}
