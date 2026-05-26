import XCTest
@testable import Yojam

final class BrowserProfileSuggestionTests: XCTestCase {
    func testDefaultProfilesAreNotSuggestedAsSeparateBrowsers() {
        XCTAssertFalse(BrowserManager.shouldSuggestProfile(BrowserProfile(
            id: "Default",
            name: "Default",
            browserBundleId: "com.google.Chrome",
            isDefault: true)))

        XCTAssertFalse(BrowserManager.shouldSuggestProfile(BrowserProfile(
            id: "default-release",
            name: "default-release",
            browserBundleId: "org.mozilla.firefox",
            isDefault: false)))

        XCTAssertFalse(BrowserManager.shouldSuggestProfile(BrowserProfile(
            id: "dev-edition-default",
            name: "dev-edition-default",
            browserBundleId: "org.mozilla.firefox",
            isDefault: false)))
    }

    func testNamedFirefoxProfileIsSuggested() {
        XCTAssertTrue(BrowserManager.shouldSuggestProfile(BrowserProfile(
            id: "Work",
            name: "Work",
            browserBundleId: "org.mozilla.firefox",
            isDefault: false)))
    }
}
