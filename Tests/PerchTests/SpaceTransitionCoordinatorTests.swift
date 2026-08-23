import Foundation
import XCTest
@testable import Perch

@MainActor
final class SpaceTransitionCoordinatorTests: XCTestCase {
    func testSpaceChangeWithoutAHintPublishesADirectionlessArrival() {
        let harness = makeHarness()
        harness.observer.start { event in
            harness.events.append(event)
        }

        harness.postSpaceChange()

        XCTAssertEqual(harness.events, [.activeSpaceDidChange(nil)])
    }

    func testFreshSwipeHintSuppliesDirectionWithoutStartingATransition() {
        let harness = makeHarness()
        harness.observer.start { event in
            harness.events.append(event)
        }

        harness.observer.recordHint(.toTrailing, at: 1, publishes: false)
        harness.postSpaceChange()

        XCTAssertEqual(harness.events, [.activeSpaceDidChange(.toTrailing)])
    }

    func testControlArrowHintPublishesImmediatelyAndIsConsumedByTheSpaceChange() {
        let harness = makeHarness()
        harness.observer.start { event in
            harness.events.append(event)
        }

        harness.observer.recordHint(.toLeading, at: 1, publishes: true)
        harness.postSpaceChange()

        XCTAssertEqual(
            harness.events,
            [.gestureHint(.toLeading), .activeSpaceDidChange(.toLeading)]
        )
    }

    func testStaleHintDoesNotAffectALaterSpaceChange() {
        let harness = makeHarness()
        harness.observer.start { event in
            harness.events.append(event)
        }

        harness.observer.recordHint(.toTrailing, at: 1, publishes: false)
        harness.now = 1 + SpaceTransitionMotionPolicy.hintValidity + 0.01
        harness.postSpaceChange()

        XCTAssertEqual(harness.events, [.activeSpaceDidChange(nil)])
    }

    func testStopRemovesDeliveryAndDropsTheStoredHint() {
        let harness = makeHarness()
        harness.observer.start { event in
            harness.events.append(event)
        }
        harness.observer.recordHint(.toTrailing, at: 1, publishes: false)

        harness.observer.stop()
        harness.postSpaceChange()
        harness.observer.recordHint(.toLeading, at: 2, publishes: true)

        XCTAssertTrue(harness.events.isEmpty)
    }

    private func makeHarness() -> SpaceTransitionObserverHarness {
        SpaceTransitionObserverHarness()
    }
}

@MainActor
private final class SpaceTransitionObserverHarness {
    let center = NotificationCenter()
    let name = Notification.Name("SpaceTransitionCoordinatorTests.spaceDidChange")
    var now: TimeInterval = 1
    var events: [SpaceTransitionEvent] = []
    lazy var observer = AppKitSpaceTransitionObserver(
        notificationCenter: center,
        notificationName: name,
        nowProvider: { [weak self] in self?.now ?? 0 },
        installsEventMonitors: false
    )

    func postSpaceChange() {
        center.post(name: name, object: nil)
    }
}
