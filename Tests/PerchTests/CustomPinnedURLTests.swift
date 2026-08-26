import Foundation
import XCTest
@testable import Perch

final class CustomPinnedURLTests: XCTestCase {
    func testAcceptsHTTPSWebURLAndCanonicalizesHostAndPath() throws {
        let pin = try CustomPinnedURL(
            validating: XCTUnwrap(URL(string: "https://Canvas.Example.EDU/courses/12?view=1#module"))
        )

        XCTAssertEqual(pin.canonicalURL.absoluteString, "https://canvas.example.edu/courses/12?view=1")
        XCTAssertEqual(pin.displayTitle, "canvas.example.edu")
        XCTAssertEqual(pin.host, "canvas.example.edu")
        XCTAssertEqual(pin.id, pin.canonicalURL.absoluteString)
    }

    func testAddsHTTPSWhenTheSchemeIsOmitted() throws {
        let pin = try CustomPinnedURL(validatingString: "canvas.example.edu/login")

        XCTAssertEqual(pin.canonicalURL.absoluteString, "https://canvas.example.edu/login")
    }

    func testRejectsHTTPCredentialsEmptyHostAndNotionPages() throws {
        XCTAssertThrowsError(
            try CustomPinnedURL(validatingString: "")
        ) { error in
            XCTAssertEqual(error as? CustomPinnedURLError, .invalidURL)
        }
        XCTAssertThrowsError(
            try CustomPinnedURL(validating: XCTUnwrap(URL(string: "http://canvas.example.edu")))
        ) { error in
            XCTAssertEqual(error as? CustomPinnedURLError, .unsupportedScheme)
        }
        XCTAssertThrowsError(
            try CustomPinnedURL(
                validating: XCTUnwrap(URL(string: "https://user:secret@canvas.example.edu"))
            )
        ) { error in
            XCTAssertEqual(error as? CustomPinnedURLError, .credentialsNotAllowed)
        }
        XCTAssertThrowsError(
            try CustomPinnedURL(
                validating: XCTUnwrap(
                    URL(string: "https://www.notion.so/Notes-0123456789abcdef0123456789abcdef")
                )
            )
        ) { error in
            XCTAssertEqual(error as? CustomPinnedURLError, .notionPageURL)
        }
    }

    func testUsesAnExplicitTitleWhenProvided() throws {
        let pin = try CustomPinnedURL(
            validating: XCTUnwrap(URL(string: "https://canvas.example.edu/courses/1")),
            displayTitle: "  Design  Studio  "
        )

        XCTAssertEqual(pin.displayTitle, "Design Studio")
        XCTAssertEqual(pin.resolvingDisplayTitle("Canvas Dashboard").displayTitle, "Canvas Dashboard")
    }
}

final class CustomPinnedURLStoreTests: XCTestCase {
    func testMissingPreferencesDefaultToDisabledWithNoPins() throws {
        let store = try makeStore()

        XCTAssertEqual(store.load(), .empty)
    }

    func testPersistsEnabledPinsAndLastActiveDestination() throws {
        let store = try makeStore()
        let pin = try CustomPinnedURL(validatingString: "https://canvas.example.edu")
        let snapshot = CustomPinnedURLSnapshot(
            isEnabled: true,
            pins: [pin],
            lastActiveID: pin.id
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
        XCTAssertEqual(store.load().lastActivePin, pin)
    }

    func testClearingLastActiveIDRemovesTheStoredValue() throws {
        let store = try makeStore()
        let pin = try CustomPinnedURL(validatingString: "https://canvas.example.edu")
        store.save(
            CustomPinnedURLSnapshot(isEnabled: true, pins: [pin], lastActiveID: pin.id)
        )

        store.saveLastActiveID(nil)

        XCTAssertNil(store.loadLastActiveID())
        XCTAssertTrue(store.loadEnabled())
        XCTAssertEqual(store.loadPins(), [pin])
    }

    private func makeStore() throws -> CustomPinnedURLStore {
        let suiteName = "CustomPinnedURLStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return CustomPinnedURLStore(defaults: defaults)
    }
}
