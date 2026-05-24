import XCTest
@testable import Yojam

final class RuleLiveTestPersistenceTests: XCTestCase {
    @MainActor
    func testLiveTestURLIsStoredInRuleMetadata() {
        let metadata = AddRuleSheet.metadataByPersistingLiveTestURL(
            "https://example.com/path",
            existingMetadata: ["importedFrom": "finicky"])

        XCTAssertEqual(metadata?[AddRuleSheet.liveTestURLMetadataKey], "https://example.com/path")
        XCTAssertEqual(metadata?["importedFrom"], "finicky")
    }

    @MainActor
    func testClearingLiveTestURLPreservesOtherMetadata() {
        let metadata = AddRuleSheet.metadataByPersistingLiveTestURL(
            "",
            existingMetadata: [
                AddRuleSheet.liveTestURLMetadataKey: "https://example.com/path",
                "importedFrom": "finicky",
            ])

        XCTAssertNil(metadata?[AddRuleSheet.liveTestURLMetadataKey])
        XCTAssertEqual(metadata?["importedFrom"], "finicky")
    }

    @MainActor
    func testClearingOnlyLiveTestURLDropsEmptyMetadata() {
        let metadata = AddRuleSheet.metadataByPersistingLiveTestURL(
            "",
            existingMetadata: [AddRuleSheet.liveTestURLMetadataKey: "https://example.com/path"])

        XCTAssertNil(metadata)
    }
}
