import AppKit
import YojamCore

@MainActor
final class ChangeReconciler {
    private let browserManager: BrowserManager
    private let ruleEngine: RuleEngine
    private var knownBundleIds: Set<String> = []

    init(browserManager: BrowserManager, ruleEngine: RuleEngine) {
        self.browserManager = browserManager
        self.ruleEngine = ruleEngine
        // §9: Track both browser and email client bundle IDs
        knownBundleIds = Set(browserManager.browsers.map(\.bundleIdentifier))
            .union(browserManager.emailClients.map(\.bundleIdentifier))
    }

    func reconcile() {
        // HTTP handler discovery
        let httpHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        var currentIds = Set(
            httpHandlers.compactMap { Bundle(url: $0)?.bundleIdentifier })

        for appURL in httpHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier,
                  !knownBundleIds.contains(bundleId) else { continue }
            appDiscovered(bundleId: bundleId, appURL: appURL)
        }

        // mailto: handler discovery
        let mailtoHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "mailto:test@example.com")!)
        var emailClientsChanged = false
        for appURL in mailtoHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier else { continue }
            // §9: Add mailto handlers to currentIds
            currentIds.insert(bundleId)
            knownBundleIds.insert(bundleId)
            if let existingIdx = browserManager.emailClients.firstIndex(where: {
                $0.bundleIdentifier == bundleId
            }) {
                if !browserManager.emailClients[existingIdx].isInstalled {
                    browserManager.emailClients[existingIdx].isInstalled = true
                    browserManager.emailClients[existingIdx].lastSeenAt = Date()
                    emailClientsChanged = true
                }
            } else {
                let name = bundle.infoDictionary?["CFBundleName"] as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                let entry = BrowserEntry(
                    bundleIdentifier: bundleId, displayName: name,
                    position: browserManager.emailClients.count,
                    source: .autoDetected)
                browserManager.emailClients.append(entry)
                emailClientsChanged = true
            }
        }
        if emailClientsChanged {
            browserManager.saveEmailClients()
        }

        // §9: Verify actual existence before removing — retain manual path-based entries
        let removed = knownBundleIds.subtracting(currentIds)
        for bundleId in removed {
            let stillExists: Bool
            if bundleId.hasPrefix("/") {
                stillExists = FileManager.default.isExecutableFile(atPath: bundleId)
            } else {
                stillExists = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
            }

            if stillExists {
                currentIds.insert(bundleId)
            } else {
                browserManager.handleAppRemoved(bundleId: bundleId)
                ruleEngine.disableRulesForApp(bundleId)
            }
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
