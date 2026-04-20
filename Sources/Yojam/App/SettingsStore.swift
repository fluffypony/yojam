import Foundation
import Combine
import ServiceManagement
import YojamCore

enum PickerLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, smallHorizontal, bigHorizontal, smallVertical, bigVertical
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .smallHorizontal: "Small Horizontal"
        case .bigHorizontal: "Big Horizontal"
        case .smallVertical: "Small Vertical"
        case .bigVertical: "Big Vertical"
        }
    }
    var isVertical: Bool {
        switch self {
        case .smallVertical, .bigVertical: true
        default: false
        }
    }
    var isHorizontal: Bool {
        switch self {
        case .smallHorizontal, .bigHorizontal: true
        default: false
        }
    }
    var isBig: Bool {
        switch self {
        case .bigHorizontal, .bigVertical: true
        default: false
        }
    }
}

enum RecentURLRetention: String, Codable, CaseIterable, Identifiable, Sendable {
    case never, timed, forever
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .never: "Never save"
        case .timed: "Auto-delete after..."
        case .forever: "Keep forever"
        }
    }
}

enum PickerDirectionOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, ltr, rtl, topToBottom, bottomToTop
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: "Automatic (follow system)"
        case .ltr: "Left to Right"
        case .rtl: "Right to Left"
        case .topToBottom: "Top to Bottom"
        case .bottomToTop: "Bottom to Top"
        }
    }
}

/// Typed navigation route used by Quick Start deep-linking.
struct PreferencesRoute: Equatable {
    let tab: String        // PreferencesTab rawValue
    let sectionId: String
    let controlId: String?
}

@MainActor
final class SettingsStore: ObservableObject {
    /// App-only settings (launch at login, Quick Start, clipboard, Sparkle, etc.)
    private let defaults = UserDefaults.standard
    /// Routing-relevant settings shared via App Group with extensions.
    /// Per hard-cut policy: no fallback to .standard for routing data.
    let sharedStore = SharedRoutingStore()
    private var sharedDefaults: UserDefaults { sharedStore.defaults }
    private var isRevertingLaunchAtLogin = false

    private enum Keys {
        static let isFirstLaunch = "isFirstLaunch"
        static let isEnabled = "isEnabled"
        static let activationMode = "activationMode"
        static let defaultSelection = "defaultSelection"
        static let verticalThreshold = "verticalThreshold"
        static let soundEffects = "soundEffects"
        static let launchAtLogin = "launchAtLogin"
        static let globalUTMStripping = "globalUTMStripping"
        static let clipboardMonitoring = "clipboardMonitoring"
        static let iCloudSync = "iCloudSync"
        static let debugLogging = "debugLogging"
        static let periodicRescanInterval = "periodicRescanInterval"
        static let browsers = "browsers"
        static let emailClients = "emailClients"
        static let rules = "rules"
        static let globalRewriteRules = "globalRewriteRules"
        static let utmStripList = "utmStripList"
        static let suppressedClipboardDomains = "suppressedClipboardDomains"
        static let pickerLayout = "pickerLayout"
        static let pickerDirectionOverride = "pickerDirectionOverride"
        static let recentURLRetention = "recentURLRetention"
        static let recentURLRetentionMinutes = "recentURLRetentionMinutes"
        static let hasDismissedQuickStart = "hasDismissedQuickStart"
        static let quickStartVisitedActivation = "quickStartVisitedActivation"
        static let quickStartVisitedBrowsers = "quickStartVisitedBrowsers"
        static let quickStartVisitedTester = "quickStartVisitedTester"
        // User-deleted built-in rule UUIDs (distinct from BuiltInRules.removedIds).
        static let deletedBuiltInRuleIds = "deletedBuiltInRuleIds"
    }

