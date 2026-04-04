import Foundation

enum BuiltInRewriteRules {
    static let all: [URLRewriteRule] = [
        URLRewriteRule(name: "Twitter to Nitter", enabled: false,
                       matchPattern: #"https://(www\.)?twitter\.com/(.*)"#,
                       replacement: "https://nitter.net/$2", scope: .global),
        URLRewriteRule(name: "X.com to Nitter", enabled: false,
                       matchPattern: #"https://(www\.)?x\.com/(.*)"#,
                       replacement: "https://nitter.net/$2", scope: .global),
        URLRewriteRule(name: "Reddit to Old Reddit", enabled: false,
                       matchPattern: #"https://(www\.)?reddit\.com/(.*)"#,
                       replacement: "https://old.reddit.com/$2", scope: .global),
        URLRewriteRule(name: "Medium to Scribe", enabled: false,
                       matchPattern: #"https://medium\.com/(.*)"#,
                       replacement: "https://scribe.rip/$1", scope: .global),
    ]
}
