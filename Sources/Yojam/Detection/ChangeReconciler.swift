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
        let handlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        let currentIds = Set(
            handlers.compactMap { Bundle(url: $0)?.bundleIdentifier })

        for appURL in handlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != "com.yojam.app",
                  !knownBundleIds.contains(bundleId) else { continue }
            appDiscovered(bundleId: bundleId, appURL: appURL)
        }

        let removed = knownBundleIds.subtracting(currentIds)
        for bundleId in removed {
            browserManager.handleAppRemoved(bundleId: bundleId)
            ruleEngine.disableRulesForApp(bundleId)
        }
        knownBundleIds = currentIds
    }

    func appDiscovered(bundleId: String, appURL: URL) {
        guard bundleId != "com.yojam.app",
              !knownBundleIds.contains(bundleId) else { return }
        browserManager.handleAppInstalled(bundleId: bundleId, appURL: appURL)
        ruleEngine.enableRulesForApp(bundleId)
        knownBundleIds.insert(bundleId)
    }
}
