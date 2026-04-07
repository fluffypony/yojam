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
    // P11: Cache (bundleId, appURL, mtime) to skip re-reading Info.plist
    // when the app binary hasn't changed on disk.
    private var appInfoCache: [URL: (bundleId: String, mtime: Date)] = [:]

    init(browserManager: BrowserManager, ruleEngine: RuleEngine) {
        self.browserManager = browserManager
        self.ruleEngine = ruleEngine
        knownBrowserIds = Set(browserManager.browsers.map(\.bundleIdentifier))
        knownEmailIds = Set(browserManager.emailClients.map(\.bundleIdentifier))
    }

    // P11: Resolve bundleId from appURL using mtime cache to skip redundant reads
    private func cachedBundleId(for appURL: URL) -> String? {
        let mtime = (try? FileManager.default.attributesOfItem(
            atPath: appURL.path)[.modificationDate] as? Date) ?? .distantPast
        if let cached = appInfoCache[appURL], cached.mtime == mtime {
            return cached.bundleId
        }
        guard let infoDict = CFBundleCopyInfoDictionaryForURL(appURL as CFURL) as NSDictionary?,
              let bundleId = infoDict["CFBundleIdentifier"] as? String else { return nil }
        appInfoCache[appURL] = (bundleId, mtime)
        return bundleId
    }

    func reconcile() {
        // HTTP handler discovery
        let httpHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        // P11: Use mtime-cached bundle ID lookup instead of Bundle(url:) per handler
        var currentIds = Set(httpHandlers.compactMap { cachedBundleId(for: $0) })

        for appURL in httpHandlers {
            guard let bundleId = cachedBundleId(for: appURL),
                  bundleId != Bundle.main.bundleIdentifier,
                  !knownBrowserIds.contains(bundleId) else { continue }
            appDiscovered(bundleId: bundleId, appURL: appURL)
        }

        // mailto: handler discovery
        let mailtoHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "mailto:test@example.com")!)
        var emailClientsChanged = false
        for appURL in mailtoHandlers {
            guard let bundleId = cachedBundleId(for: appURL),
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
                let name = (CFBundleCopyInfoDictionaryForURL(appURL as CFURL) as NSDictionary?)?["CFBundleName"] as? String
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
        // P11: Defer the LSCopyDefault/urlForApplication IPC to a background task
        // for non-path bundle IDs, then apply results on main actor.
        let removed = knownBundleIds.subtracting(currentIds)
        let pathRemoved = removed.filter { $0.hasPrefix("/") }
        let bundleRemoved = removed.subtracting(pathRemoved)

        // Path-based: check synchronously (just a stat call)
        for bundleId in pathRemoved {
            if FileManager.default.isExecutableFile(atPath: bundleId) {
                currentIds.insert(bundleId)
            } else {
                browserManager.handleAppRemoved(bundleId: bundleId)
                ruleEngine.disableRulesForApp(bundleId)
            }
        }

        // Bundle-ID-based: defer LS IPC to background
        if !bundleRemoved.isEmpty {
            let idsToCheck = bundleRemoved
            Task.detached {
                var stillInstalled: Set<String> = []
                for bundleId in idsToCheck {
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                        stillInstalled.insert(bundleId)
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    for bundleId in idsToCheck {
                        if stillInstalled.contains(bundleId) {
                            // App still exists — keep in known set
                        } else {
                            self.browserManager.handleAppRemoved(bundleId: bundleId)
                            self.ruleEngine.disableRulesForApp(bundleId)
                        }
                    }
                }
            }
        }
        // B-PATHS: Verify path-based entries that don't come from urlsForApplications
        var pathBrowsersChanged = false
        for i in browserManager.browsers.indices {
            let entry = browserManager.browsers[i]
            guard entry.bundleIdentifier.hasPrefix("/") else { continue }
            let exists = FileManager.default.isExecutableFile(atPath: entry.bundleIdentifier)
            if entry.isInstalled != exists {
                browserManager.browsers[i].isInstalled = exists
                pathBrowsersChanged = true
            }
        }
        if pathBrowsersChanged { browserManager.save() }

        // P11: Rebuild from currentIds which already used the mtime cache
        knownBrowserIds = currentIds.intersection(
            knownBrowserIds.union(Set(httpHandlers.compactMap { cachedBundleId(for: $0) }))
        )
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
