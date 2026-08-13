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
        XCTAssertEqual(
            StatusItemGlyph.visible.systemSymbolName,
            "rectangle.on.rectangle"
        )
        XCTAssertEqual(
            StatusItemGlyph.stashed.systemSymbolName,
            "rectangle.bottomhalf.inset.filled"
        )
        XCTAssertEqual(
            StatusItemGlyph.loading.systemSymbolName,
            "rectangle.dashed"
        )
        XCTAssertEqual(
            StatusItemGlyph.needsSignIn.systemSymbolName,
            "rectangle.badge.person.crop"
        )
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
