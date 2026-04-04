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
        let encoder = JSONEncoder()
        do {
            kvStore.set(try encoder.encode(settingsStore.loadBrowsers()), forKey: "sync_browsers")
        } catch {
            YojamLogger.shared.log("iCloud push browsers failed: \(error.localizedDescription)")
        }
        do {
            let userRules = settingsStore.loadRules().filter { !$0.isBuiltIn }
            kvStore.set(try encoder.encode(userRules), forKey: "sync_rules")
        } catch {
            YojamLogger.shared.log("iCloud push rules failed: \(error.localizedDescription)")
        }
        do {
            kvStore.set(try encoder.encode(settingsStore.loadGlobalRewriteRules()), forKey: "sync_rewrites")
        } catch {
            YojamLogger.shared.log("iCloud push rewrites failed: \(error.localizedDescription)")
        }
        kvStore.set(settingsStore.utmStripList, forKey: "sync_utmStripList")
        kvStore.synchronize()
    }

    private func handleRemoteChange() {
        guard settingsStore.iCloudSyncEnabled else { return }
        let decoder = JSONDecoder()
        if let data = kvStore.data(forKey: "sync_browsers") {
            do {
                let remote = try decoder.decode([BrowserEntry].self, from: data)
                let merged = SyncConflictResolver.mergeBrowserLists(
                    local: settingsStore.loadBrowsers(), remote: remote)
                settingsStore.saveBrowsers(merged)
            } catch {
                YojamLogger.shared.log("iCloud pull browsers failed: \(error.localizedDescription)")
            }
        }
        if let data = kvStore.data(forKey: "sync_rules") {
            do {
                let remote = try decoder.decode([Rule].self, from: data)
                // Preserve local user's built-in rule states
                let localBuiltIns = settingsStore.loadRules().filter { $0.isBuiltIn }
                let local = settingsStore.loadRules().filter { !$0.isBuiltIn }
                let merged = SyncConflictResolver.mergeRules(
                    local: local, remote: remote)
                var allRules = localBuiltIns
                allRules.append(contentsOf: merged)
                settingsStore.saveRules(allRules)
            } catch {
                YojamLogger.shared.log("iCloud pull rules failed: \(error.localizedDescription)")
            }
        }
        if let data = kvStore.data(forKey: "sync_rewrites") {
            do {
                let remote = try decoder.decode([URLRewriteRule].self, from: data)
                settingsStore.saveGlobalRewriteRules(remote)
            } catch {
                YojamLogger.shared.log("iCloud pull rewrites failed: \(error.localizedDescription)")
            }
        }
        if let list = kvStore.array(forKey: "sync_utmStripList") as? [String] {
            settingsStore.utmStripList = list
        }
    }
}
