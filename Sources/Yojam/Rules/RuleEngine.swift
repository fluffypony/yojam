import Foundation
import AppKit

@MainActor
final class RuleEngine: ObservableObject {
    @Published var rules: [Rule] = []
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.rules = settingsStore.loadRules()
        autoDisableUninstalledRules()
    }

    func evaluate(_ url: URL, sourceAppBundleId: String? = nil) -> Rule? {
        let sorted = rules.filter(\.enabled).sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return !$0.isBuiltIn }
            return $0.priority < $1.priority
        }
        for rule in sorted {
            if let requiredSourceApp = rule.sourceAppBundleId,
               sourceAppBundleId != requiredSourceApp { continue }
            guard NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: rule.targetBundleId
            ) != nil else { continue }
            if matches(url: url, rule: rule) { return rule }
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

    func addRule(_ rule: Rule) { rules.append(rule); save() }

    func updateRule(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule; save()
        }
    }

    func deleteRule(_ id: UUID) {
        rules.removeAll { $0.id == id && !$0.isBuiltIn }; save()
    }

    func toggleRule(_ id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled.toggle(); save()
        }
    }

    func reloadRules() { rules = settingsStore.loadRules() }

    private func autoDisableUninstalledRules() {
        for i in rules.indices where rules[i].isBuiltIn {
            rules[i].enabled = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: rules[i].targetBundleId) != nil
        }
        save()
    }

    private func save() { settingsStore.saveRules(rules) }

    func exportRules() throws -> Data {
        try JSONEncoder().encode(rules.filter { !$0.isBuiltIn })
    }

    func importRules(from data: Data) throws {
        let imported = try JSONDecoder().decode([Rule].self, from: data)
        rules.append(contentsOf: imported); save()
    }
}