    @Published var isFirstLaunch: Bool {
        didSet { defaults.set(isFirstLaunch, forKey: Keys.isFirstLaunch) }
    }
    @Published var isEnabled: Bool {
        didSet { sharedDefaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var activationMode: ActivationMode {
        didSet { sharedDefaults.set(activationMode.rawValue, forKey: Keys.activationMode); routingDataDidChange.send() }
    }
    @Published var defaultSelectionBehavior: DefaultSelectionBehavior {
        didSet { sharedDefaults.set(defaultSelectionBehavior.rawValue, forKey: Keys.defaultSelection); routingDataDidChange.send() }
    }
    @Published var verticalThreshold: Int {
        didSet { sharedDefaults.set(verticalThreshold, forKey: Keys.verticalThreshold); routingDataDidChange.send() }
    }
    @Published var soundEffectsEnabled: Bool {
        didSet { sharedDefaults.set(soundEffectsEnabled, forKey: Keys.soundEffects); routingDataDidChange.send() }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            } catch {
                YojamLogger.shared.log("SMAppService \(launchAtLogin ? "register" : "unregister") failed: \(error)")
                isRevertingLaunchAtLogin = true
                launchAtLogin = !launchAtLogin
                isRevertingLaunchAtLogin = false
            }
        }
    }
    @Published var globalUTMStrippingEnabled: Bool {
        didSet { sharedDefaults.set(globalUTMStrippingEnabled, forKey: Keys.globalUTMStripping); routingDataDidChange.send() }
    }
    @Published var clipboardMonitoringEnabled: Bool {
        didSet { defaults.set(clipboardMonitoringEnabled, forKey: Keys.clipboardMonitoring) }
    }
    @Published var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSync) }
    }
    @Published var debugLoggingEnabled: Bool {
        didSet { defaults.set(debugLoggingEnabled, forKey: Keys.debugLogging) }
    }
    @Published var periodicRescanInterval: TimeInterval {
        didSet { defaults.set(periodicRescanInterval, forKey: Keys.periodicRescanInterval) }
    }
    @Published var utmStripList: [String] {
        didSet { sharedDefaults.set(utmStripList, forKey: Keys.utmStripList); routingDataDidChange.send() }
    }
    @Published var suppressedClipboardDomains: [String] {
        didSet { defaults.set(suppressedClipboardDomains, forKey: Keys.suppressedClipboardDomains) }
    }
    @Published var pickerLayout: PickerLayout {
        didSet { sharedDefaults.set(pickerLayout.rawValue, forKey: Keys.pickerLayout) }
    }
    @Published var pickerDirectionOverride: PickerDirectionOverride {
        didSet { sharedDefaults.set(pickerDirectionOverride.rawValue, forKey: Keys.pickerDirectionOverride) }
    }
    @Published var recentURLRetention: RecentURLRetention {
        didSet { sharedDefaults.set(recentURLRetention.rawValue, forKey: Keys.recentURLRetention) }
    }
    @Published var recentURLRetentionMinutes: Int {
        didSet { sharedDefaults.set(recentURLRetentionMinutes, forKey: Keys.recentURLRetentionMinutes) }
    }
    @Published var shortlinkResolutionEnabled: Bool {
        didSet { sharedDefaults.set(shortlinkResolutionEnabled, forKey: SharedRoutingStore.Keys.shortlinkResolutionEnabled) }
    }
    @Published var hasDismissedQuickStart: Bool {
        didSet { defaults.set(hasDismissedQuickStart, forKey: Keys.hasDismissedQuickStart) }
    }
    @Published var quickStartVisitedActivation: Bool {
        didSet { defaults.set(quickStartVisitedActivation, forKey: Keys.quickStartVisitedActivation) }
    }
    @Published var quickStartVisitedBrowsers: Bool {
        didSet { defaults.set(quickStartVisitedBrowsers, forKey: Keys.quickStartVisitedBrowsers) }
    }
    @Published var quickStartVisitedTester: Bool {
        didSet { defaults.set(quickStartVisitedTester, forKey: Keys.quickStartVisitedTester) }
    }

    /// Transient: set by menu bar actions to scroll PreferencesView to a section after opening.
    @Published var pendingScrollToSection: String?
    /// Typed deep-link route pushed by Quick Start steps.
    @Published var pendingRoute: PreferencesRoute?
    /// Transient control ID that the UI should highlight briefly.
    @Published var highlightedControlId: String?

    // B-ICLOUD-BROAD: Dedicated publisher for routing-data changes only,
    // so iCloud sync doesn't re-encode on unrelated UI field changes.
    let routingDataDidChange = PassthroughSubject<Void, Never>()

    // P2: Cached decoded results to avoid re-deserializing JSON on every routing call
    private var cachedRules: [Rule]?
    private var cachedGlobalRewriteRules: [URLRewriteRule]?

    init() {
        // App-only defaults (UserDefaults.standard)
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.isFirstLaunch: true,
            Keys.periodicRescanInterval: 1800.0,
        ])

        // Routing defaults (App Group suite)
        let s = sharedStore.defaults
        s.register(defaults: [
            Keys.isEnabled: true,
            Keys.activationMode: ActivationMode.always.rawValue,
            Keys.defaultSelection: DefaultSelectionBehavior.alwaysFirst.rawValue,
            Keys.verticalThreshold: 8,
            Keys.soundEffects: false,
            Keys.pickerLayout: PickerLayout.bigHorizontal.rawValue,
            Keys.pickerDirectionOverride: PickerDirectionOverride.system.rawValue,
        ])

        // App-only settings from .standard
        self.isFirstLaunch = d.object(forKey: Keys.isFirstLaunch) as? Bool ?? true
        self.launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        self.clipboardMonitoringEnabled = d.bool(forKey: Keys.clipboardMonitoring)
        self.iCloudSyncEnabled = d.bool(forKey: Keys.iCloudSync)
        self.debugLoggingEnabled = d.bool(forKey: Keys.debugLogging)
        self.periodicRescanInterval = d.object(forKey: Keys.periodicRescanInterval)
            as? TimeInterval ?? 1800
        self.suppressedClipboardDomains = d.stringArray(forKey: Keys.suppressedClipboardDomains) ?? []
        self.hasDismissedQuickStart = d.bool(forKey: Keys.hasDismissedQuickStart)
        self.quickStartVisitedActivation = d.bool(forKey: Keys.quickStartVisitedActivation)
        self.quickStartVisitedBrowsers = d.bool(forKey: Keys.quickStartVisitedBrowsers)
        self.quickStartVisitedTester = d.bool(forKey: Keys.quickStartVisitedTester)

        // Routing settings from App Group suite
        self.isEnabled = s.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.activationMode = ActivationMode(
            rawValue: s.string(forKey: Keys.activationMode) ?? "") ?? .always
        self.defaultSelectionBehavior = DefaultSelectionBehavior(
            rawValue: s.string(forKey: Keys.defaultSelection) ?? "") ?? .alwaysFirst
        self.verticalThreshold = s.object(forKey: Keys.verticalThreshold) as? Int ?? 8
        self.soundEffectsEnabled = s.object(forKey: Keys.soundEffects) as? Bool ?? false
        self.globalUTMStrippingEnabled = s.bool(forKey: Keys.globalUTMStripping)
        self.utmStripList = s.stringArray(forKey: Keys.utmStripList)
            ?? UTMStripper.defaultParameters
        self.pickerLayout = PickerLayout(
            rawValue: s.string(forKey: Keys.pickerLayout) ?? "") ?? .auto
        // Migrate legacy pickerInvertOrder bool defaults to the new direction
        // override enum on first launch after upgrade.
        let legacyInvertKey = "pickerInvertOrder"
        let resolvedDirection: PickerDirectionOverride
        if s.object(forKey: Keys.pickerDirectionOverride) == nil,
           let legacyInvert = s.object(forKey: legacyInvertKey) as? Bool {
            resolvedDirection = legacyInvert ? .rtl : .system
            s.set(resolvedDirection.rawValue, forKey: Keys.pickerDirectionOverride)
            s.removeObject(forKey: legacyInvertKey)
        } else {
            resolvedDirection = PickerDirectionOverride(
                rawValue: s.string(forKey: Keys.pickerDirectionOverride) ?? "") ?? .system
        }
        self.pickerDirectionOverride = resolvedDirection
        self.recentURLRetention = RecentURLRetention(
            rawValue: s.string(forKey: Keys.recentURLRetention) ?? "") ?? .forever
        self.recentURLRetentionMinutes = s.object(forKey: Keys.recentURLRetentionMinutes) as? Int ?? 30
        self.shortlinkResolutionEnabled = s.bool(forKey: SharedRoutingStore.Keys.shortlinkResolutionEnabled)
    }

    // MARK: - User-deleted built-in rules tracking

    func deletedBuiltInRuleIds() -> Set<UUID> {
        guard let arr = sharedDefaults.stringArray(forKey: Keys.deletedBuiltInRuleIds) else { return [] }
        return Set(arr.compactMap { UUID(uuidString: $0) })
    }

    func addDeletedBuiltInRuleId(_ id: UUID) {
        var ids = deletedBuiltInRuleIds()
        ids.insert(id)
        sharedDefaults.set(ids.map(\.uuidString), forKey: Keys.deletedBuiltInRuleIds)
    }

    func clearDeletedBuiltInRuleIds() {
        sharedDefaults.removeObject(forKey: Keys.deletedBuiltInRuleIds)
    }

    // MARK: - Complex Data Persistence

    func saveBrowsers(_ browsers: [BrowserEntry]) {
        do {
            let data = try JSONEncoder().encode(browsers)
            sharedDefaults.set(data, forKey: Keys.browsers)
            objectWillChange.send()
            routingDataDidChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode browsers: \(error.localizedDescription)")
        }
    }

    func loadBrowsers() -> [BrowserEntry] {
        guard let data = sharedDefaults.data(forKey: Keys.browsers) else { return [] }
        do {
            return try JSONDecoder().decode([BrowserEntry].self, from: data)
        } catch {
            YojamLogger.shared.log("Failed to decode browsers: \(error.localizedDescription)")
            return []
        }
    }

    func saveEmailClients(_ clients: [BrowserEntry]) {
        do {
            let data = try JSONEncoder().encode(clients)
            sharedDefaults.set(data, forKey: Keys.emailClients)
            objectWillChange.send()
            routingDataDidChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode email clients: \(error.localizedDescription)")
        }
    }

    func loadEmailClients() -> [BrowserEntry] {
        guard let data = sharedDefaults.data(forKey: Keys.emailClients) else { return [] }
        do {
            return try JSONDecoder().decode([BrowserEntry].self, from: data)
        } catch {
            YojamLogger.shared.log("Failed to decode email clients: \(error.localizedDescription)")
            return []
        }
    }

    func saveRules(_ rules: [Rule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            sharedDefaults.set(data, forKey: Keys.rules)
            cachedRules = nil // invalidate cache
            objectWillChange.send()
            routingDataDidChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode rules: \(error.localizedDescription)")
        }
    }

    /// Loads rules. Preserves user edits to built-in rules; inserts any
    /// built-in rules that are missing from saved data (unless the user
    /// has explicitly deleted them).
    func loadRules() -> [Rule] {
        if let cached = cachedRules { return cached }
        let deletedIds = deletedBuiltInRuleIds()
        guard let data = sharedDefaults.data(forKey: Keys.rules) else {
            let initial = BuiltInRules.all.filter { !deletedIds.contains($0.id) }
            cachedRules = initial
            return initial
        }
        let savedRules: [Rule]
        do {
            savedRules = try JSONDecoder().decode([Rule].self, from: data)
        } catch {
            YojamLogger.shared.log("Failed to decode rules: \(error.localizedDescription)")
            cachedRules = BuiltInRules.all.filter { !deletedIds.contains($0.id) }
            return cachedRules!
        }

        // Drop built-ins that are tombstoned (either baked-in removedIds or user-deleted).
        var merged: [Rule] = []
        var seenIds = Set<UUID>()
        for rule in savedRules {
            if rule.isBuiltIn && BuiltInRules.removedIds.contains(rule.id) { continue }
            if rule.isBuiltIn && deletedIds.contains(rule.id) { continue }
            merged.append(rule)
            seenIds.insert(rule.id)
        }
        // Append brand-new built-in rules the user hasn't seen yet and hasn't deleted.
        for rule in BuiltInRules.all
            where !seenIds.contains(rule.id) && !deletedIds.contains(rule.id) {
            merged.append(rule)
        }
        cachedRules = merged
        return merged
    }

    func saveGlobalRewriteRules(_ rules: [URLRewriteRule]) {
        cachedGlobalRewriteRules = nil
        do {
            let data = try JSONEncoder().encode(rules)
            sharedDefaults.set(data, forKey: Keys.globalRewriteRules)
            routingDataDidChange.send()
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode rewrite rules: \(error.localizedDescription)")
        }
    }

    func loadGlobalRewriteRules() -> [URLRewriteRule] {
        if let cached = cachedGlobalRewriteRules { return cached }
        guard let data = sharedDefaults.data(forKey: Keys.globalRewriteRules) else {
            return BuiltInRewriteRules.all
        }
        let savedRules: [URLRewriteRule]
        do {
            savedRules = try JSONDecoder().decode([URLRewriteRule].self, from: data)
        } catch {
            YojamLogger.shared.log("Failed to decode rewrite rules: \(error.localizedDescription)")
            return BuiltInRewriteRules.all
        }
        // Deduplicate: keep the first occurrence of each (name + pattern) pair.
        // This cleans up duplicates from earlier builds that used random UUIDs
        // for built-in rewrite rules.
        var seen = Set<String>()
        var deduped: [URLRewriteRule] = []
        for rule in savedRules {
            let key = "\(rule.name)|\(rule.matchPattern)|\(rule.replacement)"
            if seen.insert(key).inserted {
                deduped.append(rule)
            }
        }
        let savedIds = Set(deduped.map(\.id))
        let newBuiltIns = BuiltInRewriteRules.all.filter { !savedIds.contains($0.id) }
        // Also skip new built-ins whose name+pattern already exist (migrating old random IDs)
        let finalNew = newBuiltIns.filter { rule in
            !seen.contains("\(rule.name)|\(rule.matchPattern)|\(rule.replacement)")
        }
        let result = deduped + finalNew
        cachedGlobalRewriteRules = result
        return result
    }

    // MARK: - Import / Export

    func exportJSON() throws -> Data {
        let export = SettingsExport(
            version: 5,
            activationMode: activationMode,
            defaultSelection: defaultSelectionBehavior,
            verticalThreshold: verticalThreshold,
            soundEffects: soundEffectsEnabled,
            launchAtLogin: launchAtLogin,
            globalUTMStripping: globalUTMStrippingEnabled,
            clipboardMonitoring: clipboardMonitoringEnabled,
            iCloudSync: iCloudSyncEnabled,
            debugLoggingEnabled: debugLoggingEnabled,
            periodicRescanInterval: periodicRescanInterval,
            browsers: loadBrowsers(),
            emailClients: loadEmailClients(),
            // Include built-in overrides so round-trip preserves user edits.
            rules: loadRules(),
            globalRewriteRules: loadGlobalRewriteRules(),
            utmStripList: utmStripList,
            suppressedClipboardDomains: suppressedClipboardDomains,
            pickerLayout: pickerLayout,
            pickerDirectionOverride: pickerDirectionOverride,
            recentURLRetention: recentURLRetention,
            recentURLRetentionMinutes: recentURLRetentionMinutes,
            deletedBuiltInRuleIds: Array(deletedBuiltInRuleIds()).map(\.uuidString),
            learnedDomainPreferences: {
                guard let data = sharedDefaults.data(forKey: SharedRoutingStore.Keys.learnedDomainPreferences),
                      let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data)
                else { return [:] }
                return decoded
            }()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func importJSON(_ data: Data) throws {
        let imported = try JSONDecoder().decode(SettingsExport.self, from: data)
        activationMode = imported.activationMode
        defaultSelectionBehavior = imported.defaultSelection
        // §43: Clamp imported values to valid ranges
        verticalThreshold = max(4, min(imported.verticalThreshold, 20))
        soundEffectsEnabled = imported.soundEffects
        launchAtLogin = imported.launchAtLogin
        globalUTMStrippingEnabled = imported.globalUTMStripping
        clipboardMonitoringEnabled = imported.clipboardMonitoring
        iCloudSyncEnabled = imported.iCloudSync
        debugLoggingEnabled = imported.debugLoggingEnabled
        periodicRescanInterval = max(60, min(imported.periodicRescanInterval, 86400))
        pickerLayout = imported.pickerLayout
        pickerDirectionOverride = imported.pickerDirectionOverride
        recentURLRetention = imported.recentURLRetention
        recentURLRetentionMinutes = max(1, min(imported.recentURLRetentionMinutes, 1440))
        // Restore user-deleted built-in tombstones from the export payload.
        let importedDeletedIds = Set(imported.deletedBuiltInRuleIds.compactMap { UUID(uuidString: $0) })
        if importedDeletedIds.isEmpty {
            clearDeletedBuiltInRuleIds()
        } else {
            sharedDefaults.set(importedDeletedIds.map(\.uuidString), forKey: Keys.deletedBuiltInRuleIds)
        }
        // Security: disable imported entries with path-based identifiers or
        // customLaunchArgs — these are code-execution vectors via social engineering.
        let sanitizedBrowsers = imported.browsers.map { entry -> BrowserEntry in
            var e = entry
            if e.bundleIdentifier.hasPrefix("/") || e.customLaunchArgs != nil {
                e.enabled = false
            }
            return e
        }
        let sanitizedEmailClients = imported.emailClients.map { entry -> BrowserEntry in
            var e = entry
            if e.bundleIdentifier.hasPrefix("/") || e.customLaunchArgs != nil {
                e.enabled = false
            }
            return e
        }
        saveBrowsers(sanitizedBrowsers)
        saveEmailClients(sanitizedEmailClients)
        // Validate regex patterns and disable path-based targets in imported rules.
        // Rules with absolute-path `targetBundleId` are a code-execution vector
        // (RuleEngine supports bare paths), so imported rules with that shape
        // are force-disabled. Users can re-enable them manually after review.
        let validatedImportedRules: [Rule] = imported.rules.compactMap { rule in
            if rule.matchType == .regex,
               !RegexMatcher.isValid(pattern: rule.pattern) {
                return nil
            }
            var sanitized = rule
            if sanitized.targetBundleId.hasPrefix("/") {
                sanitized.enabled = false
            }
            return sanitized
        }
        // Save imported rules verbatim; loadRules() will insert fresh built-ins
        // for any UUIDs that are missing and not tombstoned.
        saveRules(validatedImportedRules)
        saveGlobalRewriteRules(imported.globalRewriteRules)
        utmStripList = imported.utmStripList
        // Clamp to prevent clipboard-check O(n) blow-up
        suppressedClipboardDomains = Array(imported.suppressedClipboardDomains.prefix(1000))
        // Always restore learned domain preferences, even when empty, so
        // importing a config with `{}` clears stale state.
        if let data = try? JSONEncoder().encode(imported.learnedDomainPreferences) {
            sharedDefaults.set(data, forKey: SharedRoutingStore.Keys.learnedDomainPreferences)
        }
    }

    func resetToDefaults() {
        // Clear app-only settings
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        // Clear shared routing settings
        sharedDefaults.removePersistentDomain(forName: SharedRoutingStore.suiteName)
        self.isEnabled = true
        self.activationMode = .always
        self.defaultSelectionBehavior = .alwaysFirst
        self.globalUTMStrippingEnabled = false
        self.soundEffectsEnabled = false
        self.clipboardMonitoringEnabled = false
        self.iCloudSyncEnabled = false
        self.launchAtLogin = false
        self.verticalThreshold = 8
        self.isFirstLaunch = true
        self.debugLoggingEnabled = false
        self.periodicRescanInterval = 1800
        self.utmStripList = UTMStripper.defaultParameters
        self.suppressedClipboardDomains = []
        self.pickerLayout = .auto
        self.pickerDirectionOverride = .system
        self.recentURLRetention = .forever
        self.recentURLRetentionMinutes = 30
        self.shortlinkResolutionEnabled = false
        self.hasDismissedQuickStart = false
        self.quickStartVisitedActivation = false
        self.quickStartVisitedBrowsers = false
        self.quickStartVisitedTester = false
        saveBrowsers([])
        saveEmailClients([])
        saveRules(BuiltInRules.all)
        saveGlobalRewriteRules(BuiltInRewriteRules.all)
        clearDeletedBuiltInRuleIds()
        objectWillChange.send()
    }
}

