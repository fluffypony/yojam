import Foundation

/// Bundle identifiers owned by Yojam. Used to filter these out of
/// browser/email client detection so they never appear as routable targets.
public enum YojamBundleIDs {
    public static let mainApp           = "com.yojam.app"
    public static let shareExtension    = "com.yojam.app.ShareExtension"
    public static let safariExtension   = "com.yojam.app.SafariExtension"
    public static let nativeHost        = "com.yojam.app.NativeHost"

    public static let all: Set<String> = [
        mainApp, shareExtension, safariExtension, nativeHost
    ]

    /// Returns true if the given bundle ID belongs to a Yojam component.
    public static func isOwnedByYojam(_ bundleId: String) -> Bool {
        all.contains(bundleId)
    }
}
