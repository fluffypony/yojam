import Foundation

public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var matchType: MatchType
    public var pattern: String
    public var targetBundleId: String
    public var targetAppName: String
    public var isBuiltIn: Bool
    public var priority: Int
    public var stripUTMParams: Bool
    public var rewriteRules: [URLRewriteRule]
    public var sourceAppBundleId: String?
    public var sourceAppName: String?
    public var lastModifiedAt: Date?

    // Structured action fields.
    /// Firefox container name for container-aware opens (nil = no container).
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

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        matchType: MatchType,
        pattern: String,
        targetBundleId: String,
        targetAppName: String,
        isBuiltIn: Bool = false,
        priority: Int = 100,
        stripUTMParams: Bool = false,
        rewriteRules: [URLRewriteRule] = [],
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        lastModifiedAt: Date? = nil,
        firefoxContainer: String? = nil,
        targetDisplayUUID: String? = nil,
        targetDisplayIndex: Int? = nil,
        metadata: [String: String]? = nil,
        ruleProfileId: String? = nil,
        ruleOpenInPrivateWindow: Bool? = nil,
        ruleCustomLaunchArgs: String? = nil
    ) {
        self.id = id; self.name = name; self.enabled = enabled
        self.matchType = matchType; self.pattern = pattern
        self.targetBundleId = targetBundleId; self.targetAppName = targetAppName
        self.isBuiltIn = isBuiltIn; self.priority = priority
        self.stripUTMParams = stripUTMParams; self.rewriteRules = rewriteRules
        self.sourceAppBundleId = sourceAppBundleId; self.sourceAppName = sourceAppName
        self.lastModifiedAt = lastModifiedAt
        self.firefoxContainer = firefoxContainer
        self.targetDisplayUUID = targetDisplayUUID
        self.targetDisplayIndex = targetDisplayIndex
        self.metadata = metadata
        self.ruleProfileId = ruleProfileId
        self.ruleOpenInPrivateWindow = ruleOpenInPrivateWindow
        self.ruleCustomLaunchArgs = ruleCustomLaunchArgs
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, matchType, pattern
        case targetBundleId, targetAppName, isBuiltIn, priority
        case stripUTMParams, rewriteRules
        case sourceAppBundleId, sourceAppName, lastModifiedAt
        case firefoxContainer, targetDisplayUUID, targetDisplayIndex, metadata
        case ruleProfileId, ruleOpenInPrivateWindow, ruleCustomLaunchArgs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.matchType = try c.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .domain
        self.pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        self.targetBundleId = try c.decodeIfPresent(String.self, forKey: .targetBundleId) ?? ""
        self.targetAppName = try c.decodeIfPresent(String.self, forKey: .targetAppName) ?? ""
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 100
        self.stripUTMParams = try c.decodeIfPresent(Bool.self, forKey: .stripUTMParams) ?? false
        self.rewriteRules = try c.decodeIfPresent([URLRewriteRule].self, forKey: .rewriteRules) ?? []
        self.sourceAppBundleId = try c.decodeIfPresent(String.self, forKey: .sourceAppBundleId)
        self.sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        self.lastModifiedAt = try c.decodeIfPresent(Date.self, forKey: .lastModifiedAt)
        self.firefoxContainer = try c.decodeIfPresent(String.self, forKey: .firefoxContainer)
        self.targetDisplayUUID = try c.decodeIfPresent(String.self, forKey: .targetDisplayUUID)
        self.targetDisplayIndex = try c.decodeIfPresent(Int.self, forKey: .targetDisplayIndex)
        self.metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata)
        self.ruleProfileId = try c.decodeIfPresent(String.self, forKey: .ruleProfileId)
        self.ruleOpenInPrivateWindow = try c.decodeIfPresent(Bool.self, forKey: .ruleOpenInPrivateWindow)
        self.ruleCustomLaunchArgs = try c.decodeIfPresent(String.self, forKey: .ruleCustomLaunchArgs)
    }
}

public enum MatchType: String, Codable, CaseIterable, Identifiable, Sendable {
    case domain, domainSuffix, urlPrefix, hostPathPrefix, urlContains, regex
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .domain: "Host (exact)"
        case .domainSuffix: "Host suffix"
        case .urlPrefix: "Full URL prefix"
        case .hostPathPrefix: "Host + path prefix"
        case .urlContains: "URL contains"
        case .regex: "Regex"
        }
    }
}
