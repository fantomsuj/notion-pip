import XCTest
@testable import Perch

final class StorageRecoveryPresentationTests: XCTestCase {
    func testActionsHaveDeterministicFocusOrderLabelsHelpAndDefault() {
        XCTAssertEqual(
            StorageRecoveryAction.allCases,
            [.revealStore, .continueWithoutSaving, .archiveStoreAndQuit]
        )
        XCTAssertEqual(
            StorageRecoveryAction.allCases.map(\.label),
            [
                "Reveal Store in Finder",
                "Continue Without Saving",
                "Archive Store and Quit…",
            ]
        )
        XCTAssertEqual(
            StorageRecoveryAction.allCases.filter(\.isDefault),
            [.continueWithoutSaving]
        )
        XCTAssertTrue(
            StorageRecoveryAction.allCases.allSatisfy { !$0.accessibilityHelp.isEmpty }
        )
    }

    func testExplanationAndConfirmationDescribeDataSafetyExactly() {
        let explanation = StorageRecoveryPresentation.explanation
        let confirmation = StorageRecoveryPresentation.archiveConfirmationMessage

        XCTAssertTrue(explanation.contains("Notion pages and account data are unaffected"))
        XCTAssertTrue(explanation.contains("will not save local page history"))
        for artifact in PersistentStoreArchiveService.artifactNames {
            XCTAssertTrue(confirmation.contains(artifact))
        }
        XCTAssertTrue(confirmation.contains("Recovery"))
        XCTAssertTrue(confirmation.contains("empty local page history"))
        XCTAssertTrue(confirmation.contains("Notion pages and account data are unaffected"))
    }
}
