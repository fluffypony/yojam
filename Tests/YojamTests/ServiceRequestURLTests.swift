import AppKit
import XCTest
@testable import Yojam

final class ServiceRequestURLTests: XCTestCase {
    func testURLObjectsWinOverText() {
        let object = URL(string: "https://example.com/object")!
        let pasteboard = makePasteboard()
        let item = NSPasteboardItem()
        item.setString(object.absoluteString, forType: .URL)
        item.setString("https://example.com/text", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let urls = ServiceRequestURLExtractor.urls(from: pasteboard)
        XCTAssertEqual(urls, [object])
    }

    func testTextSelectionWithALinkIsRouted() {
        let pasteboard = makePasteboard()
        pasteboard.setString("https://example.com/services-test", forType: .string)
        let urls = ServiceRequestURLExtractor.urls(from: pasteboard)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/services-test"])
    }

    func testEveryLinkInSelectedTextIsRouted() {
        let urls = ServiceRequestURLExtractor.urls(
            in: "see https://one.example.com and https://two.example.com/path today")
        XCTAssertEqual(
            urls.map(\.absoluteString),
            ["https://one.example.com", "https://two.example.com/path"])
    }

    func testBareHostGetsHTTPS() {
        let urls = ServiceRequestURLExtractor.urls(in: " yoj.am ")
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.host, "yoj.am")
        XCTAssertTrue(urls.first?.scheme == "http" || urls.first?.scheme == "https")
    }

    func testPlainWordsProduceNothing() {
        XCTAssertTrue(ServiceRequestURLExtractor.urls(in: "hello world").isEmpty)
        XCTAssertTrue(ServiceRequestURLExtractor.urls(from: makePasteboard()).isEmpty)
    }

    func testSafariContextMenuRoutesTheHyperlinkBehindItsTitle() throws {
        // Captured from Safari's right-click Services request on macOS 26.6.2.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ServicesMenu/safari-context-link.rtf")
        let pasteboard = makePasteboard()
        pasteboard.setData(try Data(contentsOf: fixture), forType: .rtf)
        pasteboard.setString("Open the test target", forType: .string)

        XCTAssertTrue((pasteboard.readObjects(forClasses: [NSURL.self]) ?? []).isEmpty)
        XCTAssertEqual(ServiceRequestURLExtractor.urls(from: pasteboard).map(\.absoluteString), [
            "https://example.com/yojam-services-target"
        ])
    }

    func testHyperlinkDestinationWinsOverURLInItsLabel() throws {
        let richText = NSAttributedString(
            string: "https://label.example.com", attributes: [
                .link: URL(string: "https://destination.example.com")!
            ])
        let pasteboard = try makePasteboard(richText: richText)
        XCTAssertEqual(ServiceRequestURLExtractor.urls(from: pasteboard).map(\.absoluteString), [
            "https://destination.example.com"
        ])
    }

    func testRichSelectionIncludesHyperlinksAndPlainURLsInOrder() throws {
        let richText = NSMutableAttributedString(string: "See https://first.example.com, then ")
        richText.append(NSAttributedString(string: "文書 📄", attributes: [
            .link: "https://linked.example.com"
        ]))
        richText.append(NSAttributedString(string: " and https://last.example.com"))
        let pasteboard = try makePasteboard(richText: richText)
        XCTAssertEqual(ServiceRequestURLExtractor.urls(from: pasteboard).map(\.absoluteString), [
            "https://first.example.com", "https://linked.example.com", "https://last.example.com"
        ])
    }

    func testFormattedTextWithoutHyperlinksStillDetectsURLs() throws {
        let richText = NSAttributedString(string: "See https://example.com/plain", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14)
        ])
        XCTAssertEqual(
            ServiceRequestURLExtractor.urls(from: try makePasteboard(richText: richText))
                .map(\.absoluteString),
            ["https://example.com/plain"])
    }

    func testInvalidRTFDoesNotHidePlainText() {
        let pasteboard = makePasteboard()
        pasteboard.setData(Data([0, 1, 2]), forType: .rtf)
        pasteboard.setString("https://example.com/text", forType: .string)
        XCTAssertEqual(ServiceRequestURLExtractor.urls(from: pasteboard).map(\.absoluteString), [
            "https://example.com/text"
        ])
    }

    func testEveryPasteboardItemIsRead() {
        let pasteboard = makePasteboard()
        let items = ["https://first.example.com", "https://second.example.com"].map { text in
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            return item
        }
        XCTAssertTrue(pasteboard.writeObjects(items))
        XCTAssertEqual(ServiceRequestURLExtractor.urls(from: pasteboard).map(\.absoluteString), [
            "https://first.example.com", "https://second.example.com"
        ])
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        let name = pasteboard.name.rawValue
        addTeardownBlock { NSPasteboard(name: .init(name)).releaseGlobally() }
        return pasteboard
    }

    private func makePasteboard(richText: NSAttributedString) throws -> NSPasteboard {
        let pasteboard = makePasteboard()
        let data = try XCTUnwrap(richText.rtf(
            from: NSRange(location: 0, length: richText.length), documentAttributes: [:]))
        pasteboard.setData(data, forType: .rtf)
        pasteboard.setString(richText.string, forType: .string)
        return pasteboard
    }
}
