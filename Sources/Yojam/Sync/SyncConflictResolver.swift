import Foundation
import YojamCore

enum SyncConflictResolver {
    struct BrowserListMergeResult {
        var entries: [BrowserEntry]
        var idAliases: [UUID: UUID]
    }

    static func mergeBrowserLists(
        local: [BrowserEntry],
        remote: [BrowserEntry],
        preservingLocalRewriteFieldsForRemoteBrowserIDs legacyBrowserIds: Set<UUID> = [],
        preferringRemoteOnEqualTimestampForBrowserIDs preferredRemoteBrowserIds: Set<UUID> = []
    ) -> [BrowserEntry] {
        mergeBrowserListsWithAliases(
            local: local,
            remote: remote,
            preservingLocalRewriteFieldsForRemoteBrowserIDs: legacyBrowserIds,
            preferringRemoteOnEqualTimestampForBrowserIDs: preferredRemoteBrowserIds
        ).entries
    }

    static func mergeBrowserListsWithAliases(
        local: [BrowserEntry],
        remote: [BrowserEntry],
        preservingLocalRewriteFieldsForRemoteBrowserIDs legacyBrowserIds: Set<UUID> = [],
        preferringRemoteOnEqualTimestampForBrowserIDs preferredRemoteBrowserIds: Set<UUID> = []
    ) -> BrowserListMergeResult {
        var merged: [UUID: BrowserEntry] = [:]
        for entry in local { merged[entry.id] = entry }
        for entry in remote {
            if let existing = merged[entry.id] {
                let remoteEntry = legacyBrowserIds.contains(entry.id)
                    ? preservingLegacyRewriteFields(in: entry, from: existing)
                    : entry
                merged[entry.id] = newerBrowserEntry(
                    remote: remoteEntry,
                    local: existing,
                    preferRemoteOnEqualTimestamp: preferredRemoteBrowserIds.contains(entry.id))
            } else {
                merged[entry.id] = entry
            }
        }

        let coalesced = coalesceBrowserIdentityDuplicates(
            Array(merged.values),
            preferredLocalIds: Set(local.map(\.id)),
            legacyRemoteIds: legacyBrowserIds)

        var sorted = coalesced.entries.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id.uuidString < $1.id.uuidString
        }
        for i in sorted.indices { sorted[i].position = i }
        return BrowserListMergeResult(entries: sorted, idAliases: coalesced.idAliases)
    }

    static func mergeRules(
        local: [Rule],
        remote: [Rule],
        preservingLocalRewriteFieldsForRemoteRuleIDs legacyRuleIds: Set<UUID> = [],
        preferringRemoteOnEqualTimestampForRuleIDs preferredRemoteRuleIds: Set<UUID> = []
    ) -> [Rule] {
        var merged: [UUID: Rule] = [:]
        for rule in local { merged[rule.id] = rule }
        for rule in remote {
            if let existing = merged[rule.id] {
                let remoteRule = legacyRuleIds.contains(rule.id)
                    ? preservingLegacyRewriteFields(in: rule, from: existing)
                    : rule
                merged[rule.id] = mergeRule(
                    local: existing,
                    remote: remoteRule,
                    preferRemoteOnEqualTimestamp: preferredRemoteRuleIds.contains(rule.id))
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

    static func remapRuleBrowserTargets(_ rules: [Rule], aliases: [UUID: UUID]) -> [Rule] {
        guard !aliases.isEmpty else { return rules }
        return rules.map { rule in
            guard let targetId = rule.targetBrowserEntryId,
                  let replacement = aliases[targetId] else {
                return rule
            }
            var copy = rule
            copy.targetBrowserEntryId = replacement
            return copy
        }
    }

    private static func newerBrowserEntry(
        remote: BrowserEntry,
        local: BrowserEntry,
        preferRemoteOnEqualTimestamp: Bool = false
    ) -> BrowserEntry {
        let remoteDate = remote.lastModifiedAt ?? remote.lastSeenAt ?? .distantPast
        let localDate = local.lastModifiedAt ?? local.lastSeenAt ?? .distantPast
        guard remoteDate > localDate
                || (preferRemoteOnEqualTimestamp
                    && remote.lastModifiedAt == local.lastModifiedAt) else {
            return local
        }

        var winning = remote
        // Preserve local-only fields that are stripped or machine-specific.
        if winning.customIconData == nil, let localIcon = local.customIconData {
            winning.customIconData = localIcon
        }
        winning.isInstalled = local.isInstalled
        winning.lastSeenAt = local.lastSeenAt
        return winning
    }

    private static func coalesceBrowserIdentityDuplicates(
        _ entries: [BrowserEntry],
        preferredLocalIds: Set<UUID>,
        legacyRemoteIds: Set<UUID>
    ) -> (entries: [BrowserEntry], idAliases: [UUID: UUID]) {
        var groups: [String: [BrowserEntry]] = [:]
        for entry in entries {
            groups[browserIdentityKey(entry), default: []].append(entry)
        }

        var result: [BrowserEntry] = []
        var aliases: [UUID: UUID] = [:]
        for group in groups.values {
            let ordered = group.sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let canonical = preferredCanonicalBrowserEntry(
                in: ordered,
                preferredLocalIds: preferredLocalIds) else {
                continue
            }

            var winning = ordered[0]
            for entry in ordered.dropFirst() {
                winning = newerBrowserEntry(remote: entry, local: winning)
            }
            let winningWasLegacy = legacyRemoteIds.contains(winning.id)
            if winning.id != canonical.id {
                winning = copyBrowserEntry(winning, id: canonical.id)
            }
            if let localAnchor = ordered.first(where: { preferredLocalIds.contains($0.id) }) {
                winning = preservingLocalBrowserFields(in: winning, from: localAnchor)
                if winningWasLegacy {
                    winning = preservingLegacyRewriteFields(in: winning, from: localAnchor)
                }
            }
            for entry in ordered where entry.id != canonical.id {
                aliases[entry.id] = canonical.id
            }
            result.append(winning)
        }
        return (result, aliases)
    }

    private static func preservingLocalBrowserFields(
        in entry: BrowserEntry,
        from local: BrowserEntry
    ) -> BrowserEntry {
        var copy = entry
        if copy.customIconData == nil, let localIcon = local.customIconData {
            copy.customIconData = localIcon
        }
        copy.isInstalled = local.isInstalled
        copy.lastSeenAt = local.lastSeenAt
        return copy
    }

    private static func preservingLegacyRewriteFields(
        in remote: BrowserEntry,
        from local: BrowserEntry
    ) -> BrowserEntry {
        var copy = remote
        var localRewritesById: [UUID: URLRewriteRule] = [:]
        for rewrite in local.rewriteRules {
            localRewritesById[rewrite.id] = rewrite
        }
        for index in copy.rewriteRules.indices {
            guard let localRewrite = localRewritesById[copy.rewriteRules[index].id] else {
                continue
            }
            copy.rewriteRules[index].urlNormalization = localRewrite.urlNormalization
            copy.rewriteRules[index].metadata = localRewrite.metadata
        }
        return copy
    }

    private static func preferredCanonicalBrowserEntry(
        in entries: [BrowserEntry],
        preferredLocalIds: Set<UUID>
    ) -> BrowserEntry? {
        entries.first { preferredLocalIds.contains($0.id) } ?? entries.first
    }

    private static func browserIdentityKey(_ entry: BrowserEntry) -> String {
        [
            entry.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            normalizedIdentityComponent(entry.profileId),
            normalizedIdentityComponent(entry.userDataDirectory),
            normalizedIdentityComponent(entry.customLaunchArgs),
            entry.openInPrivateWindow ? "private" : "normal",
            entry.openAsNewInstance ? "new-instance" : "existing-instance",
        ].joined(separator: "\u{1f}")
    }

    private static func normalizedIdentityComponent(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return home + String(trimmed.dropFirst())
        }
        if trimmed.hasPrefix("$HOME/") {
            return home + String(trimmed.dropFirst("$HOME".count))
        }
        return trimmed
    }

    private static func copyBrowserEntry(_ entry: BrowserEntry, id: UUID) -> BrowserEntry {
        BrowserEntry(
            id: id,
            bundleIdentifier: entry.bundleIdentifier,
            displayName: entry.displayName,
            enabled: entry.enabled,
            position: entry.position,
            profileId: entry.profileId,
            profileName: entry.profileName,
            stripUTMParams: entry.stripUTMParams,
            openInPrivateWindow: entry.openInPrivateWindow,
            rewriteRules: entry.rewriteRules,
            source: entry.source,
            isInstalled: entry.isInstalled,
            lastSeenAt: entry.lastSeenAt,
            lastModifiedAt: entry.lastModifiedAt,
            customIconData: entry.customIconData,
            userDataDirectory: entry.userDataDirectory,
            customLaunchArgs: entry.customLaunchArgs,
            openAsNewInstance: entry.openAsNewInstance)
    }

    private static func mergeRule(
        local: Rule,
        remote: Rule,
        preferRemoteOnEqualTimestamp: Bool = false
    ) -> Rule {
        let remoteIsNewer = (remote.lastModifiedAt ?? .distantPast)
            > (local.lastModifiedAt ?? .distantPast)
        let timestampsAreEqual = (remote.lastModifiedAt ?? .distantPast)
            == (local.lastModifiedAt ?? .distantPast)
        var merged = remoteIsNewer || (preferRemoteOnEqualTimestamp && timestampsAreEqual)
            ? remote
            : local

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

    private static func preservingLegacyRewriteFields(in remote: Rule, from local: Rule) -> Rule {
        var copy = remote
        copy.urlNormalization = local.urlNormalization

        var localRewritesById: [UUID: URLRewriteRule] = [:]
        for rewrite in local.rewriteRules {
            localRewritesById[rewrite.id] = rewrite
        }
        for index in copy.rewriteRules.indices {
            guard let localRewrite = localRewritesById[copy.rewriteRules[index].id] else {
                continue
            }
            copy.rewriteRules[index].urlNormalization = localRewrite.urlNormalization
            copy.rewriteRules[index].metadata = localRewrite.metadata
        }
        return copy
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
        local: [URLRewriteRule],
        remote: [URLRewriteRule],
        preservingLocalRewriteFieldsForRemoteRewriteRuleIDs legacyRewriteRuleIds: Set<UUID> = [],
        preferringRemoteOnEqualTimestampForRewriteRuleIDs preferredRemoteRewriteRuleIds: Set<UUID> = []
    ) -> [URLRewriteRule] {
        var mergedMap: [UUID: URLRewriteRule] = [:]
        for rule in local { mergedMap[rule.id] = rule }
        for rule in remote {
            if let existing = mergedMap[rule.id] {
                var remoteRule = rule
                if legacyRewriteRuleIds.contains(rule.id) {
                    remoteRule.urlNormalization = existing.urlNormalization
                    remoteRule.metadata = existing.metadata
                }
                let remoteDate = remoteRule.lastModifiedAt ?? .distantPast
                let localDate = existing.lastModifiedAt ?? .distantPast
                if remoteDate > localDate
                    || (preferredRemoteRewriteRuleIds.contains(rule.id)
                        && remoteDate == localDate) {
                    mergedMap[rule.id] = remoteRule
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
