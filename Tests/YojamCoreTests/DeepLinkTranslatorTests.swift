import XCTest
@testable import YojamCore

final class DeepLinkTranslatorTests: XCTestCase {
    private let discord = "com.hnc.Discord"

    private func translate(_ string: String, target: String = "com.hnc.Discord") -> String {
        DeepLinkTranslator.translate(URL(string: string)!, targetBundleId: target).absoluteString
    }

    func testGuildMessageLinkBecomesDiscordScheme() {
        XCTAssertEqual(
            translate("https://discord.com/channels/123456/789012/345678"),
            "discord://-/channels/123456/789012/345678")
    }

    func testChannelLinkWithoutMessageBecomesDiscordScheme() {
        XCTAssertEqual(
            translate("https://discord.com/channels/123456/789012"),
            "discord://-/channels/123456/789012")
    }

    func testDirectMessageLinkKeepsAtMeSegment() {
        XCTAssertEqual(
            translate("https://discord.com/channels/@me/789012/345678"),
            "discord://-/channels/@me/789012/345678")
    }

    func testInviteLinkOnDiscordCom() {
        XCTAssertEqual(
            translate("https://discord.com/invite/yojam"),
            "discord://-/invite/yojam")
    }

    func testDiscordGGShorthandBecomesInviteRoute() {
        XCTAssertEqual(translate("https://discord.gg/yojam"), "discord://-/invite/yojam")
        XCTAssertEqual(translate("https://www.discord.gg/yojam"), "discord://-/invite/yojam")
    }

    func testDiscordGGWithoutCodeIsLeftAlone() {
        XCTAssertEqual(translate("https://discord.gg/"), "https://discord.gg/")
        XCTAssertEqual(translate("https://discord.gg"), "https://discord.gg")
    }

    func testAlternateDiscordHostsAreTranslated() {
        XCTAssertEqual(
            translate("https://canary.discord.com/channels/1/2/3"),
            "discord://-/channels/1/2/3")
        XCTAssertEqual(
            translate("https://ptb.discord.com/channels/1/2"),
            "discord://-/channels/1/2")
        XCTAssertEqual(
            translate("https://www.discordapp.com/users/42"),
            "discord://-/users/42")
    }

    func testQueryAndFragmentSurvive() {
        XCTAssertEqual(
            translate("https://discord.com/events/1/2?event=3#top"),
            "discord://-/events/1/2?event=3#top")
    }

    func testRootLinkOpensDiscordHome() {
        XCTAssertEqual(translate("https://discord.com/"), "discord://-/")
        XCTAssertEqual(translate("https://discord.com"), "discord://-/")
    }

    func testPTBAndCanaryAppsAlsoGetDeepLinks() {
        XCTAssertEqual(
            translate("https://discord.com/channels/1/2", target: "com.hnc.DiscordPTB"),
            "discord://-/channels/1/2")
        XCTAssertEqual(
            translate("https://discord.com/channels/1/2", target: "com.hnc.DiscordCanary"),
            "discord://-/channels/1/2")
    }

    func testBrowsersReceiveTheWebLinkUntouched() {
        let link = "https://discord.com/channels/1/2/3"
        XCTAssertEqual(translate(link, target: "com.google.Chrome"), link)
        XCTAssertEqual(translate(link, target: "com.apple.Safari"), link)
    }

    func testOtherHostsSentToDiscordAreUntouched() {
        let link = "https://example.com/discord.com/channels/1"
        XCTAssertEqual(translate(link), link)
    }

    func testNonWebSchemesAreUntouched() {
        XCTAssertEqual(translate("mailto:hi@discord.com"), "mailto:hi@discord.com")
        XCTAssertEqual(translate("discord://-/channels/1/2"), "discord://-/channels/1/2")
    }

    func testTranslatesReportsWhetherTheAppSeesADifferentURL() {
        let channel = URL(string: "https://discord.com/channels/1/2")!
        XCTAssertTrue(DeepLinkTranslator.translates(channel, targetBundleId: discord))
        XCTAssertFalse(DeepLinkTranslator.translates(channel, targetBundleId: "com.google.Chrome"))
        XCTAssertFalse(DeepLinkTranslator.translates(
            URL(string: "https://example.com")!, targetBundleId: discord))
    }
}
