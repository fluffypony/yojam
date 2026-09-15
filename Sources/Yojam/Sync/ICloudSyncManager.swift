import Foundation
import Combine
import YojamCore

// Pre-1.3 clients rewrite both rule records and the rewrite sidecar. Keep source
// lists under a key those clients do not know. Remove this key and the guard
// restoration once pre-1.3 clients can no longer participate in iCloud sync.
struct ICloudSourceAppCompatibility: Codable {
    static let key = "sync_ruleSourceApps_v1"

    struct Sources: Codable {
        let apps: [RuleSourceApp]
        let modifiedAt: Date?
    }

    let rules: [String: Sources]

    init(rules: [Rule], previous: ICloudSourceAppCompatibility? = nil) {
        var sources: [String: Sources] = [:]
        for rule in rules {
            let key = rule.id.uuidString
            if Self.hasLegacyGuard(rule) {
                sources[key] = previous?.rules[key]
            } else {
                sources[key] = Sources(apps: rule.sourceApps, modifiedAt: rule.lastModifiedAt)
            }
        }
        self.rules = sources
    }

    static func hasLegacyGuard(_ rule: Rule) -> Bool {
        rule.sourceApps.count == 1
            && rule.sourceApps.first?.bundleId == RuleSourceApp.legacyMultiAppGuard.bundleId
    }

    func restoring(_ rule: Rule, local: Rule?) -> Rule {
        guard Self.hasLegacyGuard(rule) else { return rule }
        let saved = rules[rule.id.uuidString]
        var copy = rule
        if let local, !Self.hasLegacyGuard(local),
           saved == nil || (local.lastModifiedAt ?? .distantPast) > (saved?.modifiedAt ?? .distantPast) {
            copy.sourceApps = local.sourceApps
        } else if let saved {
            copy.sourceApps = saved.apps
        }
        return copy
    }
}

// Keep each sync record flat so older app versions can decode it as the model.
// If an older version writes it back, the missing marker identifies lost fields.
struct ICloudBrowserSyncRecord: Codable {
    static let currentSchemaVersion = 1

    let browser: BrowserEntry
    let schemaVersion: Int

    var requiresLocalRewriteFields: Bool {
        schemaVersion < Self.currentSchemaVersion
    }

    init(browser: BrowserEntry) {
        self.browser = browser
        schemaVersion = Self.currentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "_yojamSyncSchemaVersion"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 0
        browser = try BrowserEntry(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try browser.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
    }
}

struct ICloudRuleSyncRecord: Codable {
    static let currentSchemaVersion = 1

    let rule: Rule
    let schemaVersion: Int

    var requiresLocalRewriteFields: Bool {
        schemaVersion < Self.currentSchemaVersion
    }

    init(rule: Rule) {
        self.rule = rule
        schemaVersion = Self.currentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "_yojamSyncSchemaVersion"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 0
        rule = try Rule(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try rule.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
    }
}

struct ICloudRewriteSyncRecord: Codable {
    static let currentSchemaVersion = 1

    let rewriteRule: URLRewriteRule
    let schemaVersion: Int

    var requiresLocalRewriteFields: Bool {
        schemaVersion < Self.currentSchemaVersion
    }

    init(rewriteRule: URLRewriteRule) {
        self.rewriteRule = rewriteRule
        schemaVersion = Self.currentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "_yojamSyncSchemaVersion"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 0
        rewriteRule = try URLRewriteRule(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try rewriteRule.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
    }
}

/// Stores fields that older Yojam versions cannot preserve when they rewrite
/// the flat sync records. Older clients do not know this key, so it survives
/// their writes and can restore those fields on a new current-version device.
struct ICloudCompatibilitySidecar: Codable, Equatable {
    static let key = "sync_rewriteCompatibility_v1"
    static let currentSchemaVersion = 2

    enum BrowserCollection {
        case browsers
        case emailClients
        case phoneClients
    }

    struct RewriteMatchSignature: Codable, Equatable {
        let matchPattern: String
        let isRegex: Bool

        init(_ rewrite: URLRewriteRule) {
            matchPattern = rewrite.matchPattern
            isRegex = rewrite.isRegex
        }
    }

