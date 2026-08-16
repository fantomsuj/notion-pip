import XCTest
@testable import Perch

@MainActor
final class StatusItemGlyphPolicyTests: XCTestCase {
    func testRestingAndOpenPanelUseTheSharedRectangleFamily() {
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .unavailable,
                sessionState: .unloaded,
                loginState: .idle
            ),
            .stashed
        )
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .stashed,
                sessionState: .active,
                loginState: .idle
            ),
            .stashed
        )
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .visible,
                sessionState: .active,
                loginState: .idle
            ),
            .visible
        )
    }

    func testEveryGlyphRendersAsANonemptyTemplateImage() {
        for glyph in [
            StatusItemGlyph.visible,
            .stashed,
            .loading,
            .needsSignIn,
        ] {
            let image = StatusItemGlyphPolicy.makeImage(for: glyph)
            XCTAssertTrue(image.isTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    func testHoveredVisibleMarkKeepsItsCanvasSize() {
        let resting = StatusItemGlyphPolicy.makeImage(for: .visible)
        let hovered = StatusItemGlyphPolicy.makeImage(for: .visible, separation: 1.5)
        XCTAssertEqual(resting.size, hovered.size)
        XCTAssertTrue(hovered.isTemplate)
    }

    func testLoadingAndSignInOverridePresentationAndPreferSignIn() {
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .visible,
                sessionState: .loading,
                loginState: .idle
            ),
            .loading
        )
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .stashed,
                sessionState: .active,
                loginState: .openingBrowser
            ),
            .loading
        )
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .visible,
                sessionState: .loading,
                loginState: .loginRequired
            ),
            .needsSignIn
        )
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .stashed,
                sessionState: .failed("Network"),
                loginState: .failed("Sign-in")
            ),
            .needsSignIn
        )
        XCTAssertEqual(
            StatusItemGlyphPolicy.glyph(
                presentation: .visible,
                sessionState: .active,
                loginState: .restorationFailed("Reload")
            ),
            .needsSignIn
        )
    }

    func testGlyphsExposeStateAwareAccessibilityLabels() {
        XCTAssertEqual(StatusItemGlyph.visible.accessibilityLabel, "Perch is open")
        XCTAssertEqual(StatusItemGlyph.stashed.accessibilityLabel, "Perch")
        XCTAssertEqual(StatusItemGlyph.loading.accessibilityLabel, "Perch is loading")
        XCTAssertEqual(StatusItemGlyph.needsSignIn.accessibilityLabel, "Perch needs sign-in")
    }
}
