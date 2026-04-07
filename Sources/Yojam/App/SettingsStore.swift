import Foundation
import Combine
import ServiceManagement
import YojamCore

enum ActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case always, holdShift, smartFallback
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .always: "Always show picker"
        case .holdShift: "Open directly; hold Shift to choose"
        case .smartFallback: "Auto-pick when confident"
        }
    }
}

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

enum DefaultSelectionBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case alwaysFirst, lastUsed, smart
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .alwaysFirst: "First in browser list"
        case .lastUsed: "Last browser I used"
        case .smart: "Learned preference for this site"
        }
    }
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
        static let pickerInvertOrder = "pickerInvertOrder"
        static let recentURLRetention = "recentURLRetention"
        static let recentURLRetentionMinutes = "recentURLRetentionMinutes"
        static let hasDismissedQuickStart = "hasDismissedQuickStart"
        static let quickStartVisitedActivation = "quickStartVisitedActivation"
        static let quickStartVisitedBrowsers = "quickStartVisitedBrowsers"
        static let quickStartVisitedTester = "quickStartVisitedTester"
    }

    @Published var isFirstLaunch: Bool {
        didSet { defaults.set(isFirstLaunch, forKey: Keys.isFirstLaunch) }
    }
    @Published var isEnabled: Bool {
        didSet { sharedDefaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var activationMode: ActivationMode {
        didSet { sharedDefaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }
    @Published var defaultSelectionBehavior: DefaultSelectionBehavior {
        didSet { sharedDefaults.set(defaultSelectionBehavior.rawValue, forKey: Keys.defaultSelection) }
    }
    @Published var verticalThreshold: Int {
        didSet { sharedDefaults.set(verticalThreshold, forKey: Keys.verticalThreshold) }
    }
    @Published var soundEffectsEnabled: Bool {
        didSet { sharedDefaults.set(soundEffectsEnabled, forKey: Keys.soundEffects) }
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
        didSet { sharedDefaults.set(globalUTMStrippingEnabled, forKey: Keys.globalUTMStripping) }
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
        didSet { sharedDefaults.set(utmStripList, forKey: Keys.utmStripList) }
    }
    @Published var suppressedClipboardDomains: [String] {
        didSet { defaults.set(suppressedClipboardDomains, forKey: Keys.suppressedClipboardDomains) }
    }
    @Published var pickerLayout: PickerLayout {
        didSet { sharedDefaults.set(pickerLayout.rawValue, forKey: Keys.pickerLayout) }
    }
    @Published var pickerInvertOrder: Bool {
        didSet { sharedDefaults.set(pickerInvertOrder, forKey: Keys.pickerInvertOrder) }
    }
    @Published var recentURLRetention: RecentURLRetention {
        didSet { sharedDefaults.set(recentURLRetention.rawValue, forKey: Keys.recentURLRetention) }
    }
    @Published var recentURLRetentionMinutes: Int {
        didSet { sharedDefaults.set(recentURLRetentionMinutes, forKey: Keys.recentURLRetentionMinutes) }
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
            Keys.soundEffects: true,
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
        self.soundEffectsEnabled = s.object(forKey: Keys.soundEffects) as? Bool ?? true
        self.globalUTMStrippingEnabled = s.bool(forKey: Keys.globalUTMStripping)
        self.utmStripList = s.stringArray(forKey: Keys.utmStripList)
            ?? UTMStripper.defaultParameters
        self.pickerLayout = PickerLayout(
            rawValue: s.string(forKey: Keys.pickerLayout) ?? "") ?? .auto
        self.pickerInvertOrder = s.bool(forKey: Keys.pickerInvertOrder)
        self.recentURLRetention = RecentURLRetention(
            rawValue: s.string(forKey: Keys.recentURLRetention) ?? "") ?? .forever
        self.recentURLRetentionMinutes = s.object(forKey: Keys.recentURLRetentionMinutes) as? Int ?? 30
    }

    // MARK: - Complex Data Persistence

    func saveBrowsers(_ browsers: [BrowserEntry]) {
        do {
            let data = try JSONEncoder().encode(browsers)
            sharedDefaults.set(data, forKey: Keys.browsers)
            objectWillChange.send()
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
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode rules: \(error.localizedDescription)")
        }
    }

    func loadRules() -> [Rule] {
        guard let data = sharedDefaults.data(forKey: Keys.rules) else { return BuiltInRules.all }
        let savedRules: [Rule]
        do {
            savedRules = try JSONDecoder().decode([Rule].self, from: data)
        } catch {
            YojamLogger.shared.log("Failed to decode rules: \(error.localizedDescription)")
            return BuiltInRules.all
        }

        // Merge saved rules with current built-in definitions:
        // - Update built-in rule definitions (patterns, bundle IDs) while preserving user's enabled state
        // - Drop removed built-in rules
        // - Append brand-new built-in rules
        let builtInById = Dictionary(uniqueKeysWithValues: BuiltInRules.all.map { ($0.id, $0) })
        var merged: [Rule] = []
        var seenBuiltInIds = Set<UUID>()

        for var rule in savedRules {
            // Drop removed built-ins
            if rule.isBuiltIn && BuiltInRules.removedIds.contains(rule.id) { continue }
            // Update existing built-in definitions, preserve user's enabled state
            if rule.isBuiltIn, let updated = builtInById[rule.id] {
                let wasEnabled = rule.enabled
                rule = updated
                rule.enabled = wasEnabled
                seenBuiltInIds.insert(rule.id)
            }
            merged.append(rule)
        }
        // Append brand-new built-in rules
        for rule in BuiltInRules.all where !seenBuiltInIds.contains(rule.id) {
            merged.append(rule)
        }
        return merged
    }

    func saveGlobalRewriteRules(_ rules: [URLRewriteRule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            sharedDefaults.set(data, forKey: Keys.globalRewriteRules)
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode rewrite rules: \(error.localizedDescription)")
        }
    }

    func loadGlobalRewriteRules() -> [URLRewriteRule] {
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
        return deduped + finalNew
    }

    // MARK: - Import / Export

    func exportJSON() throws -> Data {
        let export = SettingsExport(
            version: 4,
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
            rules: loadRules().filter { !$0.isBuiltIn },
            globalRewriteRules: loadGlobalRewriteRules(),
            utmStripList: utmStripList,
            suppressedClipboardDomains: suppressedClipboardDomains,
            pickerLayout: pickerLayout,
            pickerInvertOrder: pickerInvertOrder,
            recentURLRetention: recentURLRetention,
            recentURLRetentionMinutes: recentURLRetentionMinutes
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
        pickerInvertOrder = imported.pickerInvertOrder
        recentURLRetention = imported.recentURLRetention
        recentURLRetentionMinutes = max(1, min(imported.recentURLRetentionMinutes, 1440))
        saveBrowsers(imported.browsers)
        saveEmailClients(imported.emailClients)
        // Preserve user's built-in rule enable/disable states during import
        let currentRules = loadRules()
        let currentBuiltInStates = Dictionary(
            currentRules.filter(\.isBuiltIn).map { ($0.id, $0.enabled) },
            uniquingKeysWith: { first, _ in first })
        var allRules = BuiltInRules.all.map { rule -> Rule in
            var r = rule
            if let state = currentBuiltInStates[r.id] { r.enabled = state }
            return r
        }
        allRules.append(contentsOf: imported.rules)
        saveRules(allRules)
        saveGlobalRewriteRules(imported.globalRewriteRules)
        utmStripList = imported.utmStripList
        suppressedClipboardDomains = imported.suppressedClipboardDomains
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
        self.soundEffectsEnabled = true
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
        self.pickerInvertOrder = false
        self.recentURLRetention = .forever
        self.recentURLRetentionMinutes = 30
        self.hasDismissedQuickStart = false
        self.quickStartVisitedActivation = false
        self.quickStartVisitedBrowsers = false
        self.quickStartVisitedTester = false
        saveBrowsers([])
        saveEmailClients([])
        saveRules(BuiltInRules.all)
        saveGlobalRewriteRules(BuiltInRewriteRules.all)
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
    var pickerInvertOrder: Bool
    var recentURLRetention: RecentURLRetention
    var recentURLRetentionMinutes: Int

    enum CodingKeys: String, CodingKey {
        case version, activationMode, defaultSelection, verticalThreshold
        case soundEffects, launchAtLogin, globalUTMStripping, clipboardMonitoring
        case iCloudSync, debugLoggingEnabled
        case periodicRescanInterval, browsers, emailClients, rules
        case globalRewriteRules, utmStripList, suppressedClipboardDomains
        case pickerLayout, pickerInvertOrder
        case recentURLRetention, recentURLRetentionMinutes
    }

    init(version: Int, activationMode: ActivationMode,
         defaultSelection: DefaultSelectionBehavior, verticalThreshold: Int,
         soundEffects: Bool, launchAtLogin: Bool, globalUTMStripping: Bool,
         clipboardMonitoring: Bool, iCloudSync: Bool,
         debugLoggingEnabled: Bool, periodicRescanInterval: TimeInterval,
         browsers: [BrowserEntry], emailClients: [BrowserEntry],
         rules: [Rule], globalRewriteRules: [URLRewriteRule],
         utmStripList: [String], suppressedClipboardDomains: [String] = [],
         pickerLayout: PickerLayout = .auto, pickerInvertOrder: Bool = false,
         recentURLRetention: RecentURLRetention = .forever,
         recentURLRetentionMinutes: Int = 30) {
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
        self.pickerInvertOrder = pickerInvertOrder
        self.recentURLRetention = recentURLRetention
        self.recentURLRetentionMinutes = recentURLRetentionMinutes
    }

    // §52: Use decodeIfPresent for all fields to tolerate version migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 4
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .always
        defaultSelection = try container.decodeIfPresent(DefaultSelectionBehavior.self, forKey: .defaultSelection) ?? .alwaysFirst
        verticalThreshold = try container.decodeIfPresent(Int.self, forKey: .verticalThreshold) ?? 8
        soundEffects = try container.decodeIfPresent(Bool.self, forKey: .soundEffects) ?? true
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
        pickerInvertOrder = try container.decodeIfPresent(Bool.self, forKey: .pickerInvertOrder) ?? false
        recentURLRetention = try container.decodeIfPresent(RecentURLRetention.self, forKey: .recentURLRetention) ?? .forever
        recentURLRetentionMinutes = try container.decodeIfPresent(Int.self, forKey: .recentURLRetentionMinutes) ?? 30
    }
}
