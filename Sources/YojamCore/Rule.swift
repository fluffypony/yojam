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
        lastModifiedAt: Date? = nil
    ) {
        self.id = id; self.name = name; self.enabled = enabled
        self.matchType = matchType; self.pattern = pattern
        self.targetBundleId = targetBundleId; self.targetAppName = targetAppName
        self.isBuiltIn = isBuiltIn; self.priority = priority
        self.stripUTMParams = stripUTMParams; self.rewriteRules = rewriteRules
        self.sourceAppBundleId = sourceAppBundleId; self.sourceAppName = sourceAppName
        self.lastModifiedAt = lastModifiedAt
    }
}

public enum MatchType: String, Codable, CaseIterable, Identifiable, Sendable {
    case domain, domainSuffix, urlPrefix, urlContains, regex
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .domain: "Domain (exact)"
        case .domainSuffix: "Domain suffix"
        case .urlPrefix: "URL prefix"
        case .urlContains: "URL contains"
        case .regex: "Regex"
        }
    }
}
