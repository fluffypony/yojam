import Foundation

public struct URLRewriteRule: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var matchPattern: String
    public var replacement: String
    public var isRegex: Bool
    public var scope: RewriteScope
    public var urlNormalization: URLNormalizationMode
    public var metadata: [String: String]?
    public var lastModifiedAt: Date?

    public init(id: UUID = UUID(), name: String, enabled: Bool = true,
                matchPattern: String, replacement: String,
                isRegex: Bool = true, scope: RewriteScope = .global,
                urlNormalization: URLNormalizationMode = .none,
                metadata: [String: String]? = nil,
                lastModifiedAt: Date? = nil) {
        self.id = id; self.name = name; self.enabled = enabled
        self.matchPattern = matchPattern; self.replacement = replacement
        self.isRegex = isRegex; self.scope = scope
        self.urlNormalization = urlNormalization
        self.metadata = metadata
        self.lastModifiedAt = lastModifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, matchPattern, replacement, isRegex, scope
        case urlNormalization, metadata, lastModifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        matchPattern = try container.decode(String.self, forKey: .matchPattern)
        replacement = try container.decode(String.self, forKey: .replacement)
        isRegex = try container.decode(Bool.self, forKey: .isRegex)
        scope = try container.decode(RewriteScope.self, forKey: .scope)
        urlNormalization = try container.decodeIfPresent(
            URLNormalizationMode.self,
            forKey: .urlNormalization
        ) ?? .none
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        lastModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastModifiedAt)
    }
}

public enum RewriteScope: Codable, Equatable, Hashable, Sendable {
    case global
    case browser(String)
    case rule(UUID)

    enum CodingKeys: String, CodingKey { case type, value }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode("global", forKey: .type)
        case .browser(let id):
            try container.encode("browser", forKey: .type)
            try container.encode(id, forKey: .value)
        case .rule(let id):
            try container.encode("rule", forKey: .type)
            try container.encode(id.uuidString, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "browser":
            let value = try container.decode(String.self, forKey: .value)
            self = .browser(value)
        case "rule":
            let value = try container.decode(String.self, forKey: .value)
            if let id = UUID(uuidString: value) {
                self = .rule(id)
            } else {
                self = .global
            }
        default:
            self = .global
        }
    }
}
