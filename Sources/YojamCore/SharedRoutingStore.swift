import Foundation
import os

/// Shared storage for all routing-relevant state, backed by the App Group
/// `UserDefaults(suiteName: "group.org.yojam.shared")`.
///
/// This store is readable by the main app, the Share Extension, the Safari
/// Web Extension handler, and the Native Messaging Host. The main app is
/// the only writer; extensions and the host read from it.
///
/// `UserDefaults` is thread-safe, so no actor isolation is needed.
/// This class can be used from any isolation domain (CLI, native host, etc.).
///
/// Per the hard-cut product policy: there is no migration from
/// `UserDefaults.standard`. Users upgrading from a pre-release build
/// must reconfigure from Preferences.
public final class SharedRoutingStore: ObservableObject, @unchecked Sendable {
    public static let suiteName = "group.org.yojam.shared"

    public let defaults: UserDefaults

    /// Whether the App Group suite was successfully opened.
    /// False means we fell back to .standard (only expected during swift test).
    public let isUsingAppGroup: Bool

    /// - Parameter requireAppGroup: When `true`, crashes if the App Group
    ///   entitlement is missing. Use `true` in signed binaries (native host,
    ///   CLI) and `false` only in test/unsigned builds.
    public init(requireAppGroup: Bool = false) {
        if let suite = UserDefaults(suiteName: SharedRoutingStore.suiteName) {
            self.defaults = suite
            self.isUsingAppGroup = true
        } else {
            if requireAppGroup {
                fatalError("SharedRoutingStore: App Group '\(SharedRoutingStore.suiteName)' unavailable — check entitlements")
            }
            os_log(.error, "SharedRoutingStore: App Group unavailable, falling back to .standard (test-only)")
            self.defaults = UserDefaults.standard
            self.isUsingAppGroup = false
        }
    }

    // MARK: - Keys

    public enum Keys {
        public static let browsers = "browsers"
        public static let emailClients = "emailClients"
        public static let rules = "rules"
        public static let globalRewriteRules = "globalRewriteRules"
        public static let utmStripList = "utmStripList"
        public static let activationMode = "activationMode"
        public static let defaultSelection = "defaultSelection"
        public static let globalUTMStripping = "globalUTMStripping"
        public static let isEnabled = "isEnabled"
        public static let learnedDomainPreferences = "learnedDomainPreferences"
        public static let recentURLs = "recentURLs"
        public static let recentURLTimestamps = "recentURLTimestamps"
        public static let verticalThreshold = "verticalThreshold"
        public static let soundEffects = "soundEffects"
        public static let shortlinkResolutionEnabled = "shortlinkResolutionEnabled"
        public static let lastUsedBrowserId = "lastUsedBrowserId"
        public static let lastUsedEmailId = "lastUsedEmailId"
        public static let installedBundleIds = "installedBundleIds"
    }
}
