import AppKit
import YojamCore

@MainActor
final class ChangeReconciler {
    private let browserManager: BrowserManager
    private let ruleEngine: RuleEngine
    // §9: Track browser and email client IDs independently to prevent
    // removing an app that's both a browser and email client from flipping
    // isInstalled=false on both when removed from only one list.
    private var knownBrowserIds: Set<String> = []
    private var knownEmailIds: Set<String> = []
    private var knownBundleIds: Set<String> {
        knownBrowserIds.union(knownEmailIds)
    }

    init(browserManager: BrowserManager, ruleEngine: RuleEngine) {
        self.browserManager = browserManager
        self.ruleEngine = ruleEngine
        knownBrowserIds = Set(browserManager.browsers.map(\.bundleIdentifier))
        knownEmailIds = Set(browserManager.emailClients.map(\.bundleIdentifier))
    }

    func reconcile() {
        // HTTP handler discovery
        let httpHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        var currentIds = Set(
            httpHandlers.compactMap { Bundle(url: $0)?.bundleIdentifier })

        for appURL in httpHandlers {
            guard let bundleId = CFBundleCopyInfoDictionaryForURL(appURL as CFURL)
                    .map({ ($0 as NSDictionary)["CFBundleIdentifier"] as? String }) ?? nil,
                  bundleId != Bundle.main.bundleIdentifier,
                  !knownBrowserIds.contains(bundleId) else { continue }
            appDiscovered(bundleId: bundleId, appURL: appURL)
        }

        // mailto: handler discovery
        let mailtoHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "mailto:test@example.com")!)
        var emailClientsChanged = false
        for appURL in mailtoHandlers {
            guard let bundleId = CFBundleCopyInfoDictionaryForURL(appURL as CFURL)
                    .map({ ($0 as NSDictionary)["CFBundleIdentifier"] as? String }) ?? nil,
                  bundleId != Bundle.main.bundleIdentifier else { continue }
            currentIds.insert(bundleId)
            knownEmailIds.insert(bundleId)
            if let existingIdx = browserManager.emailClients.firstIndex(where: {
                $0.bundleIdentifier == bundleId
            }) {
                if !browserManager.emailClients[existingIdx].isInstalled {
                    browserManager.emailClients[existingIdx].isInstalled = true
                    browserManager.emailClients[existingIdx].lastSeenAt = Date()
                    emailClientsChanged = true
                }
            } else {
                let infoDict = CFBundleCopyInfoDictionaryForURL(appURL as CFURL) as NSDictionary?
                let name = infoDict?["CFBundleName"] as? String
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
        knownBrowserIds = currentIds.intersection(knownBrowserIds.union(
            Set(httpHandlers.compactMap {
                CFBundleCopyInfoDictionaryForURL($0 as CFURL)
                    .map { ($0 as NSDictionary)["CFBundleIdentifier"] as? String } ?? nil
            })
        ))
        knownEmailIds = Set(browserManager.emailClients.map(\.bundleIdentifier))

        // Persist installed bundle IDs for CLI/native-host preview filtering
        let allInstalled = Array(knownBundleIds)
        SharedRoutingStore().defaults.set(allInstalled,
            forKey: SharedRoutingStore.Keys.installedBundleIds)
    }

    func appDiscovered(bundleId: String, appURL: URL) {
        guard bundleId != Bundle.main.bundleIdentifier,
              !knownBrowserIds.contains(bundleId) else { return }
        browserManager.handleAppInstalled(bundleId: bundleId, appURL: appURL)
        ruleEngine.enableRulesForApp(bundleId)
        knownBrowserIds.insert(bundleId)
    }
}
