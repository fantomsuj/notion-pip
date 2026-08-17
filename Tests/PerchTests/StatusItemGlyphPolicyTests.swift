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
            let raster = rasterizeStatusItemImage(image)
            XCTAssertTrue(image.isTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertGreaterThan(
                raster.visiblePixelCount,
                0,
                "Expected \(glyph) to draw visible pixels"
            )
        }
    }

    func testStateGlyphsProduceMeaningfullyDifferentVisibleMarks() {
        let glyphs = [
            StatusItemGlyph.visible,
            .stashed,
            .loading,
            .needsSignIn,
        ]
        let rasters = glyphs.map {
            rasterizeStatusItemImage(StatusItemGlyphPolicy.makeImage(for: $0))
        }

        for firstIndex in rasters.indices {
            for secondIndex in rasters.indices where secondIndex > firstIndex {
                XCTAssertGreaterThan(
                    rasters[firstIndex].differingPixelCount(from: rasters[secondIndex]),
                    4,
                    "Expected \(glyphs[firstIndex]) and \(glyphs[secondIndex]) to differ"
                )
            }
        }
    }

    func testHoveredVisibleMarkDiffersFromRestingMarkOnTheSameCanvas() {
        let resting = StatusItemGlyphPolicy.makeImage(for: .visible)
        let hovered = StatusItemGlyphPolicy.makeImage(for: .visible, separation: 1.5)
        let restingRaster = rasterizeStatusItemImage(resting)
        let hoveredRaster = rasterizeStatusItemImage(hovered)

        XCTAssertEqual(resting.size, hovered.size)
        XCTAssertTrue(hovered.isTemplate)
        XCTAssertGreaterThan(restingRaster.visiblePixelCount, 0)
        XCTAssertGreaterThan(hoveredRaster.visiblePixelCount, 0)
        XCTAssertGreaterThan(restingRaster.differingPixelCount(from: hoveredRaster), 4)
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
