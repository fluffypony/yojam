import Foundation

/// Sentinel bundle identifiers used as `sourceAppBundleId` for ingress paths
/// that have no real originating app. Rules can target these explicitly.
///
/// For example, a user can write a rule like:
///   Source App = "com.yojam.source.handoff" → always open in Work profile
public enum SourceAppSentinel {
    public static let handoff          = "com.yojam.source.handoff"
    public static let airdrop          = "com.yojam.source.airdrop"
    public static let shareExtension   = "com.yojam.source.share-extension"
    public static let servicesMenu     = "com.yojam.source.service"
    public static let safariExtension  = "com.yojam.source.safari-extension"
    public static let chromeExtension  = "com.yojam.source.chrome-extension"
    public static let firefoxExtension = "com.yojam.source.firefox-extension"
    public static let urlScheme        = "com.yojam.source.url-scheme"
    public static let cli              = "com.yojam.source.cli"

    /// All sentinel values, for display in the Rules UI help text.
    public static let all: [String] = [
        handoff, airdrop, shareExtension, servicesMenu,
        safariExtension, chromeExtension, firefoxExtension,
        urlScheme, cli
    ]
}
