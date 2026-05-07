import Foundation
import YojamCore

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
                    var winning = entry
                    // Preserve local-only fields that are stripped before sync
                    if winning.customIconData == nil, let localIcon = existing.customIconData {
                        winning.customIconData = localIcon
                    }
                    winning.isInstalled = existing.isInstalled
                    winning.lastSeenAt = existing.lastSeenAt
                    merged[entry.id] = winning
                }
            } else {
                merged[entry.id] = entry
            }
        }
        // §8: Reindex positions after sorting to prevent duplicates (stable tiebreak by UUID)
        var sorted = merged.values.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id.uuidString < $1.id.uuidString
        }
        for i in sorted.indices { sorted[i].position = i }
        return sorted
    }

    static func mergeRules(local: [Rule], remote: [Rule]) -> [Rule] {
        var merged: [UUID: Rule] = [:]
        for rule in local { merged[rule.id] = rule }
        for rule in remote {
            if let existing = merged[rule.id] {
                merged[rule.id] = mergeRule(local: existing, remote: rule)
            } else {
                merged[rule.id] = rule
            }
        }
        let ordered = merged.values.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id.uuidString < $1.id.uuidString
        }
        return RuleOrdering.sorted(ordered)
    }

    private static func mergeRule(local: Rule, remote: Rule) -> Rule {
        let remoteIsNewer = (remote.lastModifiedAt ?? .distantPast)
            > (local.lastModifiedAt ?? .distantPast)
        var merged = remoteIsNewer ? remote : local

        let localScopeDate = machineScopeDate(local)
        let remoteScopeDate = machineScopeDate(remote)
        if let remoteScopeDate,
           remoteScopeDate > (localScopeDate ?? .distantPast) {
            merged.machineScopeIdentifiers = remote.machineScopeIdentifiers
            merged.machineScopeNames = remote.machineScopeNames
            merged.machineScopeModifiedAt = remote.machineScopeModifiedAt ?? remote.lastModifiedAt
        } else if let localScopeDate,
                  localScopeDate > (remoteScopeDate ?? .distantPast) {
            merged.machineScopeIdentifiers = local.machineScopeIdentifiers
            merged.machineScopeNames = local.machineScopeNames
            merged.machineScopeModifiedAt = local.machineScopeModifiedAt ?? local.lastModifiedAt
        }
        return merged
    }

    private static func machineScopeDate(_ rule: Rule) -> Date? {
        if let machineScopeModifiedAt = rule.machineScopeModifiedAt {
            return machineScopeModifiedAt
        }
        let ids = normalizedMachineScope(rule.machineScopeIdentifiers)
        return ids.isEmpty ? nil : rule.lastModifiedAt
    }

    private static func normalizedMachineScope(_ ids: [String]?) -> [String] {
        (ids ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // §7: Preserve local order, append remote-only entries. Use timestamps when available.
    static func mergeRewriteRules(
        local: [URLRewriteRule], remote: [URLRewriteRule]
    ) -> [URLRewriteRule] {
        var mergedMap: [UUID: URLRewriteRule] = [:]
        for rule in local { mergedMap[rule.id] = rule }
        for rule in remote {
            if let existing = mergedMap[rule.id] {
                let remoteDate = rule.lastModifiedAt ?? .distantPast
                let localDate = existing.lastModifiedAt ?? .distantPast
                if remoteDate > localDate {
                    mergedMap[rule.id] = rule
                }
            } else {
                mergedMap[rule.id] = rule
            }
        }

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
