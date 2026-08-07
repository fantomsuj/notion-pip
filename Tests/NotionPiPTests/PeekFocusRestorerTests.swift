import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class PeekFocusRestorerTests: XCTestCase {
    func testPassivePeekRestoresThePreviouslyFrontmostApplication() {
        let previous = FocusApplicationSpy(processIdentifier: 101)
        let notionPiP = FocusApplicationSpy(processIdentifier: 202)
        let frontmost = FrontmostApplicationProvider(previous.application)
        let monitor = PeekInteractionMonitorSpy()
        let restorer = PeekFocusRestorer(
            currentProcessIdentifier: notionPiP.processIdentifier,
            frontmostApplication: { frontmost.application },
            interactionMonitor: monitor
        )

        restorer.beginPeek()
        frontmost.application = notionPiP.application
        restorer.finishPeek()

        XCTAssertEqual(previous.activationCount, 1)
    }

    func testInteractionWithPiPSuppressesFocusRestoration() {
        let previous = FocusApplicationSpy(processIdentifier: 101)
        let notionPiP = FocusApplicationSpy(processIdentifier: 202)
        let frontmost = FrontmostApplicationProvider(previous.application)
        let monitor = PeekInteractionMonitorSpy()
        let restorer = PeekFocusRestorer(
            currentProcessIdentifier: notionPiP.processIdentifier,
            frontmostApplication: { frontmost.application },
            interactionMonitor: monitor
        )

        restorer.beginPeek()
        frontmost.application = notionPiP.application
        monitor.simulateInteraction()
        restorer.finishPeek()

        XCTAssertEqual(previous.activationCount, 0)
    }

    func testAnotherApplicationTakingFocusSuppressesStaleRestoration() {
        let previous = FocusApplicationSpy(processIdentifier: 101)
        let notionPiP = FocusApplicationSpy(processIdentifier: 202)
        let other = FocusApplicationSpy(processIdentifier: 303)
        let frontmost = FrontmostApplicationProvider(previous.application)
        let restorer = PeekFocusRestorer(
            currentProcessIdentifier: notionPiP.processIdentifier,
            frontmostApplication: { frontmost.application },
            interactionMonitor: PeekInteractionMonitorSpy()
        )

        restorer.beginPeek()
        frontmost.application = other.application
        restorer.finishPeek()

        XCTAssertEqual(previous.activationCount, 0)
    }

    func testTerminatedPreviousApplicationIsNotActivated() {
        let previous = FocusApplicationSpy(processIdentifier: 101)
        let notionPiP = FocusApplicationSpy(processIdentifier: 202)
        let frontmost = FrontmostApplicationProvider(previous.application)
        let restorer = PeekFocusRestorer(
            currentProcessIdentifier: notionPiP.processIdentifier,
            frontmostApplication: { frontmost.application },
            interactionMonitor: PeekInteractionMonitorSpy()
        )

        restorer.beginPeek()
        previous.isTerminated = true
        frontmost.application = notionPiP.application
        restorer.finishPeek()

        XCTAssertEqual(previous.activationCount, 0)
    }
}

@MainActor
final class FrontmostApplicationProvider {
    var application: PeekFocusApplication?

    init(_ application: PeekFocusApplication?) {
        self.application = application
    }
}

@MainActor
final class FocusApplicationSpy {
    let processIdentifier: pid_t
    var isTerminated = false
    private(set) var activationCount = 0

    init(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
    }

    var application: PeekFocusApplication {
        PeekFocusApplication(
            processIdentifier: processIdentifier,
            isTerminated: { [weak self] in self?.isTerminated ?? true },
            activate: { [weak self] in
                self?.activationCount += 1
                return self != nil
            }
        )
    }
}

@MainActor
final class PeekInteractionMonitorSpy: PeekInteractionMonitoring {
    private var onInteraction: (@MainActor () -> Void)?

    func start(onInteraction: @escaping @MainActor () -> Void) {
        self.onInteraction = onInteraction
    }

    func stop() {
        onInteraction = nil
    }

    func simulateInteraction() {
        onInteraction?()
    }
}
