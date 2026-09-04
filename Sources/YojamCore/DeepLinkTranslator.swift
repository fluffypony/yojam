import Foundation

/// Rewrites a web link into an app's own URL scheme when that app ignores
/// plain `https` links handed to it by Launch Services.
///
/// Discord is the known case. Its desktop app activates when it receives
/// `https://discord.com/channels/…` but never navigates, because its
/// `open-url` handler only acts on the `discord://` scheme. That scheme
/// mirrors the web paths under the `-` placeholder host, so
/// `discord://-/channels/<guild>/<channel>/<message>` lands on the message.
///
/// Translation happens at launch time only. Routing decisions, Link History,
/// and the URL tester keep the original web link.
public enum DeepLinkTranslator {
    /// Returns the URL Yojam should hand to the app identified by
    /// `targetBundleId`. Unchanged when no translation applies.
    public static func translate(_ url: URL, targetBundleId: String) -> URL {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return url }
        if isDiscord(targetBundleId) {
            return discordDeepLink(for: url) ?? url
        }
        return url
    }

    /// True when the app receives a different URL than the web link.
    public static func translates(_ url: URL, targetBundleId: String) -> Bool {
        translate(url, targetBundleId: targetBundleId) != url
    }

    // MARK: - Discord

    static let discordBundleIdentifiers: Set<String> = [
        "com.hnc.Discord",
        "com.hnc.DiscordPTB",
        "com.hnc.DiscordCanary",
    ]

    private static let discordWebHosts: Set<String> = [
        "discord.com", "www.discord.com",
        "ptb.discord.com", "canary.discord.com",
        "discordapp.com", "www.discordapp.com",
    ]

    private static let discordInviteHosts: Set<String> = [
        "discord.gg", "www.discord.gg",
    ]

    static func isDiscord(_ bundleId: String) -> Bool {
        discordBundleIdentifiers.contains(bundleId)
    }

    static func discordDeepLink(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let path: String
        if discordWebHosts.contains(host) {
            path = components.percentEncodedPath
        } else if discordInviteHosts.contains(host) {
            // discord.gg/<code> is shorthand for discord.com/invite/<code>.
            let code = components.percentEncodedPath
            guard code.count > 1 else { return nil }
            path = "/invite" + code
        } else {
            return nil
        }

        components.scheme = "discord"
        components.host = "-"
        components.port = nil
        components.user = nil
        components.password = nil
        components.percentEncodedPath = path.isEmpty ? "/" : path
        return components.url
    }
}
