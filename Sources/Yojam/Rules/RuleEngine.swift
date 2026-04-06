import Foundation
import AppKit

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
        let urlString = url.absoluteString
        let host = url.host?.lowercased() ?? ""
        let pattern = rule.pattern.lowercased()
        switch rule.matchType {
        case .domain:
            return host == pattern
        case .domainSuffix:
            return host == pattern || host.hasSuffix(".\(pattern)")
        case .urlPrefix:
            return urlString.lowercased().hasPrefix(pattern)
        case .urlContains:
            return urlString.lowercased().contains(pattern)
        case .regex:
            return RegexMatcher.matches(urlString, pattern: rule.pattern)
        }
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
        rules.removeAll { $0.id == id && !$0.isBuiltIn }; save()
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