struct SettingsExport: Codable {
    let version: Int
    var activationMode: ActivationMode
    var defaultSelection: DefaultSelectionBehavior
    var verticalThreshold: Int
    var soundEffects: Bool
    var launchAtLogin: Bool
    var globalUTMStripping: Bool
    var clipboardMonitoring: Bool
    var iCloudSync: Bool
    var debugLoggingEnabled: Bool
    var periodicRescanInterval: TimeInterval
    var browsers: [BrowserEntry]
    var emailClients: [BrowserEntry]
    var rules: [Rule]
    var globalRewriteRules: [URLRewriteRule]
    var utmStripList: [String]
    var suppressedClipboardDomains: [String]
    var pickerLayout: PickerLayout
    var pickerDirectionOverride: PickerDirectionOverride
    var recentURLRetention: RecentURLRetention
    var recentURLRetentionMinutes: Int
    var deletedBuiltInRuleIds: [String]
    var learnedDomainPreferences: [String: [String: Int]]

    enum CodingKeys: String, CodingKey {
        case version, activationMode, defaultSelection, verticalThreshold
        case soundEffects, launchAtLogin, globalUTMStripping, clipboardMonitoring
        case iCloudSync, debugLoggingEnabled
        case periodicRescanInterval, browsers, emailClients, rules
        case globalRewriteRules, utmStripList, suppressedClipboardDomains
        case pickerLayout, pickerDirectionOverride
        // Legacy key accepted on decode for migration from v4 exports.
        case pickerInvertOrder
        case recentURLRetention, recentURLRetentionMinutes
        case deletedBuiltInRuleIds
        case learnedDomainPreferences
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(activationMode, forKey: .activationMode)
        try c.encode(defaultSelection, forKey: .defaultSelection)
        try c.encode(verticalThreshold, forKey: .verticalThreshold)
        try c.encode(soundEffects, forKey: .soundEffects)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(globalUTMStripping, forKey: .globalUTMStripping)
        try c.encode(clipboardMonitoring, forKey: .clipboardMonitoring)
        try c.encode(iCloudSync, forKey: .iCloudSync)
        try c.encode(debugLoggingEnabled, forKey: .debugLoggingEnabled)
        try c.encode(periodicRescanInterval, forKey: .periodicRescanInterval)
        try c.encode(browsers, forKey: .browsers)
        try c.encode(emailClients, forKey: .emailClients)
        try c.encode(rules, forKey: .rules)
        try c.encode(globalRewriteRules, forKey: .globalRewriteRules)
        try c.encode(utmStripList, forKey: .utmStripList)
        try c.encode(suppressedClipboardDomains, forKey: .suppressedClipboardDomains)
        try c.encode(pickerLayout, forKey: .pickerLayout)
        try c.encode(pickerDirectionOverride, forKey: .pickerDirectionOverride)
        try c.encode(recentURLRetention, forKey: .recentURLRetention)
        try c.encode(recentURLRetentionMinutes, forKey: .recentURLRetentionMinutes)
        try c.encode(deletedBuiltInRuleIds, forKey: .deletedBuiltInRuleIds)
        try c.encode(learnedDomainPreferences, forKey: .learnedDomainPreferences)
    }

