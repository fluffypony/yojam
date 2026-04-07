import XCTest
@testable import YojamCore

/// Verifies that the same target URL produces structurally equivalent
/// IncomingLinkRequests regardless of the ingress path. The routing
/// pipeline only examines the URL, sourceAppBundleId, modifiers, and
/// force flags — so parity means the URL arrives intact through each path.
final class IngressParityTests: XCTestCase {
    let targetURL = URL(string: "https://example.com/page?q=search")!

    // MARK: - All origins produce the same URL

    func testAllOriginsPreserveTargetURL() {
        let origins: [(IngressOrigin, String?)] = [
            (.defaultHandler, nil),
            (.handoff, SourceAppSentinel.handoff),
            (.airdrop, SourceAppSentinel.airdrop),
            (.shareExtension, SourceAppSentinel.shareExtension),
            (.safariExtension, SourceAppSentinel.safariExtension),
            (.chromeExtension, SourceAppSentinel.chromeExtension),
            (.firefoxExtension, SourceAppSentinel.firefoxExtension),
            (.servicesMenu, SourceAppSentinel.servicesMenu),
            (.urlScheme, SourceAppSentinel.urlScheme),
            (.intent, nil),
            (.fileOpen, nil),
            (.clipboard, nil),
        ]

        for (origin, sentinel) in origins {
            let request = IncomingLinkRequest(
                url: targetURL,
                sourceAppBundleId: sentinel,
                origin: origin
            )
            XCTAssertEqual(
                request.url.absoluteString, targetURL.absoluteString,
                "URL should be preserved for origin: \(origin)")
        }
    }

    // MARK: - yojam:// round-trip preserves URL

    func testYojamSchemeRoundTripPreservesURL() {
        // Build a yojam:// URL the way the Share Extension would
        guard let yojamURL = YojamCommand.buildRoute(
            target: targetURL,
            source: SourceAppSentinel.shareExtension
        ) else {
            XCTFail("buildRoute should succeed")
            return
        }

        // Parse it back the way AppDelegate would
        guard let command = YojamCommand.parse(yojamURL),
              case .route(let request) = command else {
            XCTFail("Should round-trip through yojam:// scheme")
            return
        }

        XCTAssertEqual(request.url.absoluteString, targetURL.absoluteString)
        XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.shareExtension)
    }

    // MARK: - Internet-location file normalization produces same URL

    func testWeblocExtractionProducesHTTPURL() {
        // IncomingLinkExtractor.normalize passes through http/https URLs
        let normalized = IncomingLinkExtractor.normalize(targetURL)
        XCTAssertEqual(normalized?.absoluteString, targetURL.absoluteString)
    }

    func testHTTPPassthroughMatchesHandoff() {
        let normalized = IncomingLinkExtractor.normalize(targetURL)
        let handoffRequest = IncomingLinkRequest(
            url: targetURL,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(normalized?.absoluteString, handoffRequest.url.absoluteString,
                       "File-open normalized URL should match Handoff URL")
    }

    // MARK: - Force flags default to false across all origins

    func testDefaultForceFlags() {
        let origins: [IngressOrigin] = [
            .defaultHandler, .handoff, .airdrop, .shareExtension,
            .safariExtension, .chromeExtension, .firefoxExtension,
            .servicesMenu, .urlScheme, .intent, .fileOpen, .clipboard,
        ]
        for origin in origins {
            let request = IncomingLinkRequest(
                url: targetURL,
                origin: origin
            )
            XCTAssertFalse(request.forcePicker,
                          "forcePicker should default to false for \(origin)")
            XCTAssertFalse(request.forcePrivateWindow,
                          "forcePrivateWindow should default to false for \(origin)")
            XCTAssertNil(request.forcedBrowserBundleId,
                        "forcedBrowserBundleId should default to nil for \(origin)")
        }
    }

    // MARK: - yojam:// with force flags

    func testYojamSchemeForceFlags() {
        guard let yojamURL = YojamCommand.buildRoute(
            target: targetURL,
            browser: "com.google.Chrome",
            pick: true,
            privateWindow: true
        ),
        let command = YojamCommand.parse(yojamURL),
        case .route(let request) = command else {
            XCTFail("Should parse with flags")
            return
        }

        XCTAssertTrue(request.forcePicker)
        XCTAssertTrue(request.forcePrivateWindow)
        XCTAssertEqual(request.forcedBrowserBundleId, "com.google.Chrome")
    }

    // MARK: - Mailto parity

    func testMailtoPreservedAcrossOrigins() {
        let mailtoURL = URL(string: "mailto:test@example.com?subject=Hello")!
        let origins: [IngressOrigin] = [
            .defaultHandler, .servicesMenu, .urlScheme, .intent,
        ]
        for origin in origins {
            let request = IncomingLinkRequest(
                url: mailtoURL,
                origin: origin
            )
            XCTAssertEqual(request.url.scheme, "mailto",
                          "mailto should be preserved for \(origin)")
            XCTAssertEqual(request.url.absoluteString, mailtoURL.absoluteString,
                          "Full mailto URL should be preserved for \(origin)")
        }
    }

    func testMailtoThroughYojamScheme() {
        let mailtoURL = URL(string: "mailto:test@example.com")!
        guard let yojamURL = YojamCommand.buildRoute(target: mailtoURL),
              let command = YojamCommand.parse(yojamURL),
              case .route(let request) = command else {
            XCTFail("Should handle mailto through yojam://")
            return
        }
        XCTAssertEqual(request.url.scheme, "mailto")
    }
}
