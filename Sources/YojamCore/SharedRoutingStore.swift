import Foundation

/// Shared storage for all routing-relevant state, backed by the App Group
/// `UserDefaults(suiteName: "group.org.yojam.shared")`.
///
/// This store is readable by the main app, the Share Extension, the Safari
/// Web Extension handler, and the Native Messaging Host. The main app is
/// the only writer; extensions and the host read from it.
///
/// Per the hard-cut product policy: there is no migration from
/// `UserDefaults.standard`. Users upgrading from a pre-release build
/// must reconfigure from Preferences.
@MainActor
public final class SharedRoutingStore: ObservableObject {
    public static let suiteName = "group.org.yojam.shared"

    public let defaults: UserDefaults

    public init() {
        guard let suite = UserDefaults(suiteName: SharedRoutingStore.suiteName) else {
            // Fall back to standard if App Group is not available (e.g. during
            // swift test or when entitlements are not configured).
            self.defaults = UserDefaults.standard
            return
        }
        self.defaults = suite
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
    }
}
