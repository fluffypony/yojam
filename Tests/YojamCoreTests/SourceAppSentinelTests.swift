import XCTest
@testable import YojamCore

final class SourceAppSentinelTests: XCTestCase {
    func testAllSentinelsHaveYojamPrefix() {
        for sentinel in SourceAppSentinel.all {
            XCTAssertTrue(sentinel.hasPrefix("com.yojam.source."),
                         "Sentinel \(sentinel) should have com.yojam.source. prefix")
        }
    }

    func testAllSentinelsAreUnique() {
        let unique = Set(SourceAppSentinel.all)
        XCTAssertEqual(unique.count, SourceAppSentinel.all.count,
                      "All sentinels should be unique")
    }

    func testSentinelValues() {
        XCTAssertEqual(SourceAppSentinel.handoff, "com.yojam.source.handoff")
        XCTAssertEqual(SourceAppSentinel.airdrop, "com.yojam.source.airdrop")
        XCTAssertEqual(SourceAppSentinel.shareExtension, "com.yojam.source.share-extension")
        XCTAssertEqual(SourceAppSentinel.servicesMenu, "com.yojam.source.service")
        XCTAssertEqual(SourceAppSentinel.safariExtension, "com.yojam.source.safari-extension")
        XCTAssertEqual(SourceAppSentinel.chromeExtension, "com.yojam.source.chrome-extension")
        XCTAssertEqual(SourceAppSentinel.firefoxExtension, "com.yojam.source.firefox-extension")
        XCTAssertEqual(SourceAppSentinel.urlScheme, "com.yojam.source.url-scheme")
        XCTAssertEqual(SourceAppSentinel.cli, "com.yojam.source.cli")
    }

    func testSentinelRuleMatching() {
        // Verify that a rule's sourceAppBundleId filter can target sentinels
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(request.sourceAppBundleId, "com.yojam.source.handoff")

        // A rule that requires handoff source should match
        let ruleSourceAppId = SourceAppSentinel.handoff
        XCTAssertEqual(request.sourceAppBundleId, ruleSourceAppId)

        // A rule that requires a different source should not match
        let otherSourceAppId = SourceAppSentinel.airdrop
        XCTAssertNotEqual(request.sourceAppBundleId, otherSourceAppId)
    }
}
