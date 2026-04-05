import Foundation

enum SyncConflictResolver {
    static func mergeBrowserLists(
        local: [BrowserEntry], remote: [BrowserEntry]
    ) -> [BrowserEntry] {
        var merged: [UUID: BrowserEntry] = [:]
        for entry in local { merged[entry.id] = entry }
        for entry in remote {
            if let existing = merged[entry.id] {
                let remoteDate = entry.lastModifiedAt ?? entry.lastSeenAt ?? .distantPast
                let localDate = existing.lastModifiedAt ?? existing.lastSeenAt ?? .distantPast
                if remoteDate > localDate {
                    merged[entry.id] = entry
                }
            } else {
                merged[entry.id] = entry
            }
        }
        // §8: Reindex positions after sorting to prevent duplicates
        var sorted = merged.values.sorted { $0.position < $1.position }
        for i in sorted.indices { sorted[i].position = i }
        return sorted
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

    // §7: Preserve local order, append remote-only entries at the end
    static func mergeRewriteRules(
        local: [URLRewriteRule], remote: [URLRewriteRule]
    ) -> [URLRewriteRule] {
        var mergedMap: [UUID: URLRewriteRule] = [:]
        for rule in remote { mergedMap[rule.id] = rule }
        for rule in local { mergedMap[rule.id] = rule }

        var result: [URLRewriteRule] = []
        for rule in local {
            if let r = mergedMap.removeValue(forKey: rule.id) { result.append(r) }
        }
        for rule in remote {
            if let r = mergedMap.removeValue(forKey: rule.id) { result.append(r) }
        }
        return result
    }
}
