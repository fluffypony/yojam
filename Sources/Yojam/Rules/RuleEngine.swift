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
        let sorted = RuleOrdering.enabled(rules)
        sortedEnabledRulesCache = sorted
        return sorted
    }

    var orderedRules: [Rule] {
        RuleOrdering.sorted(rules)
    }

    func evaluate(_ url: URL, sourceAppBundleId: String? = nil) -> Rule? {
        for rule in sortedEnabledRules {
            let result = RuleMatcher.evaluate(
                url: url,
                against: rule,
                sourceApp: sourceAppBundleId,
                machineIdentifier: settingsStore.sharedStore.localMachineIdentifier
            )
            guard result.matched else { continue }
            // §32: Check match before expensive LaunchServices IPC
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
        RuleMatcher.evaluate(
            url: url,
            against: rule,
            sourceApp: nil,
            machineIdentifier: settingsStore.sharedStore.localMachineIdentifier
        ).matched
    }

    func evaluateDetailed(_ url: URL, rule: Rule, sourceApp: String? = nil) -> RuleMatchResult {
        RuleMatcher.evaluate(
            url: url,
            against: rule,
            sourceApp: sourceApp,
            machineIdentifier: settingsStore.sharedStore.localMachineIdentifier
        )
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
        stampRuleChange(&r, previous: nil)
        rules.append(r)
        save()
    }

    func updateRule(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            var r = rule
            stampRuleChange(&r, previous: rules[idx])
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
            targetBrowserEntryId: original.targetBrowserEntryId,
            isBuiltIn: false,
            priority: original.priority,
            stripUTMParams: original.stripUTMParams,
            rewriteRules: original.rewriteRules,
            sourceAppBundleId: original.sourceAppBundleId,
            sourceAppName: original.sourceAppName,
            machineScopeIdentifiers: original.machineScopeIdentifiers,
            machineScopeNames: original.machineScopeNames,
            machineScopeModifiedAt: original.machineScopeModifiedAt,
            firefoxContainer: original.firefoxContainer,
            targetDisplayUUID: original.targetDisplayUUID,
            targetDisplayIndex: original.targetDisplayIndex,
            metadata: original.metadata,
            ruleProfileId: original.ruleProfileId,
            ruleOpenInPrivateWindow: original.ruleOpenInPrivateWindow,
            ruleCustomLaunchArgs: original.ruleCustomLaunchArgs,
            ruleOpenAsNewInstance: original.ruleOpenAsNewInstance)
        stampRuleChange(&copy, previous: nil)
        rules.append(copy)
        save()
    }

    /// Reset a built-in rule back to its factory definition, preserving enabled state.
    func resetBuiltInRule(_ id: UUID) {
        guard let original = BuiltInRules.all.first(where: { $0.id == id }),
              let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        var reset = original
        reset.enabled = rules[idx].enabled
        reset.priority = rules[idx].priority
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

    func moveRule(draggedId: UUID, to currentId: UUID) {
        guard draggedId != currentId else { return }
        var ordered = orderedRules
        guard let fromIndex = ordered.firstIndex(where: { $0.id == draggedId }),
              let toIndex = ordered.firstIndex(where: { $0.id == currentId })
        else { return }
        ordered.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        reindexPriorities(&ordered)
        rules = ordered
        save()
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

    private func stampRuleChange(_ rule: inout Rule, previous: Rule?) {
        let now = Date()
        if let previous {
            if normalizedMachineScope(rule.machineScopeIdentifiers)
                != normalizedMachineScope(previous.machineScopeIdentifiers) {
                rule.machineScopeModifiedAt = now
            }
        } else if rule.machineScopeModifiedAt == nil {
            rule.machineScopeModifiedAt = now
        }
        rule.lastModifiedAt = now
    }

    private func reindexPriorities(_ ordered: inout [Rule]) {
        let now = Date()
        for index in ordered.indices {
            let priority = (index + 1) * 10
            guard ordered[index].priority != priority else { continue }
            ordered[index].priority = priority
            ordered[index].lastModifiedAt = now
        }
    }

    private func normalizedMachineScope(_ ids: [String]?) -> [String] {
        (ids ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
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
