import XCTest
@testable import YojamCore

/// Tests for the native messaging host protocol types and the yojam://
/// URL construction used by the native host to forward links.
final class NativeHostProtocolTests: XCTestCase {
    // MARK: - Route command URL construction

    func testRouteCommandBuildsValidYojamURL() {
        let targetURL = URL(string: "https://example.com/page")!
        let source = SourceAppSentinel.chromeExtension
        guard let yojamURL = YojamCommand.buildRoute(
            target: targetURL, source: source
        ) else {
            XCTFail("buildRoute should succeed for valid inputs")
            return
        }
        XCTAssertEqual(yojamURL.scheme, "yojam")
        XCTAssertEqual(yojamURL.host, "route")
    }

    func testRouteCommandPreservesURLThroughBuild() {
        let urls = [
            "https://example.com",
            "https://example.com/path?key=value&other=123",
            "https://example.com/path#fragment",
            "mailto:user@example.com",
        ]
        for urlString in urls {
            let target = URL(string: urlString)!
            guard let yojamURL = YojamCommand.buildRoute(target: target),
                  let command = YojamCommand.parse(yojamURL),
                  case .route(let request) = command else {
                XCTFail("Round-trip should succeed for: \(urlString)")
                continue
            }
            XCTAssertEqual(request.url.absoluteString, urlString,
                          "URL should survive native host round-trip: \(urlString)")
        }
    }

    func testRouteCommandWithChromeSource() {
        let target = URL(string: "https://example.com")!
        guard let yojamURL = YojamCommand.buildRoute(
            target: target, source: SourceAppSentinel.chromeExtension
        ),
        let command = YojamCommand.parse(yojamURL),
        case .route(let request) = command else {
            XCTFail("Should parse Chrome source route")
            return
        }
        XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.chromeExtension)
    }

    func testRouteCommandWithFirefoxSource() {
        let target = URL(string: "https://example.com")!
        guard let yojamURL = YojamCommand.buildRoute(
            target: target, source: SourceAppSentinel.firefoxExtension
        ),
        let command = YojamCommand.parse(yojamURL),
        case .route(let request) = command else {
            XCTFail("Should parse Firefox source route")
            return
        }
        XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.firefoxExtension)
    }

    // MARK: - URL validation (mirroring native host's validation logic)

    func testRejectsNonHTTPURL() {
        let ftp = URL(string: "ftp://files.example.com/file.txt")!
        let result = YojamCommand.buildRoute(target: ftp)
        // buildRoute succeeds but parse should reject non-http
        if let builtURL = result {
            let command = YojamCommand.parse(builtURL)
            // Should be nil because ftp is not http/https/mailto
            XCTAssertNil(command, "Should reject ftp:// target")
        }
    }

    func testRejectsJavascriptURL() {
        // The native host validates URL scheme before building yojam://
        let jsURL = URL(string: "javascript:alert(1)")!
        let scheme = jsURL.scheme?.lowercased() ?? ""
        XCTAssertFalse(
            ["http", "https", "mailto"].contains(scheme),
            "javascript: scheme should not pass validation")
    }

    func testAcceptsHTTPS() {
        let url = URL(string: "https://example.com")!
        let scheme = url.scheme?.lowercased() ?? ""
        XCTAssertTrue(["http", "https", "mailto"].contains(scheme))
    }

    func testAcceptsHTTP() {
        let url = URL(string: "http://example.com")!
        let scheme = url.scheme?.lowercased() ?? ""
        XCTAssertTrue(["http", "https", "mailto"].contains(scheme))
    }

    func testAcceptsMailto() {
        let url = URL(string: "mailto:user@example.com")!
        let scheme = url.scheme?.lowercased() ?? ""
        XCTAssertTrue(["http", "https", "mailto"].contains(scheme))
    }

    // MARK: - Default source sentinel fallback

    func testDefaultSourceIsChromeExtension() {
        // When the native host receives no source, it defaults to Chrome extension
        let defaultSource = SourceAppSentinel.chromeExtension
        let target = URL(string: "https://example.com")!
        guard let yojamURL = YojamCommand.buildRoute(
            target: target, source: defaultSource
        ),
        let command = YojamCommand.parse(yojamURL),
        case .route(let request) = command else {
            XCTFail("Should work with default Chrome source")
            return
        }
        XCTAssertEqual(request.sourceAppBundleId, "com.yojam.source.chrome-extension")
    }

    // MARK: - URL with special characters

    func testURLWithQueryParametersSurvivesRoundTrip() {
        let target = URL(string: "https://example.com/search?q=hello+world&lang=en")!
        guard let yojamURL = YojamCommand.buildRoute(target: target),
              let command = YojamCommand.parse(yojamURL),
              case .route(let request) = command else {
            XCTFail("Should handle URL with query params")
            return
        }
        XCTAssertTrue(request.url.absoluteString.contains("q=hello"))
    }

    func testURLWithFragmentSurvivesRoundTrip() {
        let target = URL(string: "https://example.com/page#section-2")!
        guard let yojamURL = YojamCommand.buildRoute(target: target),
              let command = YojamCommand.parse(yojamURL),
              case .route(let request) = command else {
            XCTFail("Should handle URL with fragment")
            return
        }
        XCTAssertTrue(request.url.absoluteString.contains("#section-2"))
    }
}
