import XCTest
@testable import Yojam

final class CustomLaunchArgumentsTests: XCTestCase {
    @MainActor
    func testCustomLaunchArgsAppendURLWhenTemplateOmitsPlaceholder() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "--profile \"$HOME/Library/Application Support/Firefox/Profiles/abc123.Profile 1\"",
            url: url,
            profile: nil,
            bundleId: "org.mozilla.firefox",
            privateWindow: false)

        XCTAssertEqual(args.last, url.absoluteString)
        XCTAssertEqual(args[0], "--profile")
        XCTAssertTrue(args[1].hasSuffix(
            "/Library/Application Support/Firefox/Profiles/abc123.Profile 1"))
    }

    @MainActor
    func testCustomLaunchArgsDoNotAppendURLWhenTemplateContainsPlaceholder() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "--new-window $URL",
            url: url,
            profile: nil,
            bundleId: "org.mozilla.firefox",
            privateWindow: false)

        XCTAssertEqual(args, ["--new-window", url.absoluteString])
    }
}
