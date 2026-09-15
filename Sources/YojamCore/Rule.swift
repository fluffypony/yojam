import Foundation

public struct RuleSourceApp: Codable, Equatable, Sendable, Identifiable {
    // Remove with the legacy Rule codec once pre-1.3 clients no longer share configs.
    public static let legacyMultiAppGuard = RuleSourceApp(
        bundleId: "com.yojam.source.requires-multiple-source-apps")

    public var bundleId: String
    public var name: String?
    public var id: String { bundleId }
    public var displayName: String { name ?? bundleId }

    public init(bundleId: String, name: String? = nil) {
        self.bundleId = bundleId
        self.name = name
    }
}

public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var matchType: MatchType
    public var pattern: String
    public var urlNormalization: URLNormalizationMode
    public var targetBundleId: String
    public var targetAppName: String
    /// Optional BrowserEntry UUID when this rule targets a configured browser
    /// row/profile instead of just the app bundle.
    public var targetBrowserEntryId: UUID?
    public var isBuiltIn: Bool
    public var priority: Int
    public var stripUTMParams: Bool
    public var rewriteRules: [URLRewriteRule]
    /// Any listed app can match. An empty list allows all sources.
    public var sourceApps: [RuleSourceApp]
    /// Local machine IDs allowed to run this rule. nil/empty means all Macs.
    public var machineScopeIdentifiers: [String]?
    /// Human-readable names captured when machine-scoped rules are created.
    public var machineScopeNames: [String: String]?
    /// Field-level timestamp for machine scope changes. This lets iCloud merge
    /// scope edits independently from unrelated rule edits on another Mac.
    public var machineScopeModifiedAt: Date?
    public var lastModifiedAt: Date?

    // Structured action fields.
    /// Firefox or Orion container name for container-aware opens (nil = no container).
    public var firefoxContainer: String?
    /// Persistent display UUID (CGDisplayCreateUUIDFromDisplayID → string) for per-display targeting.
    public var targetDisplayUUID: String?
    /// Fallback display index when UUID is not available.
    public var targetDisplayIndex: Int?
    /// Arbitrary per-rule metadata (e.g. import provenance).
    public var metadata: [String: String]?

    // Rule-level browser overrides. Each is optional; `nil` means "inherit
    // from the matched BrowserEntry." The launcher resolves effective
    // values by OR-ing these over the entry's defaults.
    /// Profile ID (Chromium profile dir, Firefox profile name) to launch
    /// against when this rule matches. `nil` = inherit from BrowserEntry.
    public var ruleProfileId: String?
    /// Private/incognito window for this rule. `nil` = inherit from
    /// BrowserEntry, `true` = force private, `false` = force normal.
    public var ruleOpenInPrivateWindow: Bool?
    /// Launch-arg template (with `$URL`) for this rule. `nil` = inherit
    /// from BrowserEntry. Empty string is treated the same as nil.
    public var ruleCustomLaunchArgs: String?
    /// Whether this rule should force a new app instance. `nil` = inherit.
    public var ruleOpenAsNewInstance: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        matchType: MatchType,
        pattern: String,
        urlNormalization: URLNormalizationMode = .none,
        targetBundleId: String,
        targetAppName: String,
        targetBrowserEntryId: UUID? = nil,
        isBuiltIn: Bool = false,
        priority: Int = 100,
        stripUTMParams: Bool = false,
        rewriteRules: [URLRewriteRule] = [],
        sourceApps: [RuleSourceApp] = [],
        machineScopeIdentifiers: [String]? = nil,
        machineScopeNames: [String: String]? = nil,
        machineScopeModifiedAt: Date? = nil,
        lastModifiedAt: Date? = nil,
        firefoxContainer: String? = nil,
        targetDisplayUUID: String? = nil,
        targetDisplayIndex: Int? = nil,
        metadata: [String: String]? = nil,
        ruleProfileId: String? = nil,
        ruleOpenInPrivateWindow: Bool? = nil,
        ruleCustomLaunchArgs: String? = nil,
        ruleOpenAsNewInstance: Bool? = nil
    ) {
        self.id = id; self.name = name; self.enabled = enabled
        self.matchType = matchType; self.pattern = pattern
        self.urlNormalization = urlNormalization
        self.targetBundleId = targetBundleId; self.targetAppName = targetAppName
        self.targetBrowserEntryId = targetBrowserEntryId
        self.isBuiltIn = isBuiltIn; self.priority = priority
        self.stripUTMParams = stripUTMParams; self.rewriteRules = rewriteRules
        self.sourceApps = sourceApps
        self.machineScopeIdentifiers = machineScopeIdentifiers
        self.machineScopeNames = machineScopeNames
        self.machineScopeModifiedAt = machineScopeModifiedAt
        self.lastModifiedAt = lastModifiedAt
        self.firefoxContainer = firefoxContainer
        self.targetDisplayUUID = targetDisplayUUID
        self.targetDisplayIndex = targetDisplayIndex
        self.metadata = metadata
        self.ruleProfileId = ruleProfileId
        self.ruleOpenInPrivateWindow = ruleOpenInPrivateWindow
        self.ruleCustomLaunchArgs = ruleCustomLaunchArgs
        self.ruleOpenAsNewInstance = ruleOpenAsNewInstance
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, matchType, pattern, urlNormalization
        case targetBundleId, targetAppName, targetBrowserEntryId, isBuiltIn, priority
        case stripUTMParams, rewriteRules
        case sourceApps
        case machineScopeIdentifiers, machineScopeNames, machineScopeModifiedAt, lastModifiedAt
        case firefoxContainer, targetDisplayUUID, targetDisplayIndex, metadata
        case ruleProfileId, ruleOpenInPrivateWindow, ruleCustomLaunchArgs
        case ruleOpenAsNewInstance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.matchType = try c.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .domain
        self.pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        self.urlNormalization = try c.decodeIfPresent(
            URLNormalizationMode.self,
            forKey: .urlNormalization
        ) ?? .none
        self.targetBundleId = try c.decodeIfPresent(String.self, forKey: .targetBundleId) ?? ""
        self.targetAppName = try c.decodeIfPresent(String.self, forKey: .targetAppName) ?? ""
        self.targetBrowserEntryId = try c.decodeIfPresent(UUID.self, forKey: .targetBrowserEntryId)
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 100
        self.stripUTMParams = try c.decodeIfPresent(Bool.self, forKey: .stripUTMParams) ?? false
        self.rewriteRules = try c.decodeIfPresent([URLRewriteRule].self, forKey: .rewriteRules) ?? []
        if let sourceApps = try c.decodeIfPresent([RuleSourceApp].self, forKey: .sourceApps) {
            self.sourceApps = sourceApps
        } else {
            // Single-source rules survive in saved exports and on Macs that update
            // independently. The sourceApps list is canonical. Remove this read
            // once pre-1.3 exports and sync clients are no longer supported.
            let legacy = try decoder.container(keyedBy: LegacySourceAppKeys.self)
            if let bundleId = try legacy.decodeIfPresent(String.self, forKey: .sourceAppBundleId) {
                self.sourceApps = [RuleSourceApp(
                    bundleId: bundleId,
                    name: try legacy.decodeIfPresent(String.self, forKey: .sourceAppName))]
            } else {
                self.sourceApps = []
            }
        }
        self.machineScopeIdentifiers = try c.decodeIfPresent([String].self, forKey: .machineScopeIdentifiers)
        self.machineScopeNames = try c.decodeIfPresent([String: String].self, forKey: .machineScopeNames)
        self.machineScopeModifiedAt = try c.decodeIfPresent(Date.self, forKey: .machineScopeModifiedAt)
        self.lastModifiedAt = try c.decodeIfPresent(Date.self, forKey: .lastModifiedAt)
        self.firefoxContainer = try c.decodeIfPresent(String.self, forKey: .firefoxContainer)
        self.targetDisplayUUID = try c.decodeIfPresent(String.self, forKey: .targetDisplayUUID)
        self.targetDisplayIndex = try c.decodeIfPresent(Int.self, forKey: .targetDisplayIndex)
        self.metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata)
        self.ruleProfileId = try c.decodeIfPresent(String.self, forKey: .ruleProfileId)
        self.ruleOpenInPrivateWindow = try c.decodeIfPresent(Bool.self, forKey: .ruleOpenInPrivateWindow)
        self.ruleCustomLaunchArgs = try c.decodeIfPresent(String.self, forKey: .ruleCustomLaunchArgs)
        self.ruleOpenAsNewInstance = try c.decodeIfPresent(Bool.self, forKey: .ruleOpenAsNewInstance)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(matchType, forKey: .matchType)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(urlNormalization, forKey: .urlNormalization)
        try c.encode(targetBundleId, forKey: .targetBundleId)
        try c.encode(targetAppName, forKey: .targetAppName)
        try c.encodeIfPresent(targetBrowserEntryId, forKey: .targetBrowserEntryId)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
        try c.encode(priority, forKey: .priority)
        try c.encode(stripUTMParams, forKey: .stripUTMParams)
        try c.encode(rewriteRules, forKey: .rewriteRules)
        try c.encode(sourceApps, forKey: .sourceApps)
        try c.encodeIfPresent(machineScopeIdentifiers, forKey: .machineScopeIdentifiers)
        try c.encodeIfPresent(machineScopeNames, forKey: .machineScopeNames)
        try c.encodeIfPresent(machineScopeModifiedAt, forKey: .machineScopeModifiedAt)
        try c.encodeIfPresent(lastModifiedAt, forKey: .lastModifiedAt)
        try c.encodeIfPresent(firefoxContainer, forKey: .firefoxContainer)
        try c.encodeIfPresent(targetDisplayUUID, forKey: .targetDisplayUUID)
        try c.encodeIfPresent(targetDisplayIndex, forKey: .targetDisplayIndex)
        try c.encodeIfPresent(metadata, forKey: .metadata)
        try c.encodeIfPresent(ruleProfileId, forKey: .ruleProfileId)
        try c.encodeIfPresent(ruleOpenInPrivateWindow, forKey: .ruleOpenInPrivateWindow)
        try c.encodeIfPresent(ruleCustomLaunchArgs, forKey: .ruleCustomLaunchArgs)
        try c.encodeIfPresent(ruleOpenAsNewInstance, forKey: .ruleOpenAsNewInstance)

        // Pre-1.3 apps ignore sourceApps. Keep single-app rules usable there;
        // make multi-app rules miss instead of silently routing every source.
        // Remove these keys when pre-1.3 clients no longer share configs.
        var legacy = encoder.container(keyedBy: LegacySourceAppKeys.self)
        let legacySource = sourceApps.count > 1 ? RuleSourceApp.legacyMultiAppGuard : sourceApps.first
        try legacy.encodeIfPresent(legacySource?.bundleId, forKey: .sourceAppBundleId)
        try legacy.encodeIfPresent(legacySource?.name, forKey: .sourceAppName)
    }

    private enum LegacySourceAppKeys: String, CodingKey {
        case sourceAppBundleId, sourceAppName
    }
}

public enum MatchType: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, domain, domainSuffix, urlPrefix, hostPathPrefix, urlContains, regex
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .all: "All URLs"
        case .domain: "Host (exact)"
        case .domainSuffix: "Host suffix"
        case .urlPrefix: "Full URL prefix"
        case .hostPathPrefix: "Host + path prefix"
        case .urlContains: "URL contains"
        case .regex: "Regex"
        }
    }
}
