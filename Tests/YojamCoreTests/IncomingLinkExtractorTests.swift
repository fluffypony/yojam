import XCTest
@testable import YojamCore

final class IncomingLinkExtractorTests: XCTestCase {
    func testHTTPPassThrough() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertEqual(IncomingLinkExtractor.normalize(url)?.absoluteString, "https://example.com/page")
    }

    func testHTTPSPassThrough() {
        let url = URL(string: "http://example.com")!
        XCTAssertEqual(IncomingLinkExtractor.normalize(url)?.absoluteString, "http://example.com")
    }

    func testMailtoPassThrough() {
        let url = URL(string: "mailto:test@example.com")!
        XCTAssertEqual(IncomingLinkExtractor.normalize(url)?.absoluteString, "mailto:test@example.com")
    }

    func testLocalHTMLAllowed() {
        let url = URL(fileURLWithPath: "/tmp/test.html")
        let result = IncomingLinkExtractor.normalize(url)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/test.html")
    }

    func testLocalXHTMLAllowed() {
        let url = URL(fileURLWithPath: "/tmp/test.xhtml")
        let result = IncomingLinkExtractor.normalize(url)
        XCTAssertNotNil(result)
    }

    func testLocalHTMAllowed() {
        let url = URL(fileURLWithPath: "/tmp/test.htm")
        let result = IncomingLinkExtractor.normalize(url)
        XCTAssertNotNil(result)
    }

    func testArbitraryLocalFileRejected() {
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        XCTAssertNil(IncomingLinkExtractor.normalize(url))
    }

    func testUnknownExtensionRejected() {
        let url = URL(fileURLWithPath: "/tmp/test.zip")
        XCTAssertNil(IncomingLinkExtractor.normalize(url))
    }

    func testWeblocParsing() throws {
        // Create a temporary .webloc plist file
        let plist: [String: String] = ["URL": "https://example.com/from-webloc"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)

        let tempDir = FileManager.default.temporaryDirectory
        let weblocPath = tempDir.appendingPathComponent("test-\(UUID()).webloc")
        try data.write(to: weblocPath)
        defer { try? FileManager.default.removeItem(at: weblocPath) }

        let result = IncomingLinkExtractor.normalize(weblocPath)
        XCTAssertEqual(result?.absoluteString, "https://example.com/from-webloc")
    }

    func testWeblocWithFTPRejected() throws {
        let plist: [String: String] = ["URL": "ftp://files.example.com/file"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)

        let tempDir = FileManager.default.temporaryDirectory
        let weblocPath = tempDir.appendingPathComponent("test-ftp-\(UUID()).webloc")
        try data.write(to: weblocPath)
        defer { try? FileManager.default.removeItem(at: weblocPath) }

        XCTAssertNil(IncomingLinkExtractor.normalize(weblocPath))
    }

    func testWindowsURLShortcutParsing() throws {
        let content = """
        [InternetShortcut]
        URL=https://example.com/from-url-file
        IconIndex=0
        """
        let tempDir = FileManager.default.temporaryDirectory
        let urlPath = tempDir.appendingPathComponent("test-\(UUID()).url")
        try content.write(to: urlPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: urlPath) }

        let result = IncomingLinkExtractor.normalize(urlPath)
        XCTAssertEqual(result?.absoluteString, "https://example.com/from-url-file")
    }

    func testWindowsURLShortcutWithFTPRejected() throws {
        let content = """
        [InternetShortcut]
        URL=ftp://files.example.com/file
        """
        let tempDir = FileManager.default.temporaryDirectory
        let urlPath = tempDir.appendingPathComponent("test-ftp-\(UUID()).url")
        try content.write(to: urlPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: urlPath) }

        XCTAssertNil(IncomingLinkExtractor.normalize(urlPath))
    }

    func testMalformedWeblocRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let weblocPath = tempDir.appendingPathComponent("bad-\(UUID()).webloc")
        try "this is not a plist".write(to: weblocPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: weblocPath) }

        XCTAssertNil(IncomingLinkExtractor.normalize(weblocPath))
    }

    func testOversizeWeblocRejected() throws {
        // Create a file larger than 64KB
        let tempDir = FileManager.default.temporaryDirectory
        let weblocPath = tempDir.appendingPathComponent("big-\(UUID()).webloc")
        let bigData = Data(repeating: 0x41, count: 70_000)
        try bigData.write(to: weblocPath)
        defer { try? FileManager.default.removeItem(at: weblocPath) }

        XCTAssertNil(IncomingLinkExtractor.normalize(weblocPath))
    }
}
