import Foundation

enum SyncConflictResolver {
    static func mergeBrowserLists(
        local: [BrowserEntry], remote: [BrowserEntry]
    ) -> [BrowserEntry] {
        var merged: [UUID: BrowserEntry] = [:]
        for entry in local { merged[entry.id] = entry }
        for entry in remote {
            if let existing = merged[entry.id] {
                // Use lastModifiedAt for conflict resolution, fall back to lastSeenAt
                let remoteDate = entry.lastModifiedAt ?? entry.lastSeenAt ?? .distantPast
                let localDate = existing.lastModifiedAt ?? existing.lastSeenAt ?? .distantPast
                if remoteDate > localDate {
                    merged[entry.id] = entry
                }
            } else {
                merged[entry.id] = entry
            }
        }
        return merged.values.sorted { $0.position < $1.position }
    }

    static func mergeRules(local: [Rule], remote: [Rule]) -> [Rule] {
        var merged: [UUID: Rule] = [:]
        for rule in local { merged[rule.id] = rule }
        for rule in remote {
            if let existing = merged[rule.id] {
                if (rule.lastModifiedAt ?? .distantPast) > (existing.lastModifiedAt ?? .distantPast) {
                    merged[rule.id] = rule
                }
            } else {
                merged[rule.id] = rule
            }
        }
        return merged.values.sorted { $0.priority < $1.priority }
    }

    static func mergeRewriteRules(
        local: [URLRewriteRule], remote: [URLRewriteRule]
    ) -> [URLRewriteRule] {
        var merged: [UUID: URLRewriteRule] = [:]
        for rule in remote { merged[rule.id] = rule }
        // Local wins on conflict (no timestamp available for rewrite rules)
        for rule in local { merged[rule.id] = rule }
        return Array(merged.values)
    }
}
