import Foundation
import AppKit
import YojamCore

@MainActor
final class RuleEngine: ObservableObject {
    @Published var rules: [Rule] = [] {
        didSet { sortedEnabledRulesCache = nil }
    }
    private let settingsStore: SettingsStore
    // §33: Cache sorted/filtered rules to avoid re-sorting on every URL
    private var sortedEnabledRulesCache: [Rule]?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.rules = settingsStore.loadRules()
        autoDisableUninstalledRules()
    }

    private var sortedEnabledRules: [Rule] {
        if let cached = sortedEnabledRulesCache { return cached }
        let sorted = rules.filter(\.enabled).sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return !$0.isBuiltIn }
            return $0.priority < $1.priority
        }
        sortedEnabledRulesCache = sorted
        return sorted
    }

    func evaluate(_ url: URL, sourceAppBundleId: String? = nil) -> Rule? {
        for rule in sortedEnabledRules {
            if let requiredSourceApp = rule.sourceAppBundleId,
               sourceAppBundleId != requiredSourceApp { continue }
            // §32: Check match before expensive LaunchServices IPC
            guard matches(url: url, rule: rule) else { continue }
            // §18: Support bare executable paths in addition to bundle IDs
            let isPath = rule.targetBundleId.hasPrefix("/")
            guard isPath
                ? FileManager.default.isExecutableFile(atPath: rule.targetBundleId)
                : (NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: rule.targetBundleId) != nil)
            else { continue }
            return rule
        }
        return nil
    }

    func matches(url: URL, rule: Rule) -> Bool {
        RuleMatcher.evaluate(url: url, against: rule, sourceApp: nil).matched
    }

    func evaluateDetailed(_ url: URL, rule: Rule, sourceApp: String? = nil) -> RuleMatchResult {
        RuleMatcher.evaluate(url: url, against: rule, sourceApp: sourceApp)
    }

    func enableRulesForApp(_ bundleId: String) {
        for i in rules.indices where rules[i].targetBundleId == bundleId && rules[i].isBuiltIn {
            rules[i].enabled = true
        }
        save()
    }

    func disableRulesForApp(_ bundleId: String) {
        for i in rules.indices where rules[i].targetBundleId == bundleId && rules[i].isBuiltIn {
            rules[i].enabled = false
        }
        save()
    }

    func addRule(_ rule: Rule) {
        var r = rule
        r.lastModifiedAt = Date()
        rules.append(r)
        save()
    }

    func updateRule(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            var r = rule
            r.lastModifiedAt = Date()
            rules[idx] = r
            save()
        }
    }

    func deleteRule(_ id: UUID) {
        // Allow deleting built-in rules too — they get tombstoned in
        // SettingsStore.deletedBuiltInRuleIds so they don't reappear on next load.
        if let rule = rules.first(where: { $0.id == id }), rule.isBuiltIn {
            settingsStore.addDeletedBuiltInRuleId(id)
        }
        rules.removeAll { $0.id == id }
        save()
    }

    /// Clone a rule (built-in or user) into a new editable user rule.
    func duplicateRule(_ id: UUID) {
        guard let original = rules.first(where: { $0.id == id }) else { return }
        var copy = Rule(
            name: original.name + " (Copy)",
            enabled: true,
            matchType: original.matchType,
            pattern: original.pattern,
            targetBundleId: original.targetBundleId,
            targetAppName: original.targetAppName,
            isBuiltIn: false,
            priority: original.priority,
            stripUTMParams: original.stripUTMParams,
            rewriteRules: original.rewriteRules,
            sourceAppBundleId: original.sourceAppBundleId,
            sourceAppName: original.sourceAppName,
            firefoxContainer: original.firefoxContainer,
            targetDisplayUUID: original.targetDisplayUUID,
            targetDisplayIndex: original.targetDisplayIndex,
            metadata: original.metadata)
        copy.lastModifiedAt = Date()
        rules.append(copy)
        save()
    }

    /// Reset a built-in rule back to its factory definition, preserving enabled state.
    func resetBuiltInRule(_ id: UUID) {
        guard let original = BuiltInRules.all.first(where: { $0.id == id }),
              let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        var reset = original
        reset.enabled = rules[idx].enabled
        rules[idx] = reset
        save()
    }

    /// Re-insert any built-ins the user previously deleted.
    func restoreAllBuiltIns() {
        settingsStore.clearDeletedBuiltInRuleIds()
        let existingIds = Set(rules.map(\.id))
        for builtIn in BuiltInRules.all where !existingIds.contains(builtIn.id) {
            rules.append(builtIn)
        }
        save()
    }

    func toggleRule(_ id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled.toggle()
            rules[idx].lastModifiedAt = Date()
            save()
        }
    }

    func reloadRules() { rules = settingsStore.loadRules() }

    private func autoDisableUninstalledRules() {
        var installedCache: [String: Bool] = [:]
        for i in rules.indices where rules[i].isBuiltIn {
            let bundleId = rules[i].targetBundleId
            if installedCache[bundleId] == nil {
                installedCache[bundleId] = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleId) != nil
            }
            if installedCache[bundleId] == false {
                rules[i].enabled = false
            }
        }
        save()
    }

    private func save() {
        sortedEnabledRulesCache = nil
        settingsStore.saveRules(rules)
    }

    func exportRules() throws -> Data {
        try JSONEncoder().encode(rules.filter { !$0.isBuiltIn })
    }

    // §23: Deduplicate on re-import with regex validation
    func importRules(from data: Data) throws {
        let imported = try JSONDecoder().decode([Rule].self, from: data)
        let existingIds = Set(rules.map(\.id))
        let newRules = imported.filter { rule in
            guard !existingIds.contains(rule.id) else { return false }
            if rule.matchType == .regex {
                guard RegexMatcher.isValid(pattern: rule.pattern) else {
                    YojamLogger.shared.log("Skipping imported rule '\(rule.name)': invalid regex")
                    return false
                }
            }
            return true
        }
        rules.append(contentsOf: newRules)
        save()
    }
}
