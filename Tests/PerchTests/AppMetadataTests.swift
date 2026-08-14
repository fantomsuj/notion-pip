import XCTest
@testable import Perch

final class AppMetadataTests: XCTestCase {
    func testReadsReleaseFactsFromBundleInformation() {
        let metadata = AppMetadata(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "42",
            "LSMinimumSystemVersion": "14.0",
            "NSHumanReadableCopyright": "Copyright © 2026 Sujay Jayakar"
        ])

        XCTAssertEqual(metadata.versionAndBuild, "0.1.0 (42)")
        XCTAssertEqual(metadata.minimumSystemVersion, "14.0")
        XCTAssertEqual(metadata.copyright, "Copyright © 2026 Sujay Jayakar")
    }

    func testUsesCalmFallbacksWhenBundleInformationIsUnavailable() {
        let metadata = AppMetadata(infoDictionary: [:])

        XCTAssertEqual(metadata.versionAndBuild, "Unknown")
        XCTAssertEqual(metadata.minimumSystemVersion, "Unknown")
        XCTAssertNil(metadata.copyright)
    }
}
