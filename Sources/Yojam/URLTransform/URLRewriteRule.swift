import Foundation

struct URLRewriteRule: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var enabled: Bool
    var matchPattern: String
    var replacement: String
    var isRegex: Bool
    var scope: RewriteScope

    init(id: UUID = UUID(), name: String, enabled: Bool = true,
         matchPattern: String, replacement: String,
         isRegex: Bool = true, scope: RewriteScope = .global) {
        self.id = id; self.name = name; self.enabled = enabled
        self.matchPattern = matchPattern; self.replacement = replacement
        self.isRegex = isRegex; self.scope = scope
    }
}

enum RewriteScope: Codable, Equatable, Hashable, Sendable {
    case global
    case browser(String)
    case rule(UUID)

    enum CodingKeys: String, CodingKey { case type, value }

    func encode(to encoder: Encoder) throws {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "browser":
            let value = try container.decode(String.self, forKey: .value)
            self = .browser(value)
        case "rule":
            let value = try container.decode(String.self, forKey: .value)
            // §22: Fall back to .global instead of generating orphan random UUID
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
