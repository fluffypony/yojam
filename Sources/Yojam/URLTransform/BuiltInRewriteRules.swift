import Foundation

enum BuiltInRewriteRules {
    // Stable UUIDs so loadGlobalRewriteRules() can deduplicate across launches.
    static let all: [URLRewriteRule] = [
        URLRewriteRule(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
                       name: "Twitter to Nitter (defunct)", enabled: false,
                       matchPattern: #"https://(www\.)?twitter\.com/(.*)"#,
                       replacement: "https://nitter.net/$2", scope: .global),
        URLRewriteRule(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
                       name: "X.com to Nitter (defunct)", enabled: false,
                       matchPattern: #"https://(www\.)?x\.com/(.*)"#,
                       replacement: "https://nitter.net/$2", scope: .global),
        URLRewriteRule(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
                       name: "Reddit to Old Reddit", enabled: false,
                       matchPattern: #"https://(www\.)?reddit\.com/(.*)"#,
                       replacement: "https://old.reddit.com/$2", scope: .global),
        URLRewriteRule(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!,
                       name: "Medium to Scribe", enabled: false,
                       matchPattern: #"https://medium\.com/(.*)"#,
                       replacement: "https://scribe.rip/$1", scope: .global),
    ]
}
