import AppKit

@MainActor
final class ChangeReconciler {
    private let browserManager: BrowserManager
    private let ruleEngine: RuleEngine
    private var knownBundleIds: Set<String> = []

    init(browserManager: BrowserManager, ruleEngine: RuleEngine) {
        self.browserManager = browserManager
        self.ruleEngine = ruleEngine
        knownBundleIds = Set(browserManager.browsers.map(\.bundleIdentifier))
    }

    func reconcile() {
        // HTTP handler discovery
        let httpHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        let currentIds = Set(
            httpHandlers.compactMap { Bundle(url: $0)?.bundleIdentifier })

        for appURL in httpHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier,
                  !knownBundleIds.contains(bundleId) else { continue }
            appDiscovered(bundleId: bundleId, appURL: appURL)
        }

        // mailto: handler discovery (§9.2)
        let mailtoHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "mailto:test@example.com")!)
        for appURL in mailtoHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier else { continue }
            if !browserManager.emailClients.contains(where: {
                $0.bundleIdentifier == bundleId
            }) {
                let name = bundle.infoDictionary?["CFBundleName"] as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                let entry = BrowserEntry(
                    bundleIdentifier: bundleId, displayName: name,
                    position: browserManager.emailClients.count,
                    source: .autoDetected)
                browserManager.emailClients.append(entry)
            }
        }

        let removed = knownBundleIds.subtracting(currentIds)
        for bundleId in removed {
            browserManager.handleAppRemoved(bundleId: bundleId)
            ruleEngine.disableRulesForApp(bundleId)
        }
        knownBundleIds = currentIds
    }

    func appDiscovered(bundleId: String, appURL: URL) {
        guard bundleId != Bundle.main.bundleIdentifier,
              !knownBundleIds.contains(bundleId) else { return }
        browserManager.handleAppInstalled(bundleId: bundleId, appURL: appURL)
        ruleEngine.enableRulesForApp(bundleId)
        knownBundleIds.insert(bundleId)
    }
}
