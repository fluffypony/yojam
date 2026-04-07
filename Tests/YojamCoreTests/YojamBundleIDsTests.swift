import XCTest
@testable import YojamCore

final class YojamBundleIDsTests: XCTestCase {
    func testMainAppIsOwned() {
        XCTAssertTrue(YojamBundleIDs.isOwnedByYojam("com.yojam.app"))
    }

    func testShareExtensionIsOwned() {
        XCTAssertTrue(YojamBundleIDs.isOwnedByYojam("com.yojam.app.ShareExtension"))
    }

    func testSafariExtensionIsOwned() {
        XCTAssertTrue(YojamBundleIDs.isOwnedByYojam("com.yojam.app.SafariExtension"))
    }

    func testNativeHostIsOwned() {
        XCTAssertTrue(YojamBundleIDs.isOwnedByYojam("com.yojam.app.NativeHost"))
    }

    func testThirdPartyBrowserIsNotOwned() {
        XCTAssertFalse(YojamBundleIDs.isOwnedByYojam("com.google.Chrome"))
        XCTAssertFalse(YojamBundleIDs.isOwnedByYojam("org.mozilla.firefox"))
        XCTAssertFalse(YojamBundleIDs.isOwnedByYojam("com.apple.Safari"))
    }

    func testAllContainsFourEntries() {
        XCTAssertEqual(YojamBundleIDs.all.count, 4)
    }
}