    init(version: Int, activationMode: ActivationMode,
         defaultSelection: DefaultSelectionBehavior, verticalThreshold: Int,
         soundEffects: Bool, launchAtLogin: Bool, globalUTMStripping: Bool,
         clipboardMonitoring: Bool, iCloudSync: Bool,
         debugLoggingEnabled: Bool, periodicRescanInterval: TimeInterval,
         browsers: [BrowserEntry], emailClients: [BrowserEntry],
         rules: [Rule], globalRewriteRules: [URLRewriteRule],
         utmStripList: [String], suppressedClipboardDomains: [String] = [],
         pickerLayout: PickerLayout = .auto,
         pickerDirectionOverride: PickerDirectionOverride = .system,
         recentURLRetention: RecentURLRetention = .forever,
         recentURLRetentionMinutes: Int = 30,
         deletedBuiltInRuleIds: [String] = [],
         learnedDomainPreferences: [String: [String: Int]] = [:]) {
        self.version = version
        self.activationMode = activationMode
        self.defaultSelection = defaultSelection
        self.verticalThreshold = verticalThreshold
        self.soundEffects = soundEffects
        self.launchAtLogin = launchAtLogin
        self.globalUTMStripping = globalUTMStripping
        self.clipboardMonitoring = clipboardMonitoring
        self.iCloudSync = iCloudSync
        self.debugLoggingEnabled = debugLoggingEnabled
        self.periodicRescanInterval = periodicRescanInterval
        self.browsers = browsers
        self.emailClients = emailClients
        self.rules = rules
        self.globalRewriteRules = globalRewriteRules
        self.utmStripList = utmStripList
        self.suppressedClipboardDomains = suppressedClipboardDomains
        self.pickerLayout = pickerLayout
        self.pickerDirectionOverride = pickerDirectionOverride
        self.recentURLRetention = recentURLRetention
        self.recentURLRetentionMinutes = recentURLRetentionMinutes
        self.deletedBuiltInRuleIds = deletedBuiltInRuleIds
        self.learnedDomainPreferences = learnedDomainPreferences
    }

