import AppKit
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

    func testOrdinaryTypingIsFilteredOutBeforeAnyHintIsRecorded() {
        XCTAssertNil(AppKitSpaceTransitionObserver.keyHint(modifierFlags: [], keyCode: 0))
        XCTAssertNil(AppKitSpaceTransitionObserver.keyHint(modifierFlags: [], keyCode: 123))
        XCTAssertNil(
            AppKitSpaceTransitionObserver.keyHint(modifierFlags: [.control], keyCode: 0)
        )
        XCTAssertNil(
            AppKitSpaceTransitionObserver.keyHint(
                modifierFlags: [.control, .command],
                keyCode: 123
            )
        )
        XCTAssertNil(
            AppKitSpaceTransitionObserver.keyHint(
                modifierFlags: [.control, .option],
                keyCode: 124
            )
        )
    }

    func testControlArrowAndSwipeProduceHints() {
        XCTAssertEqual(
            AppKitSpaceTransitionObserver.keyHint(modifierFlags: [.control], keyCode: 123),
            SpaceTransitionHint(direction: .toLeading, publishes: true)
        )
        XCTAssertEqual(
            AppKitSpaceTransitionObserver.keyHint(modifierFlags: [.control], keyCode: 124),
            SpaceTransitionHint(direction: .toTrailing, publishes: true)
        )
        XCTAssertEqual(
            AppKitSpaceTransitionObserver.swipeHint(deltaX: -1),
            SpaceTransitionHint(direction: .toTrailing, publishes: false)
        )
        XCTAssertNil(AppKitSpaceTransitionObserver.swipeHint(deltaX: 0))
    }

    func testKeyEventsAreFilteredFromTheEventItself() throws {
        let letter = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )
        let controlLeft = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 123
            )
        )

        XCTAssertNil(AppKitSpaceTransitionObserver.hint(from: letter))
        XCTAssertEqual(
            AppKitSpaceTransitionObserver.hint(from: controlLeft),
            SpaceTransitionHint(direction: .toLeading, publishes: true)
        )
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
