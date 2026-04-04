import Foundation
import Combine

@MainActor
final class ICloudSyncManager {
    private let settingsStore: SettingsStore
    private let kvStore = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var cancellable: AnyCancellable?

    init(settingsStore: SettingsStore) { self.settingsStore = settingsStore }

    func startSync() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRemoteChange() }
        }
        kvStore.synchronize()
        pushToCloud()

        // Observe local changes and push continuously (§11.2)
        cancellable = settingsStore.objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushToCloud() }
    }

    func stopSync() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        cancellable?.cancel()
        cancellable = nil
    }

    func pushToCloud() {
        guard settingsStore.iCloudSyncEnabled else { return }
        if let data = try? JSONEncoder().encode(settingsStore.loadBrowsers()) {
            kvStore.set(data, forKey: "sync_browsers")
        }
        let userRules = settingsStore.loadRules().filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(userRules) {
            kvStore.set(data, forKey: "sync_rules")
        }
        if let data = try? JSONEncoder().encode(
            settingsStore.loadGlobalRewriteRules()
        ) {
            kvStore.set(data, forKey: "sync_rewrites")
        }
        kvStore.set(settingsStore.utmStripList, forKey: "sync_utmStripList")
        kvStore.synchronize()
    }

    private func handleRemoteChange() {
        guard settingsStore.iCloudSyncEnabled else { return }
        if let data = kvStore.data(forKey: "sync_browsers"),
           let remote = try? JSONDecoder().decode(
               [BrowserEntry].self, from: data
           ) {
            let merged = SyncConflictResolver.mergeBrowserLists(
                local: settingsStore.loadBrowsers(), remote: remote)
            settingsStore.saveBrowsers(merged)
        }
        if let data = kvStore.data(forKey: "sync_rules"),
           let remote = try? JSONDecoder().decode(
               [Rule].self, from: data
           ) {
            // Preserve local user's built-in rule states (§11.3)
            let localBuiltIns = settingsStore.loadRules().filter { $0.isBuiltIn }
            let local = settingsStore.loadRules().filter { !$0.isBuiltIn }
            let merged = SyncConflictResolver.mergeRules(
                local: local, remote: remote)
            var allRules = localBuiltIns
            allRules.append(contentsOf: merged)
            settingsStore.saveRules(allRules)
        }
        // Pull rewrite rules (§11.1)
        if let data = kvStore.data(forKey: "sync_rewrites"),
           let remote = try? JSONDecoder().decode(
               [URLRewriteRule].self, from: data
           ) {
            settingsStore.saveGlobalRewriteRules(remote)
        }
        if let list = kvStore.array(forKey: "sync_utmStripList") as? [String] {
            settingsStore.utmStripList = list
        }
    }
}
