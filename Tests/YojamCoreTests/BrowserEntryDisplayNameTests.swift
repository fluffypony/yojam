import XCTest
@testable import YojamCore

final class BrowserEntryDisplayNameTests: XCTestCase {
    func testDefaultProfileNamesRenderAsReadableLabels() {
        XCTAssertEqual(
            BrowserEntry(
                bundleIdentifier: "org.mozilla.firefox",
                displayName: "Firefox",
                profileId: "default-release",
                profileName: "default-release"
            ).fullDisplayName,
            "Firefox — Default Release Profile")

        XCTAssertEqual(
            BrowserEntry(
                bundleIdentifier: "org.mozilla.firefoxdeveloperedition",
                displayName: "Firefox Developer Edition",
                profileId: "dev-edition-default",
                profileName: "dev-edition-default"
            ).fullDisplayName,
            "Firefox Developer Edition — Developer Edition Default Profile")
    }

    func testNamedProfileStillUsesUserVisibleName() {
        let entry = BrowserEntry(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            profileId: "Work",
            profileName: "Work")

        XCTAssertEqual(entry.fullDisplayName, "Firefox — Work")
    }
}
