import Foundation
import YojamCore

@MainActor
final class RoutingSuggestionEngine {
    private var domainPreferences: [String: [String: Int]] = [:]
    private let minimumConfidence = 3
    private let sharedDefaults: UserDefaults
    // P4: Debounce UserDefaults writes to avoid per-click I/O
    private let saveDebouncer = Debouncer(delay: 2.0)

    init() {
        self.sharedDefaults = SharedRoutingStore().defaults
        if let data = sharedDefaults.data(forKey: SharedRoutingStore.Keys.learnedDomainPreferences),
           let decoded = try? JSONDecoder().decode(
               [String: [String: Int]].self, from: data
           ) {
            domainPreferences = decoded
        }
    }

    // Uses entry ID (UUID string) to distinguish profiles (§13.1)
    func recordChoice(domain: String, entryId: String) {
        var prefs = domainPreferences[domain, default: [:]]
        prefs[entryId, default: 0] += 1
        domainPreferences[domain] = prefs
        // §37: Cap unbounded growth
        if domainPreferences.count > 1000 {
            let sorted = domainPreferences.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }
            domainPreferences = Dictionary(uniqueKeysWithValues: sorted.prefix(800).map { ($0.key, $0.value) })
        }
        debouncedSave()
    }

    func suggestion(for domain: String) -> String? {
        guard let prefs = domainPreferences[domain] else { return nil }
        let total = prefs.values.reduce(0, +)
        guard total >= minimumConfidence else { return nil }
        if let (entryId, count) = prefs.max(by: { $0.value < $1.value }),
           Double(count) / Double(total) > 0.7 {
            return entryId
        }
        return nil
    }

    /// Returns a flat domain → entryId mapping of all confident suggestions,
    /// for use in `RoutingConfiguration`.
    func allSuggestions() -> [String: String] {
        var result: [String: String] = [:]
        for (domain, prefs) in domainPreferences {
            let total = prefs.values.reduce(0, +)
            guard total >= minimumConfidence else { continue }
            if let (entryId, count) = prefs.max(by: { $0.value < $1.value }),
               Double(count) / Double(total) > 0.7 {
                result[domain] = entryId
            }
        }
        return result
    }

    func clearAll() { domainPreferences = [:]; save() }

    private func debouncedSave() {
        saveDebouncer.debounce { [weak self] in self?.save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(domainPreferences) {
            sharedDefaults.set(data, forKey: SharedRoutingStore.Keys.learnedDomainPreferences)
        }
    }
}
