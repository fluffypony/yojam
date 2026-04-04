import Foundation
import Combine

@MainActor
final class ICloudSyncManager {
    private let settingsStore: SettingsStore
    private let kvStore = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var cancellable: AnyCancellable?
    private var lastPullTime: Date = .distantPast
    // Suppress push-back for 3 seconds after a pull to outlast the 2-second debounce
    private let pullSuppressionWindow: TimeInterval = 3.0

    init(settingsStore: SettingsStore) { self.settingsStore = settingsStore }

    func startSync() {
        // 1. Subscribe to remote changes first
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRemoteChange() }
        }

        // 2. Pull from cloud before pushing local
        kvStore.synchronize()
        handleRemoteChange()

        // 3. Push local state
        pushToCloud()

        // 4. Start observing local changes
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
        guard settingsStore.iCloudSyncEnabled,
              Date().timeIntervalSince(lastPullTime) > pullSuppressionWindow else { return }
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

        // Sync general preferences
        kvStore.set(settingsStore.activationMode.rawValue, forKey: "sync_activationMode")
        kvStore.set(settingsStore.defaultSelectionBehavior.rawValue, forKey: "sync_defaultSelection")
        kvStore.set(settingsStore.verticalThreshold, forKey: "sync_verticalThreshold")
        kvStore.set(settingsStore.soundEffectsEnabled, forKey: "sync_soundEffects")
        kvStore.set(settingsStore.globalUTMStrippingEnabled, forKey: "sync_globalUTMStripping")
        kvStore.set(settingsStore.clipboardMonitoringEnabled, forKey: "sync_clipboardMonitoring")
        kvStore.set(settingsStore.universalClickModifierEnabled, forKey: "sync_universalClickModifier")
        kvStore.set(settingsStore.cmdShiftClickEnabled, forKey: "sync_cmdShiftClick")
        kvStore.set(settingsStore.ctrlShiftClickEnabled, forKey: "sync_ctrlShiftClick")
        kvStore.set(settingsStore.cmdOptionClickEnabled, forKey: "sync_cmdOptionClick")
        kvStore.set(settingsStore.debugLoggingEnabled, forKey: "sync_debugLogging")
        kvStore.set(settingsStore.periodicRescanInterval, forKey: "sync_periodicRescanInterval")

        kvStore.synchronize()
    }

    private func handleRemoteChange() {
        guard settingsStore.iCloudSyncEnabled else { return }
        lastPullTime = Date()

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
                let local = settingsStore.loadGlobalRewriteRules()
                let merged = SyncConflictResolver.mergeRewriteRules(
                    local: local, remote: remote)
                settingsStore.saveGlobalRewriteRules(merged)
            } catch {
                YojamLogger.shared.log("iCloud pull rewrites failed: \(error.localizedDescription)")
            }
        }
        if let list = kvStore.array(forKey: "sync_utmStripList") as? [String] {
            settingsStore.utmStripList = list
        }

        // Pull general preferences
        if let raw = kvStore.string(forKey: "sync_activationMode"),
           let mode = ActivationMode(rawValue: raw) {
            settingsStore.activationMode = mode
        }
        if let raw = kvStore.string(forKey: "sync_defaultSelection"),
           let behavior = DefaultSelectionBehavior(rawValue: raw) {
            settingsStore.defaultSelectionBehavior = behavior
        }
        if kvStore.object(forKey: "sync_verticalThreshold") != nil {
            settingsStore.verticalThreshold = Int(kvStore.longLong(forKey: "sync_verticalThreshold"))
        }
        if kvStore.object(forKey: "sync_soundEffects") != nil {
            settingsStore.soundEffectsEnabled = kvStore.bool(forKey: "sync_soundEffects")
        }
        if kvStore.object(forKey: "sync_globalUTMStripping") != nil {
            settingsStore.globalUTMStrippingEnabled = kvStore.bool(forKey: "sync_globalUTMStripping")
        }
        if kvStore.object(forKey: "sync_clipboardMonitoring") != nil {
            settingsStore.clipboardMonitoringEnabled = kvStore.bool(forKey: "sync_clipboardMonitoring")
        }
        if kvStore.object(forKey: "sync_universalClickModifier") != nil {
            settingsStore.universalClickModifierEnabled = kvStore.bool(forKey: "sync_universalClickModifier")
        }
        if kvStore.object(forKey: "sync_cmdShiftClick") != nil {
            settingsStore.cmdShiftClickEnabled = kvStore.bool(forKey: "sync_cmdShiftClick")
        }
        if kvStore.object(forKey: "sync_ctrlShiftClick") != nil {
            settingsStore.ctrlShiftClickEnabled = kvStore.bool(forKey: "sync_ctrlShiftClick")
        }
        if kvStore.object(forKey: "sync_cmdOptionClick") != nil {
            settingsStore.cmdOptionClickEnabled = kvStore.bool(forKey: "sync_cmdOptionClick")
        }
        if kvStore.object(forKey: "sync_debugLogging") != nil {
            settingsStore.debugLoggingEnabled = kvStore.bool(forKey: "sync_debugLogging")
        }
        if kvStore.object(forKey: "sync_periodicRescanInterval") != nil {
            settingsStore.periodicRescanInterval = kvStore.double(forKey: "sync_periodicRescanInterval")
        }
    }
}
