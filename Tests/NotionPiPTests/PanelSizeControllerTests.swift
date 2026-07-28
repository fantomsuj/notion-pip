import CoreGraphics
import XCTest

@testable import NotionPiP

@MainActor
final class PanelSizeControllerTests: XCTestCase {
    func testChangingDefaultPersistsWithoutApplyingIt() {
        let store = PanelSizeStoreSpy()
        let target = PanelSizingSpy()
        let controller = PanelSizeController(store: store)
        controller.bind(to: target)

        controller.setDefault(.wide)

        XCTAssertEqual(controller.defaultPresetID, .wide)
        XCTAssertTrue(target.appliedSizes.isEmpty)
        XCTAssertEqual(store.savedPreferences.last?.defaultPresetID, .wide)
    }

    func testApplyUsesAdaptiveScreenSizeAndPersistsRequestedWorkingSize() throws {
        let store = PanelSizeStoreSpy()
        let target = PanelSizingSpy(
            screenSize: CGSize(width: 1_440, height: 900)
        )
        let controller = PanelSizeController(store: store)
        controller.bind(to: target)

        XCTAssertTrue(controller.apply(.comfortable))

        let expected = CGSize(width: 489.6, height: 630)
        XCTAssertEqual(target.appliedSizes, [expected])
        XCTAssertEqual(
            store.savedPreferences.last?.lastExplicitWorkingContentSize,
            try PanelContentSize(expected)
        )
    }

    func testApplyIsDisabledWithoutPinnedPageWhilePresetManagementRemainsAvailable() {
        let store = PanelSizeStoreSpy()
        let target = PanelSizingSpy(hasPinnedPage: false)
        let controller = PanelSizeController(store: store)
        controller.bind(to: target)

        XCTAssertFalse(controller.canApply)
        XCTAssertFalse(controller.apply(.compact))
        XCTAssertTrue(target.appliedSizes.isEmpty)

        XCTAssertNotNil(
            controller.addCustomPreset(
                name: "Writing",
                width: 500,
                height: 700
            )
        )
        XCTAssertEqual(controller.preferences.customPresets.map(\.name), ["Writing"])
    }

    func testManualResizeCompletionPersistsOnlyCompletedWorkingSize() throws {
        let store = PanelSizeStoreSpy()
        let target = PanelSizingSpy()
        let controller = PanelSizeController(store: store)
        controller.bind(to: target)

        target.currentPanelContentSize = CGSize(width: 612.5, height: 744.5)
        XCTAssertTrue(store.savedPreferences.isEmpty)

        target.completeManualResize()

        XCTAssertEqual(
            store.savedPreferences.last?.lastExplicitWorkingContentSize,
            try PanelContentSize(width: 612.5, height: 744.5)
        )
        XCTAssertEqual(
            controller.currentContentSize,
            CGSize(width: 612.5, height: 744.5)
        )
    }

    func testEffectiveClampDoesNotReplaceRequestedWorkingSize() throws {
        let store = PanelSizeStoreSpy()
        let target = PanelSizingSpy(
            currentContentSize: CGSize(width: 420, height: 520),
            effectiveAppliedSize: CGSize(width: 500, height: 400)
        )
        let controller = PanelSizeController(store: store)
        controller.bind(to: target)

        XCTAssertTrue(controller.apply(.wide))

        XCTAssertEqual(controller.currentContentSize, CGSize(width: 500, height: 400))
        XCTAssertEqual(
            store.savedPreferences.last?.lastExplicitWorkingContentSize,
            try PanelContentSize(width: 680, height: 720)
        )
    }

    func testDefaultSuffixAndManageActionAreSharedControllerState() {
        let controller = PanelSizeController(store: PanelSizeStoreSpy())
        var manageCount = 0
        controller.onManagePanelSizes = { manageCount += 1 }

        XCTAssertEqual(
            controller.presets.map(controller.displayName),
            ["Compact", "Comfortable — Default", "Wide"]
        )

        controller.managePanelSizes()

        XCTAssertEqual(manageCount, 1)
    }
}

private final class PanelSizeStoreSpy: PanelSizePreferencesPersisting {
    let loadedPreferences: PanelSizePreferences?
    private(set) var savedPreferences: [PanelSizePreferences] = []

    init(loadedPreferences: PanelSizePreferences? = nil) {
        self.loadedPreferences = loadedPreferences
    }

    func load() -> PanelSizePreferences? {
        loadedPreferences
    }

    func save(_ preferences: PanelSizePreferences) throws {
        savedPreferences.append(preferences)
    }
}

@MainActor
private final class PanelSizingSpy: PanelSizing {
    var hasPinnedPage: Bool
    var currentPanelContentSize: CGSize
    var sizingScreenSize: CGSize
    var onManualResizeCompletion: (@MainActor (CGSize) -> Void)?
    var onPinnedPageAvailabilityChange: (@MainActor () -> Void)?
    private let effectiveAppliedSize: CGSize?
    private(set) var appliedSizes: [CGSize] = []

    init(
        hasPinnedPage: Bool = true,
        currentContentSize: CGSize = CGSize(width: 520, height: 680),
        screenSize: CGSize = CGSize(width: 1_440, height: 900),
        effectiveAppliedSize: CGSize? = nil
    ) {
        self.hasPinnedPage = hasPinnedPage
        currentPanelContentSize = currentContentSize
        sizingScreenSize = screenSize
        self.effectiveAppliedSize = effectiveAppliedSize
    }

    func applyPanelContentSize(_ contentSize: CGSize) -> Bool {
        guard hasPinnedPage else { return false }
        appliedSizes.append(contentSize)
        currentPanelContentSize = effectiveAppliedSize ?? contentSize
        return true
    }

    func completeManualResize() {
        onManualResizeCompletion?(currentPanelContentSize)
    }
}