    struct RuleMatchSignature: Codable, Equatable {
        let matchType: MatchType
        let pattern: String

        init(_ rule: Rule) {
            matchType = rule.matchType
            pattern = rule.pattern
        }
    }

    struct RewriteFields: Codable, Equatable {
        let rewriteRuleID: UUID
        let originalMatch: RewriteMatchSignature?
        let urlNormalization: URLNormalizationMode
        let metadata: [String: String]?

        init(_ rewrite: URLRewriteRule) {
            rewriteRuleID = rewrite.id
            originalMatch = RewriteMatchSignature(rewrite)
            urlNormalization = rewrite.urlNormalization
            metadata = rewrite.metadata
        }

        func restoring(_ rewrite: URLRewriteRule) -> URLRewriteRule {
            var copy = rewrite
            var restoredMetadata = metadata
            if let originalMatch,
               originalMatch != RewriteMatchSignature(rewrite) {
                restoredMetadata?.removeValue(forKey: "finickyWebOnly")
                if restoredMetadata?.isEmpty == true {
                    restoredMetadata = nil
                }
            }
            copy.urlNormalization = urlNormalization
            copy.metadata = restoredMetadata
            return copy
        }
    }

    struct BrowserFields: Codable, Equatable {
        let browserID: UUID
        let rewrites: [RewriteFields]

        init(_ browser: BrowserEntry) {
            browserID = browser.id
            rewrites = browser.rewriteRules.map(RewriteFields.init)
        }

        func restoring(_ browser: BrowserEntry) -> BrowserEntry {
            let fieldsByID = Dictionary(uniqueKeysWithValues: rewrites.map {
                ($0.rewriteRuleID, $0)
            })
            var copy = browser
            copy.rewriteRules = browser.rewriteRules.map { rewrite in
                fieldsByID[rewrite.id]?.restoring(rewrite) ?? rewrite
            }
            return copy
        }
    }

    struct RuleFields: Codable, Equatable {
        let ruleID: UUID
        let originalMatch: RuleMatchSignature?
        let urlNormalization: URLNormalizationMode
        let rewrites: [RewriteFields]

        init(_ rule: Rule) {
            ruleID = rule.id
            originalMatch = RuleMatchSignature(rule)
            urlNormalization = rule.urlNormalization
            rewrites = rule.rewriteRules.map(RewriteFields.init)
        }

        func restoring(_ rule: Rule) -> Rule {
            let fieldsByID = Dictionary(uniqueKeysWithValues: rewrites.map {
                ($0.rewriteRuleID, $0)
            })
            var copy = rule
            if let originalMatch,
               originalMatch != RuleMatchSignature(rule) {
                copy.metadata?.removeValue(forKey: "finickyWebOnly")
                if copy.metadata?.isEmpty == true {
                    copy.metadata = nil
                }
            }
            copy.urlNormalization = urlNormalization
            copy.rewriteRules = rule.rewriteRules.map { rewrite in
                fieldsByID[rewrite.id]?.restoring(rewrite) ?? rewrite
            }
            return copy
        }
    }

    let schemaVersion: Int
    let browsers: [BrowserFields]
    let emailClients: [BrowserFields]
    let phoneClients: [BrowserFields]
    let rules: [RuleFields]
    let globalRewrites: [RewriteFields]

    init(
        browsers: [BrowserEntry],
        emailClients: [BrowserEntry],
        phoneClients: [BrowserEntry],
        rules: [Rule],
        globalRewrites: [URLRewriteRule]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.browsers = browsers.map(BrowserFields.init)
        self.emailClients = emailClients.map(BrowserFields.init)
        self.phoneClients = phoneClients.map(BrowserFields.init)
        self.rules = rules.map(RuleFields.init)
        self.globalRewrites = globalRewrites.map(RewriteFields.init)
    }

    func restoringLegacyBrowser(
        _ browser: BrowserEntry,
        in collection: BrowserCollection
    ) -> BrowserEntry {
        browserFields(in: collection)
            .first(where: { $0.browserID == browser.id })?
            .restoring(browser) ?? browser
    }

    func containsBrowser(_ browserID: UUID, in collection: BrowserCollection) -> Bool {
        browserFields(in: collection).contains { $0.browserID == browserID }
    }

