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

    static func mergeRules(local: [Rule], remote: [Rule]) -> [Rule] {
        var merged: [UUID: Rule] = [:]
        for rule in local { merged[rule.id] = rule }
        for rule in remote { merged[rule.id] = rule }
        return merged.values.sorted { $0.priority < $1.priority }
    }
}
