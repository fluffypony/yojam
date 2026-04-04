import Foundation

@MainActor
final class RoutingSuggestionEngine {
    private var domainPreferences: [String: [String: Int]] = [:]
    private let minimumConfidence = 3
    private let key = "learnedDomainPreferences"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(
               [String: [String: Int]].self, from: data
           ) {
            domainPreferences = decoded
        }
    }

    func recordChoice(domain: String, bundleId: String) {
        var prefs = domainPreferences[domain, default: [:]]
        prefs[bundleId, default: 0] += 1
        domainPreferences[domain] = prefs
        save()
    }

    func suggestion(for domain: String) -> String? {
        guard let prefs = domainPreferences[domain] else { return nil }
        let total = prefs.values.reduce(0, +)
        guard total >= minimumConfidence else { return nil }
        if let (bundleId, count) = prefs.max(by: { $0.value < $1.value }),
           Double(count) / Double(total) > 0.7 {
            return bundleId
        }
        return nil
    }

    func clearAll() { domainPreferences = [:]; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(domainPreferences) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
