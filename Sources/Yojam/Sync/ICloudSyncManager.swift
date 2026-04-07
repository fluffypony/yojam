import Foundation
import Combine
import YojamCore

@MainActor
final class ICloudSyncManager {
    private let settingsStore: SettingsStore
    private let kvStore = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var cancellable: AnyCancellable?
    private var lastPullTime: Date = .distantPast
    // Suppress push-back for 3 seconds after a pull to outlast the 2-second debounce
    private let pullSuppressionWindow: TimeInterval = 3.0
    private var isApplyingRemoteChange = false
    private var pushRescheduled = false
    private var lastPushedHash: Int = 0 // P6: Skip push when payload unchanged
    private var hasReceivedRemoteData = false // B-ICLOUD: Track if we've seen remote data

    // §4: Live references for updating in-memory state after remote changes
    weak var browserManager: BrowserManager?
    weak var ruleEngine: RuleEngine?

    init(settingsStore: SettingsStore) { self.settingsStore = settingsStore }

    func startSync() {
        // 1. Subscribe to remote changes first
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hasReceivedRemoteData = true
                self?.handleRemoteChange()
            }
        }

        // 2. Pull from cloud before pushing local
        kvStore.synchronize()

        // B-ICLOUD: On first sync on this device, check if we have local data.
        // If no local sync_browsers key exists yet, wait for remote data before pushing
        // to avoid overwriting other devices' data with empty local state.
        let hasLocalSyncData = kvStore.data(forKey: "sync_browsers") != nil
        if hasLocalSyncData {
            hasReceivedRemoteData = true
        }
        handleRemoteChange()

        // 3. Schedule initial push after suppression window so it isn't blocked.
        // On new devices without prior sync data, delay push until remote data arrives
        // (up to 10s) to avoid wiping other devices.
        let initialPushDelay = hasLocalSyncData
            ? pullSuppressionWindow + 0.1
            : 10.0
        DispatchQueue.main.asyncAfter(deadline: .now() + initialPushDelay) { [weak self] in
            guard let self else { return }
            // On first device / empty iCloud, no remote notification arrives.
            // Allow push after the delay so sync can start.
            self.hasReceivedRemoteData = true
            self.pushToCloud()
        }

        // 4. B-ICLOUD-BROAD: Use dedicated publisher for routing-data changes only,
        // instead of objectWillChange which fires on unrelated UI fields.
        cancellable = settingsStore.routingDataDidChange
            .filter { [weak self] _ in self?.isApplyingRemoteChange == false }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushToCloud() }
    }

    func stopSync() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        cancellable?.cancel()
        cancellable = nil
        pushRescheduled = false // R11: Clear on stop
    }

    func pushToCloud() {
        guard settingsStore.iCloudSyncEnabled else { return }

        // §6: Instead of dropping the push, reschedule it after the suppression window
        let timeSincePull = Date().timeIntervalSince(lastPullTime)
        guard timeSincePull > pullSuppressionWindow else {
            guard !pushRescheduled else { return }
            pushRescheduled = true
            let delay = pullSuppressionWindow - timeSincePull + 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pushRescheduled = false
                self?.pushToCloud()
            }
            return
        }

        // B-ICLOUD: Don't push until we've received at least one remote data set
        // (prevents wiping other devices on first launch)
        guard hasReceivedRemoteData else { return }

        let encoder = JSONEncoder()

        // P6: Compute a hash of the payload to skip identical pushes
        var payloadParts: [Data] = []

        // Strip customIconData and filter path-based entries before syncing
        do {
            let browsersToSync = settingsStore.loadBrowsers()
                .filter { !$0.bundleIdentifier.hasPrefix("/") }
                .map { entry -> BrowserEntry in
                    var copy = entry
                    copy.customIconData = nil
                    return copy
                }
            let data = try encoder.encode(browsersToSync)
            payloadParts.append(data)
            kvStore.set(data, forKey: "sync_browsers")
        } catch {
            YojamLogger.shared.log("iCloud push browsers failed: \(error.localizedDescription)")
        }
        do {
            let userRules = settingsStore.loadRules().filter { !$0.isBuiltIn }
            let data = try encoder.encode(userRules)
            payloadParts.append(data)
            kvStore.set(data, forKey: "sync_rules")
        } catch {
            YojamLogger.shared.log("iCloud push rules failed: \(error.localizedDescription)")
        }
        do {
            let data = try encoder.encode(settingsStore.loadGlobalRewriteRules())
            payloadParts.append(data)
            kvStore.set(data, forKey: "sync_rewrites")
        } catch {
            YojamLogger.shared.log("iCloud push rewrites failed: \(error.localizedDescription)")
        }
        kvStore.set(settingsStore.utmStripList, forKey: "sync_utmStripList")

        // §50: Sync email clients (filter path-based entries like browsers)
        do {
            let emailToSync = settingsStore.loadEmailClients()
                .filter { !$0.bundleIdentifier.hasPrefix("/") }
                .map { entry -> BrowserEntry in
                    var copy = entry
                    copy.customIconData = nil
                    return copy
                }
            let data = try encoder.encode(emailToSync)
            payloadParts.append(data)
            kvStore.set(data, forKey: "sync_emailClients")
        } catch {
            YojamLogger.shared.log("iCloud push email clients failed: \(error.localizedDescription)")
        }

        // Sync general preferences
        kvStore.set(settingsStore.activationMode.rawValue, forKey: "sync_activationMode")
        kvStore.set(settingsStore.defaultSelectionBehavior.rawValue, forKey: "sync_defaultSelection")
        kvStore.set(settingsStore.verticalThreshold, forKey: "sync_verticalThreshold")
        kvStore.set(settingsStore.soundEffectsEnabled, forKey: "sync_soundEffects")
        kvStore.set(settingsStore.globalUTMStrippingEnabled, forKey: "sync_globalUTMStripping")
        kvStore.set(settingsStore.clipboardMonitoringEnabled, forKey: "sync_clipboardMonitoring")
        kvStore.set(settingsStore.debugLoggingEnabled, forKey: "sync_debugLogging")
        kvStore.set(settingsStore.periodicRescanInterval, forKey: "sync_periodicRescanInterval")

        // B-ICLOUD-QUOTA: Check total size BEFORE committing to iCloud
        let totalBytes = payloadParts.reduce(0) { $0 + $1.count }
        if totalBytes > 1_000_000 {
            YojamLogger.shared.log("iCloud push rejected: payload \(totalBytes) bytes exceeds 1MB quota")
            return
        }
        if totalBytes > 900_000 {
            YojamLogger.shared.log("Warning: iCloud KV store near quota: \(totalBytes) bytes")
        }

        // P6: Skip push if payload hasn't changed
        let currentHash = payloadParts.reduce(0) { $0 ^ $1.hashValue }
        if currentHash == lastPushedHash { return }
        lastPushedHash = currentHash

        kvStore.synchronize()
    }

    private func handleRemoteChange() {
        guard settingsStore.iCloudSyncEnabled else { return }
        lastPullTime = Date()
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        let decoder = JSONDecoder()
        if let data = kvStore.data(forKey: "sync_browsers") {
            do {
                let remote = try decoder.decode([BrowserEntry].self, from: data)
                    .filter { !$0.bundleIdentifier.hasPrefix("/") }
                let merged = SyncConflictResolver.mergeBrowserLists(
                    local: settingsStore.loadBrowsers(), remote: remote)
                settingsStore.saveBrowsers(merged)
                // §4: Update live in-memory state
                browserManager?.browsers = merged
                browserManager?.refreshProfileSuggestions()
            } catch {
                YojamLogger.shared.log("iCloud pull browsers failed: \(error.localizedDescription)")
            }
        }
        if let data = kvStore.data(forKey: "sync_rules") {
            do {
                let remote = try decoder.decode([Rule].self, from: data)
                let allLocal = settingsStore.loadRules()
                let localBuiltIns = allLocal.filter { $0.isBuiltIn }
                let local = allLocal.filter { !$0.isBuiltIn }
                let merged = SyncConflictResolver.mergeRules(
                    local: local, remote: remote)
                var allRules = localBuiltIns
                allRules.append(contentsOf: merged)
                settingsStore.saveRules(allRules)
                // §4: Update live in-memory state
                ruleEngine?.rules = allRules
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

        // §50: Pull email clients (filter path-based entries)
        if let data = kvStore.data(forKey: "sync_emailClients") {
            do {
                let remote = try decoder.decode([BrowserEntry].self, from: data)
                    .filter { !$0.bundleIdentifier.hasPrefix("/") }
                let merged = SyncConflictResolver.mergeBrowserLists(
                    local: settingsStore.loadEmailClients(), remote: remote)
                settingsStore.saveEmailClients(merged)
                browserManager?.emailClients = merged
            } catch {
                YojamLogger.shared.log("iCloud pull email clients failed: \(error.localizedDescription)")
            }
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
            settingsStore.verticalThreshold = max(4, min(Int(kvStore.longLong(forKey: "sync_verticalThreshold")), 20))
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
        if kvStore.object(forKey: "sync_debugLogging") != nil {
            settingsStore.debugLoggingEnabled = kvStore.bool(forKey: "sync_debugLogging")
        }
        if kvStore.object(forKey: "sync_periodicRescanInterval") != nil {
            settingsStore.periodicRescanInterval = max(60, min(kvStore.double(forKey: "sync_periodicRescanInterval"), 86400))
        }
    }
}