    func containsRule(_ ruleID: UUID) -> Bool {
        rules.contains { $0.ruleID == ruleID }
    }

    func containsGlobalRewrite(_ rewriteRuleID: UUID) -> Bool {
        globalRewrites.contains { $0.rewriteRuleID == rewriteRuleID }
    }

    private func browserFields(in collection: BrowserCollection) -> [BrowserFields] {
        switch collection {
        case .browsers:
            browsers
        case .emailClients:
            emailClients
        case .phoneClients:
            phoneClients
        }
    }

    func restoringLegacyRule(_ rule: Rule) -> Rule {
        rules.first(where: { $0.ruleID == rule.id })?.restoring(rule) ?? rule
    }

    func restoringLegacyGlobalRewrite(_ rewrite: URLRewriteRule) -> URLRewriteRule {
        globalRewrites.first(where: { $0.rewriteRuleID == rewrite.id })?.restoring(rewrite)
            ?? rewrite
    }
}

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

        // Compute all payloads BEFORE writing to KV store so we can
        // check total size and skip identical pushes without partial writes.
        var payloads: [(key: String, data: Data)] = []

        // Strip customIconData and filter path-based entries before syncing.
        let browsersToSync = settingsStore.loadBrowsers()
            .filter { !$0.bundleIdentifier.hasPrefix("/") }
            .map { entry -> BrowserEntry in
                var copy = entry
                copy.customIconData = nil
                return copy
            }
        let userRules = settingsStore.loadRules().filter { !$0.isBuiltIn }
        let globalRewrites = settingsStore.loadGlobalRewriteRules()
        let emailToSync = settingsStore.loadEmailClients()
            .filter { !$0.bundleIdentifier.hasPrefix("/") }
            .map { entry -> BrowserEntry in
                var copy = entry
                copy.customIconData = nil
                return copy
            }
        let phoneToSync = settingsStore.loadPhoneClients()
            .filter { !$0.bundleIdentifier.hasPrefix("/") }
            .map { entry -> BrowserEntry in
                var copy = entry
                copy.customIconData = nil
                return copy
            }

        // Write the compatibility data under a separate key. Older clients
        // replace the flat records but leave this key intact.
        do {
            let sidecar = ICloudCompatibilitySidecar(
                browsers: browsersToSync,
                emailClients: emailToSync,
                phoneClients: phoneToSync,
                rules: userRules,
                globalRewrites: globalRewrites)
            payloads.append((ICloudCompatibilitySidecar.key, try encoder.encode(sidecar)))
        } catch {
            YojamLogger.shared.log(
                "iCloud push compatibility data failed: \(error.localizedDescription)")
            return
        }

        do {
            let records = browsersToSync.map(ICloudBrowserSyncRecord.init(browser:))
            payloads.append(("sync_browsers", try encoder.encode(records)))
        } catch {
            YojamLogger.shared.log("iCloud push browsers failed: \(error.localizedDescription)")
        }
        do {
            let records = userRules.map(ICloudRuleSyncRecord.init(rule:))
            let previousSources = kvStore.data(forKey: ICloudSourceAppCompatibility.key)
                .flatMap { try? JSONDecoder().decode(ICloudSourceAppCompatibility.self, from: $0) }
            let sourceApps = ICloudSourceAppCompatibility(rules: userRules, previous: previousSources)
            payloads.append((ICloudSourceAppCompatibility.key, try encoder.encode(sourceApps)))
            payloads.append(("sync_rules", try encoder.encode(records)))
        } catch {
            YojamLogger.shared.log("iCloud push rules failed: \(error.localizedDescription)")
        }
        do {
            let records = globalRewrites
                .map(ICloudRewriteSyncRecord.init(rewriteRule:))
            payloads.append(("sync_rewrites", try encoder.encode(records)))
        } catch {
            YojamLogger.shared.log("iCloud push rewrites failed: \(error.localizedDescription)")
        }
        do {
            let records = emailToSync.map(ICloudBrowserSyncRecord.init(browser:))
            payloads.append(("sync_emailClients", try encoder.encode(records)))
        } catch {
            YojamLogger.shared.log("iCloud push email clients failed: \(error.localizedDescription)")
        }
        do {
            let records = phoneToSync.map(ICloudBrowserSyncRecord.init(browser:))
            payloads.append(("sync_phoneClients", try encoder.encode(records)))
        } catch {
            YojamLogger.shared.log("iCloud push phone clients failed: \(error.localizedDescription)")
        }

