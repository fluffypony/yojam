import XCTest
@testable import YojamCore

final class HandoffIntakeTests: XCTestCase {
    func testHandoffRequestHasCorrectOrigin() {
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com/article")!,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(request.origin, .handoff)
        XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.handoff)
        XCTAssertEqual(request.url.absoluteString, "https://example.com/article")
    }

    func testHandoffRequestDefaultModifiers() {
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(request.modifierFlags, 0)
        XCTAssertFalse(request.forcePicker)
        XCTAssertFalse(request.forcePrivateWindow)
        XCTAssertNil(request.forcedBrowserBundleId)
    }

    func testHandoffRequestWithModifiers() {
        let shiftFlag: UInt = 1 << 17 // NSEvent.ModifierFlags.shift
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff,
            modifierFlags: shiftFlag
        )
        XCTAssertEqual(request.modifierFlags, shiftFlag)
    }

    func testHandoffRequestReceivedAtIsRecent() {
        let before = Date()
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        let after = Date()
        XCTAssertGreaterThanOrEqual(request.receivedAt, before)
        XCTAssertLessThanOrEqual(request.receivedAt, after)
    }

    func testHandoffSentinelIsCorrectValue() {
        XCTAssertEqual(SourceAppSentinel.handoff, "com.yojam.source.handoff")
    }

    func testHandoffRequestPreservesHTTPSURL() {
        let url = URL(string: "https://www.apple.com/iphone")!
        let request = IncomingLinkRequest(
            url: url,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "www.apple.com")
        XCTAssertEqual(request.url.path, "/iphone")
    }

    func testHandoffRequestPreservesHTTPURL() {
        let url = URL(string: "http://example.com/page")!
        let request = IncomingLinkRequest(
            url: url,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(request.url.scheme, "http")
    }

    func testHandoffRequestEmptyMetadata() {
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertTrue(request.metadata.isEmpty)
    }
}
