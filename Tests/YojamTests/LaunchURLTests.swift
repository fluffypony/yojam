import XCTest
@testable import Yojam
import YojamCore

/// The launcher hands Discord a `discord://` deep link while every other
/// target, and every untargeted launch, keeps the web URL.
final class LaunchURLTests: XCTestCase {
    private let channel = URL(string: "https://discord.com/channels/1/2/3")!

    func testDiscordTargetGetsDeepLink() {
        let launched = AppDelegate.launchURL(for: channel, targetBundleId: "com.hnc.Discord")
        XCTAssertEqual(launched.absoluteString, "discord://-/channels/1/2/3")
    }

    func testBrowserTargetKeepsWebLink() {
        XCTAssertEqual(
            AppDelegate.launchURL(for: channel, targetBundleId: "com.google.Chrome"), channel)
    }

    func testUnknownTargetKeepsWebLink() {
        XCTAssertEqual(AppDelegate.launchURL(for: channel, targetBundleId: nil), channel)
    }

    @MainActor
    func testBuiltInDiscordRulesCoverChannelsAndInvites() {
        let discordRules = BuiltInRules.all.filter { $0.targetBundleId == "com.hnc.Discord" }
        let links = [
            "https://discord.com/channels/123/456/789",
            "https://discord.com/channels/@me/456",
            "https://discord.com/invite/yojam",
            "https://discord.gg/yojam",
        ]
        for link in links {
            let url = URL(string: link)!
            XCTAssertTrue(
                discordRules.contains { RuleMatcher.evaluate(url: url, against: $0).matched },
                "No built-in Discord rule matches \(link)")
        }
        XCTAssertFalse(discordRules.contains {
            RuleMatcher.evaluate(
                url: URL(string: "https://discord.com/developers/docs")!, against: $0).matched
        })
    }

    @MainActor
    func testBuiltInRuleIdsAreUnique() {
        let ids = BuiltInRules.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Set(ids).isDisjoint(with: BuiltInRules.removedIds))
    }
}
