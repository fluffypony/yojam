import XCTest
@testable import YojamCore

final class YojamCommandTests: XCTestCase {
    func testParseRouteWithURL() {
        let url = URL(string: "yojam://route?url=https%3A%2F%2Fexample.com%2Fpage")!
        guard let command = YojamCommand.parse(url) else {
            XCTFail("Should parse valid route command")
            return
        }
        if case .route(let request) = command {
            XCTAssertEqual(request.url.absoluteString, "https://example.com/page")
            XCTAssertEqual(request.origin, .urlScheme)
            XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.urlScheme)
        } else {
            XCTFail("Expected .route command")
        }
    }

    func testParseRouteWithSource() {
        let url = URL(string: "yojam://route?url=https%3A%2F%2Fexample.com&source=com.yojam.source.share-extension")!
        guard let command = YojamCommand.parse(url) else {
            XCTFail("Should parse valid route command")
            return
        }
        if case .route(let request) = command {
            XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.shareExtension)
        } else {
            XCTFail("Expected .route command")
        }
    }

    func testParseRouteWithBrowserAndFlags() {
        let url = URL(string: "yojam://route?url=https%3A%2F%2Fexample.com&browser=com.google.Chrome&pick=1&private=1")!
        guard let command = YojamCommand.parse(url) else {
            XCTFail("Should parse valid route command with flags")
            return
        }
        if case .route(let request) = command {
            XCTAssertEqual(request.forcedBrowserBundleId, "com.google.Chrome")
            XCTAssertTrue(request.forcePicker)
            XCTAssertTrue(request.forcePrivateWindow)
        } else {
            XCTFail("Expected .route command")
        }
    }

    func testParseOpenAlias() {
        let url = URL(string: "yojam://open?url=https%3A%2F%2Fexample.com")!
        guard let command = YojamCommand.parse(url) else {
            XCTFail("Should parse 'open' as alias for 'route'")
            return
        }
        if case .route(let request) = command {
            XCTAssertEqual(request.url.absoluteString, "https://example.com")
        } else {
            XCTFail("Expected .route command")
        }
    }

    func testParseSettings() {
        let url = URL(string: "yojam://settings")!
        guard let command = YojamCommand.parse(url) else {
            XCTFail("Should parse settings command")
            return
        }
        if case .openSettings = command {
            // pass
        } else {
            XCTFail("Expected .openSettings command")
        }
    }

    func testRejectsRecursiveYojamURL() {
        let url = URL(string: "yojam://route?url=yojam%3A%2F%2Froute%3Furl%3Dhttps%253A%252F%252Fexample.com")!
        XCTAssertNil(YojamCommand.parse(url), "Should reject recursive yojam:// URLs")
    }

    func testRejectsNonHTTPTarget() {
        let url = URL(string: "yojam://route?url=ftp%3A%2F%2Ffiles.example.com%2Ffile.txt")!
        XCTAssertNil(YojamCommand.parse(url), "Should reject non-http target URLs")
    }

    func testRejectsMissingURL() {
        let url = URL(string: "yojam://route?source=com.test")!
        XCTAssertNil(YojamCommand.parse(url), "Should reject route without url parameter")
    }

    func testRejectsNonYojamScheme() {
        let url = URL(string: "https://example.com")!
        XCTAssertNil(YojamCommand.parse(url), "Should reject non-yojam:// URLs")
    }

    func testRejectsUnknownHost() {
        let url = URL(string: "yojam://unknown?url=https%3A%2F%2Fexample.com")!
        XCTAssertNil(YojamCommand.parse(url), "Should reject unknown command hosts")
    }

    func testBuildRoute() {
        let target = URL(string: "https://example.com/page?q=1")!
        let result = YojamCommand.buildRoute(
            target: target,
            source: SourceAppSentinel.shareExtension
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.scheme, "yojam")
        XCTAssertEqual(result?.host, "route")

        // Round-trip: parse the built URL
        if let builtURL = result, let command = YojamCommand.parse(builtURL) {
            if case .route(let request) = command {
                XCTAssertEqual(request.url.absoluteString, "https://example.com/page?q=1")
                XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.shareExtension)
            } else {
                XCTFail("Expected .route from round-trip")
            }
        }
    }

    func testBuildRouteWithAllFlags() {
        let target = URL(string: "https://example.com")!
        let result = YojamCommand.buildRoute(
            target: target,
            source: "com.test",
            browser: "com.google.Chrome",
            pick: true,
            privateWindow: true
        )
        XCTAssertNotNil(result)

        if let builtURL = result, let command = YojamCommand.parse(builtURL) {
            if case .route(let request) = command {
                XCTAssertEqual(request.forcedBrowserBundleId, "com.google.Chrome")
                XCTAssertTrue(request.forcePicker)
                XCTAssertTrue(request.forcePrivateWindow)
            } else {
                XCTFail("Expected .route")
            }
        }
    }

    func testMailtoTarget() {
        let url = URL(string: "yojam://route?url=mailto%3Atest%40example.com")!
        guard let command = YojamCommand.parse(url) else {
            XCTFail("Should parse mailto target")
            return
        }
        if case .route(let request) = command {
            XCTAssertEqual(request.url.scheme, "mailto")
        } else {
            XCTFail("Expected .route command")
        }
    }
}