        // Check total size BEFORE committing anything to iCloud
        let totalBytes = payloads.reduce(0) { $0 + $1.data.count }
        if totalBytes > 1_000_000 {
            YojamLogger.shared.log("iCloud push rejected: payload \(totalBytes) bytes exceeds 1MB quota")
            return
        }
        if totalBytes > 900_000 {
            YojamLogger.shared.log("Warning: iCloud KV store near quota: \(totalBytes) bytes")
        }

        // Skip a push only when both record payloads and scalar settings match.
        // The old hash omitted scalars, so scalar-only changes never reached KVS.
        var hasher = Hasher()
        for payload in payloads.sorted(by: { $0.key < $1.key }) {
            hasher.combine(payload.key)
            hasher.combine(payload.data)
        }
        hasher.combine(settingsStore.utmStripList)
        hasher.combine(settingsStore.activationMode.rawValue)
        hasher.combine(settingsStore.defaultSelectionBehavior.rawValue)
        hasher.combine(settingsStore.verticalThreshold)
        hasher.combine(settingsStore.soundEffectsEnabled)
        hasher.combine(settingsStore.globalUTMStrippingEnabled)
        hasher.combine(settingsStore.clipboardMonitoringEnabled)
        hasher.combine(settingsStore.debugLoggingEnabled)
        hasher.combine(settingsStore.periodicRescanInterval)
        hasher.combine(settingsStore.shortlinkResolutionEnabled)
        hasher.combine(settingsStore.shortlinkResolutionHosts.sorted())
        hasher.combine(settingsStore.shortlinkResolutionMode.rawValue)
        let currentHash = hasher.finalize()
        if currentHash == lastPushedHash { return }
        lastPushedHash = currentHash

        // Now commit all payloads
        for (key, data) in payloads {
            kvStore.set(data, forKey: key)
        }
        kvStore.set(settingsStore.utmStripList, forKey: "sync_utmStripList")
        kvStore.set(settingsStore.activationMode.rawValue, forKey: "sync_activationMode")
        kvStore.set(settingsStore.defaultSelectionBehavior.rawValue, forKey: "sync_defaultSelection")
        kvStore.set(settingsStore.verticalThreshold, forKey: "sync_verticalThreshold")
        kvStore.set(settingsStore.soundEffectsEnabled, forKey: "sync_soundEffects")
        kvStore.set(settingsStore.globalUTMStrippingEnabled, forKey: "sync_globalUTMStripping")
        kvStore.set(settingsStore.clipboardMonitoringEnabled, forKey: "sync_clipboardMonitoring")
        kvStore.set(settingsStore.debugLoggingEnabled, forKey: "sync_debugLogging")
        kvStore.set(settingsStore.periodicRescanInterval, forKey: "sync_periodicRescanInterval")
        kvStore.set(
            settingsStore.shortlinkResolutionEnabled,
            forKey: "sync_shortlinkResolutionEnabled")
        kvStore.set(
            settingsStore.shortlinkResolutionHosts.sorted(),
            forKey: "sync_shortlinkResolutionHosts")
        kvStore.set(
            settingsStore.shortlinkResolutionMode.rawValue,
            forKey: "sync_shortlinkResolutionMode")

        kvStore.synchronize()
    }

