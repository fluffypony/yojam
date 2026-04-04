import Foundation

enum SyncConflictResolver {
    static func mergeBrowserLists(
        local: [BrowserEntry], remote: [BrowserEntry]
    ) -> [BrowserEntry] {
        var merged: [UUID: BrowserEntry] = [:]
        for entry in local { merged[entry.id] = entry }
        for entry in remote {
            if let existing = merged[entry.id] {
                if (entry.lastSeenAt ?? .distantPast)
                    > (existing.lastSeenAt ?? .distantPast) {
                    merged[entry.id] = entry
                }
            } else {
                merged[entry.id] = entry
            }
        }
        return merged.values.sorted { $0.position < $1.position }
    }

    // Use lastModifiedAt for conflict resolution (§24.1)
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
}
