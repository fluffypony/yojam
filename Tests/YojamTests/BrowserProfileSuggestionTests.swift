import XCTest
@testable import Yojam
import YojamCore

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

    func testAutoDetectedFirefoxDefaultProfileSelectionIsCleared() {
        let entry = BrowserEntry(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            profileId: "default",
            profileName: "default",
            source: .autoDetected)

        let cleaned = BrowserManager.clearingDefaultProfileSelectionIfNeeded(entry)

        XCTAssertNil(cleaned.profileId)
        XCTAssertNil(cleaned.profileName)
    }

    func testManualFirefoxDefaultProfileSelectionIsPreserved() {
        let entry = BrowserEntry(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            profileId: "default",
            profileName: "default",
            source: .manual)

        let cleaned = BrowserManager.clearingDefaultProfileSelectionIfNeeded(entry)

        XCTAssertEqual(cleaned.profileId, "default")
        XCTAssertEqual(cleaned.profileName, "default")
    }

    func testNamedFirefoxProfileSelectionIsPreserved() {
        let entry = BrowserEntry(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            profileId: "Work",
            profileName: "Work",
            source: .suggested)

        let cleaned = BrowserManager.clearingDefaultProfileSelectionIfNeeded(entry)

        XCTAssertEqual(cleaned.profileId, "Work")
        XCTAssertEqual(cleaned.profileName, "Work")
    }
}
