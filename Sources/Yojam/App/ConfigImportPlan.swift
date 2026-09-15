import Foundation
import YojamCore

struct ConfigImportPlan {
    let rules: [Rule]
    let rewriteRules: [URLRewriteRule]
    let duplicateRuleCount: Int
    let duplicateRewriteCount: Int
    /// A known policy to apply after at least one Finicky item is added.
    /// nil keeps the user's current network settings unchanged.
    let shortlinkPolicyChange: FinickyShortlinkPolicy?

    var enablesShortlinkResolution: Bool {
        guard case .replace(let hosts, _) = shortlinkPolicyChange else { return false }
        return !hosts.isEmpty
    }

    var importedItemCount: Int { rules.count + rewriteRules.count }
    var duplicateItemCount: Int { duplicateRuleCount + duplicateRewriteCount }

    static func make(
        results: [ConfigImporter.ImportResult],
        selectedRuleIDs: Set<UUID>,
        selectedRewriteIDs: Set<UUID>,
        existingRules: [Rule],
        existingRewriteRules: [URLRewriteRule]
    ) -> ConfigImportPlan {
        let selectedRules = results.flatMap { result -> [Rule] in
            let selected = result.rules.filter { selectedRuleIDs.contains($0.id) }
            guard result.source == .finicky else { return selected }

            // Every Finicky handler runs after its global rewrite pipeline.
            // Reject a route if the caller did not select that full pipeline.
            let requiredRewriteIDs = Set(result.rewriteRules.map(\.id))
            guard requiredRewriteIDs.isSubset(of: selectedRewriteIDs) else { return [] }
            return selected
        }
        let selectedRewrites = results
            .flatMap(\.rewriteRules)
            .filter { selectedRewriteIDs.contains($0.id) }
        var seenRuleKeys = Set(existingRules.map(ruleKey))
        var newRules: [Rule] = []
        var duplicateRuleCount = 0
        for rule in selectedRules {
            if seenRuleKeys.insert(ruleKey(rule)).inserted {
                newRules.append(rule)
            } else {
                duplicateRuleCount += 1
            }
        }

        var seenRewriteKeys = Set(existingRewriteRules.map(rewriteKey))
        var newRewrites: [URLRewriteRule] = []
        var duplicateRewriteCount = 0
        for rewrite in selectedRewrites {
            if seenRewriteKeys.insert(rewriteKey(rewrite)).inserted {
                newRewrites.append(rewrite)
            } else {
                duplicateRewriteCount += 1
            }
        }

        let newRuleIDs = Set(newRules.map(\.id))
        let newRewriteIDs = Set(newRewrites.map(\.id))
        let contributingFinickyResult = results.first { result in
            guard result.source == .finicky else { return false }
            return result.rules.contains { newRuleIDs.contains($0.id) }
                || result.rewriteRules.contains { newRewriteIDs.contains($0.id) }
        }
        let shortlinkPolicyChange: FinickyShortlinkPolicy?
        switch contributingFinickyResult?.finickyShortlinkPolicy {
        case .replace(let hosts, let mode):
            shortlinkPolicyChange = .replace(
                hosts: ShortlinkResolver.canonicalHostAllowlist(hosts),
                mode: mode)
        case .unknownDynamic, .none:
            shortlinkPolicyChange = nil
        }

        return ConfigImportPlan(
            rules: newRules,
            rewriteRules: newRewrites,
            duplicateRuleCount: duplicateRuleCount,
            duplicateRewriteCount: duplicateRewriteCount,
            shortlinkPolicyChange: shortlinkPolicyChange)
    }

    private static func ruleKey(_ rule: Rule) -> String {
        let pattern = rule.matchType == .regex
            ? rule.pattern
            : rule.pattern.lowercased()
        let nestedRewrites = rule.rewriteRules.map(nestedRewriteKey).joined(separator: "\u{1e}")
        let machineIDs = (rule.machineScopeIdentifiers ?? []).sorted().joined(separator: "\u{1f}")
        return [
            String(rule.enabled),
            rule.matchType.rawValue,
            pattern,
            rule.urlNormalization.rawValue,
            rule.targetBundleId.lowercased(),
            rule.targetBrowserEntryId?.uuidString ?? "",
            Set(rule.sourceApps.map(\.bundleId)).sorted().joined(separator: "\u{1f}"),
            machineIDs,
            String(rule.stripUTMParams),
            nestedRewrites,
            rule.firefoxContainer ?? "",
            rule.targetDisplayUUID ?? "",
            rule.targetDisplayIndex.map(String.init) ?? "",
            rule.ruleProfileId ?? "",
            rule.ruleOpenInPrivateWindow.map(String.init) ?? "",
            rule.ruleCustomLaunchArgs ?? "",
            rule.metadata?["finickySuppressAutomaticURL"] ?? "",
            rule.metadata?["finickyExactBrowserAction"] ?? "",
            rule.metadata?["finickyWebOnly"] ?? "",
            rule.ruleOpenAsNewInstance.map(String.init) ?? "",
        ].joined(separator: "\u{1d}")
    }

    private static func rewriteKey(_ rule: URLRewriteRule) -> String {
        [
            String(rule.enabled),
            String(rule.isRegex),
            rule.matchPattern,
            rule.replacement,
            scopeKey(rule.scope),
            rule.urlNormalization.rawValue,
            rule.metadata?["finickyWebOnly"] ?? "",
        ].joined(separator: "\u{1d}")
    }

    private static func nestedRewriteKey(_ rule: URLRewriteRule) -> String {
        let scope: String
        switch rule.scope {
        case .rule:
            scope = "owning-rule"
        case .global, .browser:
            scope = scopeKey(rule.scope)
        }
        return [
            String(rule.enabled),
            String(rule.isRegex),
            rule.matchPattern,
            rule.replacement,
            scope,
            rule.urlNormalization.rawValue,
            rule.metadata?["finickyWebOnly"] ?? "",
        ].joined(separator: "\u{1d}")
    }

    private static func scopeKey(_ scope: RewriteScope) -> String {
        switch scope {
        case .global:
            return "global"
        case .browser(let bundleID):
            return "browser:\(bundleID.lowercased())"
        case .rule(let id):
            return "rule:\(id.uuidString)"
        }
    }
}
