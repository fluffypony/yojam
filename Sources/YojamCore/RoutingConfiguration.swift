import Foundation

/// A snapshot of all routing-relevant state needed by `RoutingService.decide()`.
/// Built by the main app from its live subsystems before each routing decision.
public struct RoutingConfiguration: Sendable {
    /// Enabled, installed browsers in display order.
    public let browsers: [BrowserEntry]
    /// Enabled, installed email clients in display order.
    public let emailClients: [BrowserEntry]
    /// Enabled rules sorted by priority (user rules first, then built-in).
    /// Caller should pre-filter for rules whose targets are installed.
    public let rules: [Rule]
    /// Enabled global rewrite rules.
    public let globalRewriteRules: [URLRewriteRule]
    /// Lowercased UTM parameter names to strip.
    public let utmStripParameters: Set<String>
    /// Whether global UTM stripping is enabled.
    public let globalUTMStrippingEnabled: Bool
    /// Current activation mode.
    public let activationMode: ActivationMode
    /// How to pick the default selection in the picker.
    public let defaultSelectionBehavior: DefaultSelectionBehavior
    /// Whether Yojam routing is enabled at all.
    public let isEnabled: Bool
    /// Learned domain → entry UUID string mapping from RoutingSuggestionEngine.
    public let learnedDomainPreferences: [String: String]
    /// UUID of the last-used browser (for lastUsed selection behavior).
    public let lastUsedBrowserId: UUID?
    /// UUID of the last-used email client.
    public let lastUsedEmailClientId: UUID?

    public init(
        browsers: [BrowserEntry],
        emailClients: [BrowserEntry],
        rules: [Rule],
        globalRewriteRules: [URLRewriteRule],
        utmStripParameters: Set<String>,
        globalUTMStrippingEnabled: Bool,
        activationMode: ActivationMode,
        defaultSelectionBehavior: DefaultSelectionBehavior,
        isEnabled: Bool,
        learnedDomainPreferences: [String: String],
        lastUsedBrowserId: UUID?,
        lastUsedEmailClientId: UUID?
    ) {
        self.browsers = browsers
        self.emailClients = emailClients
        self.rules = rules
        self.globalRewriteRules = globalRewriteRules
        self.utmStripParameters = utmStripParameters
        self.globalUTMStrippingEnabled = globalUTMStrippingEnabled
        self.activationMode = activationMode
        self.defaultSelectionBehavior = defaultSelectionBehavior
        self.isEnabled = isEnabled
        self.learnedDomainPreferences = learnedDomainPreferences
        self.lastUsedBrowserId = lastUsedBrowserId
        self.lastUsedEmailClientId = lastUsedEmailClientId
    }
}
