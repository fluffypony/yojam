import Foundation

struct Rule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    var matchType: MatchType
    var pattern: String
    var targetBundleId: String
    var targetAppName: String
    var isBuiltIn: Bool
    var priority: Int
    var stripUTMParams: Bool
    var rewriteRules: [URLRewriteRule]
    var sourceAppBundleId: String?
    var sourceAppName: String?

    init(
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
        sourceAppName: String? = nil
    ) {
        self.id = id; self.name = name; self.enabled = enabled
        self.matchType = matchType; self.pattern = pattern
        self.targetBundleId = targetBundleId; self.targetAppName = targetAppName
        self.isBuiltIn = isBuiltIn; self.priority = priority
        self.stripUTMParams = stripUTMParams; self.rewriteRules = rewriteRules
        self.sourceAppBundleId = sourceAppBundleId; self.sourceAppName = sourceAppName
    }
}

enum MatchType: String, Codable, CaseIterable, Identifiable {
    case domain, domainSuffix, urlPrefix, urlContains, regex
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .domain: "Domain (exact)"
        case .domainSuffix: "Domain suffix"
        case .urlPrefix: "URL prefix"
        case .urlContains: "URL contains"
        case .regex: "Regex"
        }
    }
}