    private func handleRemoteChange() {
        guard settingsStore.iCloudSyncEnabled else { return }
        lastPullTime = Date()
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        let decoder = JSONDecoder()
        let compatibilitySidecar: ICloudCompatibilitySidecar?
        if let data = kvStore.data(forKey: ICloudCompatibilitySidecar.key) {
            do {
                compatibilitySidecar = try decoder.decode(
                    ICloudCompatibilitySidecar.self,
                    from: data)
            } catch {
                compatibilitySidecar = nil
                YojamLogger.shared.log(
                    "iCloud pull compatibility data failed: \(error.localizedDescription)")
            }
        } else {
            compatibilitySidecar = nil
        }
        var browserIdAliases: [UUID: UUID] = [:]
        if let data = kvStore.data(forKey: "sync_browsers") {
            do {
                let records = try decoder.decode([ICloudBrowserSyncRecord].self, from: data)
                let remote = records.map { record in
                    guard record.requiresLocalRewriteFields,
                          let compatibilitySidecar else {
                        return record.browser
                    }
                    return compatibilitySidecar.restoringLegacyBrowser(
                        record.browser,
                        in: .browsers)
                }
                    .filter { !$0.bundleIdentifier.hasPrefix("/") }
                let legacyBrowserIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsBrowser(
                                $0.browser.id,
                                in: .browsers) != true
                        }
                        .map { $0.browser.id })
                let restoredLegacyBrowserIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsBrowser(
                                $0.browser.id,
                                in: .browsers) == true
                        }
                        .map { $0.browser.id })
                let local = settingsStore.loadBrowsers()
                let mergeResult = SyncConflictResolver.mergeBrowserListsWithAliases(
                    local: local,
                    remote: remote,
                    preservingLocalRewriteFieldsForRemoteBrowserIDs: legacyBrowserIds,
                    preferringRemoteOnEqualTimestampForBrowserIDs: restoredLegacyBrowserIds)
                let merged = settingsStore.preservingLocalBrowserState(
                    in: mergeResult.entries, local: local)
                browserIdAliases.merge(mergeResult.idAliases) { current, _ in current }
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
                let allLocal = settingsStore.loadRules()
                let sourceApps = kvStore.data(forKey: ICloudSourceAppCompatibility.key)
                    .flatMap { try? decoder.decode(ICloudSourceAppCompatibility.self, from: $0) }
                    ?? ICloudSourceAppCompatibility(rules: [])
                let records = try decoder.decode([ICloudRuleSyncRecord].self, from: data)
                let restoredRemote = records.map { record in
                    let rule = sourceApps.restoring(
                        record.rule,
                        local: allLocal.first { $0.id == record.rule.id })
                    guard record.requiresLocalRewriteFields,
                          let compatibilitySidecar else {
                        return rule
                    }
                    return compatibilitySidecar.restoringLegacyRule(rule)
                }
                let remote = SyncConflictResolver.remapRuleBrowserTargets(
                    restoredRemote,
                    aliases: browserIdAliases)
                let legacyRuleIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsRule($0.rule.id) != true
                        }
                        .map { $0.rule.id })
                let restoredSourceRuleIds = Set(zip(records, restoredRemote).compactMap { record, rule in
                    ICloudSourceAppCompatibility.hasLegacyGuard(record.rule)
                        && !ICloudSourceAppCompatibility.hasLegacyGuard(rule) ? rule.id : nil
                })
                let restoredLegacyRuleIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsRule($0.rule.id) == true
                        }
                        .map { $0.rule.id })
                    .union(restoredSourceRuleIds)
                let localBuiltIns = allLocal.filter { $0.isBuiltIn }
                let local = SyncConflictResolver.remapRuleBrowserTargets(
                    allLocal.filter { !$0.isBuiltIn },
                    aliases: browserIdAliases)
                let merged = SyncConflictResolver.mergeRules(
                    local: local,
                    remote: remote,
                    preservingLocalRewriteFieldsForRemoteRuleIDs: legacyRuleIds,
                    preferringRemoteOnEqualTimestampForRuleIDs: restoredLegacyRuleIds)
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
                let records = try decoder.decode([ICloudRewriteSyncRecord].self, from: data)
                let remote = records.map { record in
                    guard record.requiresLocalRewriteFields,
                          let compatibilitySidecar else {
                        return record.rewriteRule
                    }
                    return compatibilitySidecar.restoringLegacyGlobalRewrite(
                        record.rewriteRule)
                }
                let legacyRewriteIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsGlobalRewrite(
                                $0.rewriteRule.id) != true
                        }
                        .map { $0.rewriteRule.id })
                let restoredLegacyRewriteIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsGlobalRewrite(
                                $0.rewriteRule.id) == true
                        }
                        .map { $0.rewriteRule.id })
                let local = settingsStore.loadGlobalRewriteRules()
                let merged = SyncConflictResolver.mergeRewriteRules(
                    local: local,
                    remote: remote,
                    preservingLocalRewriteFieldsForRemoteRewriteRuleIDs: legacyRewriteIds,
                    preferringRemoteOnEqualTimestampForRewriteRuleIDs:
                        restoredLegacyRewriteIds)
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
                let records = try decoder.decode([ICloudBrowserSyncRecord].self, from: data)
                let remote = records.map { record in
                    guard record.requiresLocalRewriteFields,
                          let compatibilitySidecar else {
                        return record.browser
                    }
                    return compatibilitySidecar.restoringLegacyBrowser(
                        record.browser,
                        in: .emailClients)
                }
                    .filter { !$0.bundleIdentifier.hasPrefix("/") }
                let legacyBrowserIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsBrowser(
                                $0.browser.id,
                                in: .emailClients) != true
                        }
                        .map { $0.browser.id })
                let restoredLegacyBrowserIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsBrowser(
                                $0.browser.id,
                                in: .emailClients) == true
                        }
                        .map { $0.browser.id })
                let local = settingsStore.loadEmailClients()
                let merged = settingsStore.preservingLocalBrowserState(
                    in: SyncConflictResolver.mergeBrowserLists(
                        local: local,
                        remote: remote,
                        preservingLocalRewriteFieldsForRemoteBrowserIDs: legacyBrowserIds,
                        preferringRemoteOnEqualTimestampForBrowserIDs:
                            restoredLegacyBrowserIds),
                    local: local)
                settingsStore.saveEmailClients(merged)
                browserManager?.emailClients = merged
            } catch {
                YojamLogger.shared.log("iCloud pull email clients failed: \(error.localizedDescription)")
            }
        }

        if let data = kvStore.data(forKey: "sync_phoneClients") {
            do {
                let records = try decoder.decode([ICloudBrowserSyncRecord].self, from: data)
                let remote = records.map { record in
                    guard record.requiresLocalRewriteFields,
                          let compatibilitySidecar else {
                        return record.browser
                    }
                    return compatibilitySidecar.restoringLegacyBrowser(
                        record.browser,
                        in: .phoneClients)
                }
                    .filter { !$0.bundleIdentifier.hasPrefix("/") }
                let legacyBrowserIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsBrowser(
                                $0.browser.id,
                                in: .phoneClients) != true
                        }
                        .map { $0.browser.id })
                let restoredLegacyBrowserIds = Set(
                    records.lazy
                        .filter(\.requiresLocalRewriteFields)
                        .filter {
                            compatibilitySidecar?.containsBrowser(
                                $0.browser.id,
                                in: .phoneClients) == true
                        }
                        .map { $0.browser.id })
                let local = settingsStore.loadPhoneClients()
                let merged = settingsStore.preservingLocalBrowserState(
                    in: SyncConflictResolver.mergeBrowserLists(
                        local: local,
                        remote: remote,
                        preservingLocalRewriteFieldsForRemoteBrowserIDs: legacyBrowserIds,
                        preferringRemoteOnEqualTimestampForBrowserIDs:
                            restoredLegacyBrowserIds),
                    local: local)
                settingsStore.savePhoneClients(merged)
                browserManager?.phoneClients = merged
            } catch {
                YojamLogger.shared.log("iCloud pull phone clients failed: \(error.localizedDescription)")
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
        if kvStore.object(forKey: "sync_shortlinkResolutionHosts") != nil {
            settingsStore.shortlinkResolutionHosts = ShortlinkResolver.canonicalHostAllowlist(
                kvStore.array(forKey: "sync_shortlinkResolutionHosts") as? [String] ?? [])
        }
        if let rawMode = kvStore.string(forKey: "sync_shortlinkResolutionMode"),
           let mode = ShortlinkResolutionMode(rawValue: rawMode) {
            settingsStore.shortlinkResolutionMode = mode
        }
        if kvStore.object(forKey: "sync_shortlinkResolutionEnabled") != nil {
            settingsStore.shortlinkResolutionEnabled = kvStore.bool(
                forKey: "sync_shortlinkResolutionEnabled")
        }
    }
}
