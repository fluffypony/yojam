import XCTest
@testable import Yojam

/// "Open in Yojam" from the Services menu hands over either URL objects or
/// the selected text. Text selections arrive with an empty URL-object array,
/// which older releases mistook for "nothing to open".
final class ServiceRequestURLTests: XCTestCase {
    func testURLObjectsWinOverText() {
        let object = URL(string: "https://example.com/object")!
        let urls = AppDelegate.serviceRequestURLs(
            urlObjects: [object], text: "https://example.com/text")
        XCTAssertEqual(urls, [object])
    }

    func testTextSelectionWithALinkIsRouted() {
        let urls = AppDelegate.serviceRequestURLs(
            urlObjects: [], text: "https://example.com/services-test")
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/services-test"])
    }

    func testEveryLinkInSelectedTextIsRouted() {
        let urls = AppDelegate.serviceRequestURLs(
            urlObjects: [],
            text: "see https://one.example.com and https://two.example.com/path today")
        XCTAssertEqual(
            urls.map(\.absoluteString),
            ["https://one.example.com", "https://two.example.com/path"])
    }

    func testBareHostGetsHTTPS() {
        let urls = AppDelegate.serviceRequestURLs(urlObjects: [], text: " yoj.am ")
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.host, "yoj.am")
        XCTAssertTrue(urls.first?.scheme == "http" || urls.first?.scheme == "https")
    }

    func testPlainWordsProduceNothing() {
        XCTAssertTrue(AppDelegate.serviceRequestURLs(urlObjects: [], text: "hello world").isEmpty)
        XCTAssertTrue(AppDelegate.serviceRequestURLs(urlObjects: [], text: nil).isEmpty)
    }
}
