import Foundation
import Combine
import ServiceManagement

enum ActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case always, holdShift, smartFallback
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .always: "Always show picker"
        case .holdShift: "Hold Shift to pick"
        case .smartFallback: "Smart + Fallback"
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
        case .alwaysFirst: "Always first"
        case .lastUsed: "Last used"
        case .smart: "Smart"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

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
    }

    @Published var isFirstLaunch: Bool {
        didSet { defaults.set(isFirstLaunch, forKey: Keys.isFirstLaunch) }
    }
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }
    @Published var defaultSelectionBehavior: DefaultSelectionBehavior {
        didSet { defaults.set(defaultSelectionBehavior.rawValue, forKey: Keys.defaultSelection) }
    }
    @Published var verticalThreshold: Int {
        didSet { defaults.set(verticalThreshold, forKey: Keys.verticalThreshold) }
    }
    @Published var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: Keys.soundEffects) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
    @Published var globalUTMStrippingEnabled: Bool {
        didSet { defaults.set(globalUTMStrippingEnabled, forKey: Keys.globalUTMStripping) }
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
        didSet { defaults.set(utmStripList, forKey: Keys.utmStripList) }
    }
    @Published var suppressedClipboardDomains: [String] {
        didSet { defaults.set(suppressedClipboardDomains, forKey: Keys.suppressedClipboardDomains) }
    }
    @Published var pickerLayout: PickerLayout {
        didSet { defaults.set(pickerLayout.rawValue, forKey: Keys.pickerLayout) }
    }
    @Published var pickerInvertOrder: Bool {
        didSet { defaults.set(pickerInvertOrder, forKey: Keys.pickerInvertOrder) }
    }
    @Published var recentURLRetention: RecentURLRetention {
        didSet { defaults.set(recentURLRetention.rawValue, forKey: Keys.recentURLRetention) }
    }
    @Published var recentURLRetentionMinutes: Int {
        didSet { defaults.set(recentURLRetentionMinutes, forKey: Keys.recentURLRetentionMinutes) }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.isFirstLaunch: true,
            Keys.isEnabled: true,
            Keys.activationMode: ActivationMode.always.rawValue,
            Keys.defaultSelection: DefaultSelectionBehavior.alwaysFirst.rawValue,
            Keys.verticalThreshold: 8,
            Keys.soundEffects: true,
            Keys.periodicRescanInterval: 1800.0,
        ])
        self.isFirstLaunch = d.object(forKey: Keys.isFirstLaunch) as? Bool ?? true
        self.isEnabled = d.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.activationMode = ActivationMode(
            rawValue: d.string(forKey: Keys.activationMode) ?? "") ?? .always
        self.defaultSelectionBehavior = DefaultSelectionBehavior(
            rawValue: d.string(forKey: Keys.defaultSelection) ?? "") ?? .alwaysFirst
        self.verticalThreshold = d.object(forKey: Keys.verticalThreshold) as? Int ?? 8
        self.soundEffectsEnabled = d.object(forKey: Keys.soundEffects) as? Bool ?? true
        self.launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        self.globalUTMStrippingEnabled = d.bool(forKey: Keys.globalUTMStripping)
        self.clipboardMonitoringEnabled = d.bool(forKey: Keys.clipboardMonitoring)
        self.iCloudSyncEnabled = d.bool(forKey: Keys.iCloudSync)
        self.debugLoggingEnabled = d.bool(forKey: Keys.debugLogging)
        self.periodicRescanInterval = d.object(forKey: Keys.periodicRescanInterval)
            as? TimeInterval ?? 1800
        self.utmStripList = d.stringArray(forKey: Keys.utmStripList)
            ?? UTMStripper.defaultParameters
        self.suppressedClipboardDomains = d.stringArray(forKey: Keys.suppressedClipboardDomains) ?? []
        self.pickerLayout = PickerLayout(
            rawValue: d.string(forKey: Keys.pickerLayout) ?? "") ?? .auto
        self.pickerInvertOrder = d.bool(forKey: Keys.pickerInvertOrder)
        self.recentURLRetention = RecentURLRetention(
            rawValue: d.string(forKey: Keys.recentURLRetention) ?? "") ?? .forever
        self.recentURLRetentionMinutes = d.object(forKey: Keys.recentURLRetentionMinutes) as? Int ?? 30
    }

    // MARK: - Complex Data Persistence

    func saveBrowsers(_ browsers: [BrowserEntry]) {
        do {
            let data = try JSONEncoder().encode(browsers)
            defaults.set(data, forKey: Keys.browsers)
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode browsers: \(error.localizedDescription)")
        }
    }

    func loadBrowsers() -> [BrowserEntry] {
        guard let data = defaults.data(forKey: Keys.browsers) else { return [] }
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
            defaults.set(data, forKey: Keys.emailClients)
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode email clients: \(error.localizedDescription)")
        }
    }

    func loadEmailClients() -> [BrowserEntry] {
        guard let data = defaults.data(forKey: Keys.emailClients) else { return [] }
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
            defaults.set(data, forKey: Keys.rules)
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode rules: \(error.localizedDescription)")
        }
    }

    func loadRules() -> [Rule] {
        guard let data = defaults.data(forKey: Keys.rules) else { return BuiltInRules.all }
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
            defaults.set(data, forKey: Keys.globalRewriteRules)
            objectWillChange.send()
        } catch {
            YojamLogger.shared.log("Failed to encode rewrite rules: \(error.localizedDescription)")
        }
    }

    func loadGlobalRewriteRules() -> [URLRewriteRule] {
        guard let data = defaults.data(forKey: Keys.globalRewriteRules) else {
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
            let key = "\(rule.name)|\(rule.matchPattern)"
            if seen.insert(key).inserted {
                deduped.append(rule)
            }
        }
        let savedIds = Set(deduped.map(\.id))
        let newBuiltIns = BuiltInRewriteRules.all.filter { !savedIds.contains($0.id) }
        // Also skip new built-ins whose name+pattern already exist (migrating old random IDs)
        let finalNew = newBuiltIns.filter { rule in
            !seen.contains("\(rule.name)|\(rule.matchPattern)")
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
        verticalThreshold = imported.verticalThreshold
        soundEffectsEnabled = imported.soundEffects
        launchAtLogin = imported.launchAtLogin
        globalUTMStrippingEnabled = imported.globalUTMStripping
        clipboardMonitoringEnabled = imported.clipboardMonitoring
        iCloudSyncEnabled = imported.iCloudSync
        debugLoggingEnabled = imported.debugLoggingEnabled
        periodicRescanInterval = imported.periodicRescanInterval
        pickerLayout = imported.pickerLayout
        pickerInvertOrder = imported.pickerInvertOrder
        recentURLRetention = imported.recentURLRetention
        recentURLRetentionMinutes = imported.recentURLRetentionMinutes
        saveBrowsers(imported.browsers)
        saveEmailClients(imported.emailClients)
        // Preserve user's built-in rule enable/disable states during import
        let currentRules = loadRules()
        let currentBuiltInStates = Dictionary(
            uniqueKeysWithValues: currentRules.filter(\.isBuiltIn).map { ($0.id, $0.enabled) })
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
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        activationMode = try container.decode(ActivationMode.self, forKey: .activationMode)
        defaultSelection = try container.decode(DefaultSelectionBehavior.self, forKey: .defaultSelection)
        verticalThreshold = try container.decode(Int.self, forKey: .verticalThreshold)
        soundEffects = try container.decode(Bool.self, forKey: .soundEffects)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        globalUTMStripping = try container.decode(Bool.self, forKey: .globalUTMStripping)
        clipboardMonitoring = try container.decode(Bool.self, forKey: .clipboardMonitoring)
        iCloudSync = try container.decode(Bool.self, forKey: .iCloudSync)
        debugLoggingEnabled = try container.decode(Bool.self, forKey: .debugLoggingEnabled)
        periodicRescanInterval = try container.decode(TimeInterval.self, forKey: .periodicRescanInterval)
        browsers = try container.decode([BrowserEntry].self, forKey: .browsers)
        emailClients = try container.decode([BrowserEntry].self, forKey: .emailClients)
        rules = try container.decode([Rule].self, forKey: .rules)
        globalRewriteRules = try container.decode([URLRewriteRule].self, forKey: .globalRewriteRules)
        utmStripList = try container.decode([String].self, forKey: .utmStripList)
        suppressedClipboardDomains = try container.decodeIfPresent([String].self, forKey: .suppressedClipboardDomains) ?? []
        pickerLayout = try container.decodeIfPresent(PickerLayout.self, forKey: .pickerLayout) ?? .auto
        pickerInvertOrder = try container.decodeIfPresent(Bool.self, forKey: .pickerInvertOrder) ?? false
        recentURLRetention = try container.decodeIfPresent(RecentURLRetention.self, forKey: .recentURLRetention) ?? .forever
        recentURLRetentionMinutes = try container.decodeIfPresent(Int.self, forKey: .recentURLRetentionMinutes) ?? 30
    }
}
