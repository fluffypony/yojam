import Foundation

/// Loads a `RoutingConfiguration` snapshot from `SharedRoutingStore` without
/// requiring AppKit or `@MainActor`. Usable from the main app, native host,
/// CLI, and extensions.
public enum RoutingSnapshotLoader {
    public static func loadConfiguration(
        from store: SharedRoutingStore,
        installedBundleIdsOverride: Set<String>? = nil
    ) -> RoutingConfiguration? {
        let defaults = store.defaults
        let decoder = JSONDecoder()

        let browsers: [BrowserEntry] =
            (try? decoder.decode([BrowserEntry].self,
                from: defaults.data(forKey: SharedRoutingStore.Keys.browsers) ?? Data())) ?? []
        let emailClients: [BrowserEntry] =
            (try? decoder.decode([BrowserEntry].self,
                from: defaults.data(forKey: SharedRoutingStore.Keys.emailClients) ?? Data())) ?? []
        let rules: [Rule] =
            (try? decoder.decode([Rule].self,
                from: defaults.data(forKey: SharedRoutingStore.Keys.rules) ?? Data())) ?? []
        let globalRewrites: [URLRewriteRule] =
            (try? decoder.decode([URLRewriteRule].self,
                from: defaults.data(forKey: SharedRoutingStore.Keys.globalRewriteRules) ?? Data())) ?? []
        // Stored format is [String: [String: Int]] (domain → {entryId: count}).
        // Flatten to [String: String] (domain → entryId) using the same
        // confidence logic as RoutingSuggestionEngine.allSuggestions().
        let learned: [String: String]
        if let rawData = defaults.data(forKey: SharedRoutingStore.Keys.learnedDomainPreferences),
           let full = try? decoder.decode([String: [String: Int]].self, from: rawData) {
            var flat: [String: String] = [:]
            for (domain, prefs) in full {
                let total = prefs.values.reduce(0, +)
                guard total >= 3 else { continue }
                if let (entryId, count) = prefs.max(by: { $0.value < $1.value }),
                   Double(count) / Double(total) > 0.7 {
                    flat[domain] = entryId
                }
            }
            learned = flat
        } else {
            learned = [:]
        }

        let utm = Set((defaults.stringArray(forKey: SharedRoutingStore.Keys.utmStripList) ?? [])
            .map { $0.lowercased() })
        let activation = ActivationMode(rawValue: defaults.string(forKey: SharedRoutingStore.Keys.activationMode) ?? "")
            ?? .always
        let defaultSelection = DefaultSelectionBehavior(
            rawValue: defaults.string(forKey: SharedRoutingStore.Keys.defaultSelection) ?? "")
            ?? .alwaysFirst
        let isEnabled = (defaults.object(forKey: SharedRoutingStore.Keys.isEnabled) as? Bool) ?? true
        let globalUTMStripping = (defaults.object(forKey: SharedRoutingStore.Keys.globalUTMStripping) as? Bool) ?? false
        let shortlinkEnabled = (defaults.object(forKey: SharedRoutingStore.Keys.shortlinkResolutionEnabled) as? Bool) ?? false
        let lastUsedBrowserIdStr = defaults.string(forKey: SharedRoutingStore.Keys.lastUsedBrowserId)
        let lastUsedEmailIdStr = defaults.string(forKey: SharedRoutingStore.Keys.lastUsedEmailId)

        // Filter by persisted isInstalled + optional installed override
        let filterEntry: (BrowserEntry) -> Bool = { entry in
            guard entry.enabled && entry.isInstalled else { return false }
            if let override = installedBundleIdsOverride {
                return override.contains(entry.bundleIdentifier)
            }
            return true
        }

        // Filter rules for installed targets using the persisted set
        let installedIds: Set<String>
        if let override = installedBundleIdsOverride {
            installedIds = override
        } else if let savedIds = defaults.stringArray(forKey: SharedRoutingStore.Keys.installedBundleIds) {
            installedIds = Set(savedIds)
        } else {
            // No installed-IDs data available; include all rules as-is
            installedIds = Set(rules.map(\.targetBundleId))
        }

        let filteredRules = rules.filter { $0.enabled }.filter { rule in
            let isPath = rule.targetBundleId.hasPrefix("/")
            return isPath || installedIds.contains(rule.targetBundleId)
        }.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return !$0.isBuiltIn }
            return $0.priority < $1.priority
        }

        return RoutingConfiguration(
            browsers: browsers.filter(filterEntry),
            emailClients: emailClients.filter(filterEntry),
            rules: filteredRules,
            globalRewriteRules: globalRewrites.filter { $0.enabled && $0.scope == .global },
            utmStripParameters: utm,
            globalUTMStrippingEnabled: globalUTMStripping,
            activationMode: activation,
            defaultSelectionBehavior: defaultSelection,
            isEnabled: isEnabled,
            learnedDomainPreferences: learned,
            lastUsedBrowserId: lastUsedBrowserIdStr.flatMap(UUID.init(uuidString:)),
            lastUsedEmailClientId: lastUsedEmailIdStr.flatMap(UUID.init(uuidString:)),
            shortlinkResolutionEnabled: shortlinkEnabled
        )
    }
}