    // §52: Use decodeIfPresent for all fields to tolerate version migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 5
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .always
        defaultSelection = try container.decodeIfPresent(DefaultSelectionBehavior.self, forKey: .defaultSelection) ?? .alwaysFirst
        verticalThreshold = try container.decodeIfPresent(Int.self, forKey: .verticalThreshold) ?? 8
        soundEffects = try container.decodeIfPresent(Bool.self, forKey: .soundEffects) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        globalUTMStripping = try container.decodeIfPresent(Bool.self, forKey: .globalUTMStripping) ?? false
        clipboardMonitoring = try container.decodeIfPresent(Bool.self, forKey: .clipboardMonitoring) ?? false
        iCloudSync = try container.decodeIfPresent(Bool.self, forKey: .iCloudSync) ?? false
        debugLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? false
        periodicRescanInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .periodicRescanInterval) ?? 1800
        browsers = try container.decodeIfPresent([BrowserEntry].self, forKey: .browsers) ?? []
        emailClients = try container.decodeIfPresent([BrowserEntry].self, forKey: .emailClients) ?? []
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        globalRewriteRules = try container.decodeIfPresent([URLRewriteRule].self, forKey: .globalRewriteRules) ?? []
        utmStripList = try container.decodeIfPresent([String].self, forKey: .utmStripList) ?? UTMStripper.defaultParameters
        suppressedClipboardDomains = try container.decodeIfPresent([String].self, forKey: .suppressedClipboardDomains) ?? []
        pickerLayout = try container.decodeIfPresent(PickerLayout.self, forKey: .pickerLayout) ?? .auto
        // Migrate legacy pickerInvertOrder → pickerDirectionOverride (.rtl if was true).
        if let direction = try container.decodeIfPresent(PickerDirectionOverride.self, forKey: .pickerDirectionOverride) {
            pickerDirectionOverride = direction
        } else if let legacy = try container.decodeIfPresent(Bool.self, forKey: .pickerInvertOrder) {
            pickerDirectionOverride = legacy ? .rtl : .system
        } else {
            pickerDirectionOverride = .system
        }
        recentURLRetention = try container.decodeIfPresent(RecentURLRetention.self, forKey: .recentURLRetention) ?? .forever
        recentURLRetentionMinutes = try container.decodeIfPresent(Int.self, forKey: .recentURLRetentionMinutes) ?? 30
        deletedBuiltInRuleIds = try container.decodeIfPresent([String].self, forKey: .deletedBuiltInRuleIds) ?? []
        learnedDomainPreferences = try container.decodeIfPresent([String: [String: Int]].self, forKey: .learnedDomainPreferences) ?? [:]
    }
}
