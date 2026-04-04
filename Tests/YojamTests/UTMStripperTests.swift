import XCTest
@testable import Yojam

final class UTMStripperTests: XCTestCase {
    @MainActor
    func testStripsUTM() {
        let store = SettingsStore()
        let stripper = UTMStripper(settingsStore: store)
        let url = URL(string:
            "https://example.com/page?utm_source=twitter&utm_medium=social&id=42")!
        XCTAssertEqual(
            stripper.strip(url).absoluteString,
            "https://example.com/page?id=42")
    }

    @MainActor
    func testRemovesAllQueryWhenAllStripped() {
        let store = SettingsStore()
        let stripper = UTMStripper(settingsStore: store)
        let url = URL(string:
            "https://example.com/page?utm_source=twitter&fbclid=abc")!
        XCTAssertEqual(
            stripper.strip(url).absoluteString,
            "https://example.com/page")
    }

    @MainActor
    func testPreservesCleanURL() {
        let store = SettingsStore()
        let stripper = UTMStripper(settingsStore: store)
        let url = URL(string: "https://example.com/page?id=42&name=test")!
        XCTAssertEqual(
            stripper.strip(url).absoluteString, url.absoluteString)
    }

    @MainActor
    func testCaseInsensitiveStripping() {
        let store = SettingsStore()
        let stripper = UTMStripper(settingsStore: store)
        let url = URL(string:
            "https://example.com/page?UTM_SOURCE=twitter&UTM_Medium=social&id=42")!
        XCTAssertEqual(
            stripper.strip(url).absoluteString,
            "https://example.com/page?id=42")
    }

    @MainActor
    func testHandlesURLWithNoQuery() {
        let store = SettingsStore()
        let stripper = UTMStripper(settingsStore: store)
        let url = URL(string: "https://example.com/page")!
        XCTAssertEqual(
            stripper.strip(url).absoluteString, url.absoluteString)
    }

    @MainActor
    func testHandlesURLWithFragment() {
        let store = SettingsStore()
        let stripper = UTMStripper(settingsStore: store)
        let url = URL(string:
            "https://example.com/page?utm_source=x&id=1#section")!
        let result = stripper.strip(url)
        XCTAssertTrue(result.absoluteString.contains("id=1"))
        XCTAssertFalse(result.absoluteString.contains("utm_source"))
    }
}
