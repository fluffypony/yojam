import Foundation
import Combine

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
        static let universalClickModifier = "universalClickModifier"
        static let cmdShiftClick = "cmdShiftClick"
        static let ctrlShiftClick = "ctrlShiftClick"
        static let cmdOptionClick = "cmdOptionClick"
        static let iCloudSync = "iCloudSync"
        static let debugLogging = "debugLogging"
        static let periodicRescanInterval = "periodicRescanInterval"
        static let browsers = "browsers"
        static let emailClients = "emailClients"
        static let rules = "rules"
        static let globalRewriteRules = "globalRewriteRules"
        static let utmStripList = "utmStripList"
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
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published var globalUTMStrippingEnabled: Bool {
        didSet { defaults.set(globalUTMStrippingEnabled, forKey: Keys.globalUTMStripping) }
    }
    @Published var clipboardMonitoringEnabled: Bool {
        didSet { defaults.set(clipboardMonitoringEnabled, forKey: Keys.clipboardMonitoring) }
    }
    @Published var universalClickModifierEnabled: Bool {
        didSet { defaults.set(universalClickModifierEnabled, forKey: Keys.universalClickModifier) }
    }
    @Published var cmdShiftClickEnabled: Bool {
        didSet { defaults.set(cmdShiftClickEnabled, forKey: Keys.cmdShiftClick) }
    }
    @Published var ctrlShiftClickEnabled: Bool {
        didSet { defaults.set(ctrlShiftClickEnabled, forKey: Keys.ctrlShiftClick) }
    }
    @Published var cmdOptionClickEnabled: Bool {
        didSet { defaults.set(cmdOptionClickEnabled, forKey: Keys.cmdOptionClick) }
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
        self.isFirstLaunch = !d.bool(forKey: "hasLaunchedBefore")
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
        self.universalClickModifierEnabled = d.bool(forKey: Keys.universalClickModifier)
        self.cmdShiftClickEnabled = d.bool(forKey: Keys.cmdShiftClick)
        self.ctrlShiftClickEnabled = d.bool(forKey: Keys.ctrlShiftClick)
        self.cmdOptionClickEnabled = d.bool(forKey: Keys.cmdOptionClick)
        self.iCloudSyncEnabled = d.bool(forKey: Keys.iCloudSync)
        self.debugLoggingEnabled = d.bool(forKey: Keys.debugLogging)
        self.periodicRescanInterval = d.object(forKey: Keys.periodicRescanInterval)
            as? TimeInterval ?? 1800
        self.utmStripList = d.stringArray(forKey: Keys.utmStripList)
            ?? UTMStripper.defaultParameters
    }

    // MARK: - Complex Data Persistence

    func saveBrowsers(_ browsers: [BrowserEntry]) {
        if let data = try? JSONEncoder().encode(browsers) {
            defaults.set(data, forKey: Keys.browsers)
            objectWillChange.send()
        }
    }

    func loadBrowsers() -> [BrowserEntry] {
        guard let data = defaults.data(forKey: Keys.browsers),
              let browsers = try? JSONDecoder().decode([BrowserEntry].self, from: data)
        else { return [] }
        return browsers
    }

    func saveEmailClients(_ clients: [BrowserEntry]) {
        if let data = try? JSONEncoder().encode(clients) {
            defaults.set(data, forKey: Keys.emailClients)
            objectWillChange.send()
        }
    }

    func loadEmailClients() -> [BrowserEntry] {
        guard let data = defaults.data(forKey: Keys.emailClients),
              let clients = try? JSONDecoder().decode([BrowserEntry].self, from: data)
        else { return [] }
        return clients
    }

    func saveRules(_ rules: [Rule]) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Keys.rules)
            objectWillChange.send()
        }
    }

    func loadRules() -> [Rule] {
        guard let data = defaults.data(forKey: Keys.rules),
              let rules = try? JSONDecoder().decode([Rule].self, from: data)
        else { return BuiltInRules.all }
        return rules
    }

    func saveGlobalRewriteRules(_ rules: [URLRewriteRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Keys.globalRewriteRules)
            objectWillChange.send()
        }
    }

    func loadGlobalRewriteRules() -> [URLRewriteRule] {
        guard let data = defaults.data(forKey: Keys.globalRewriteRules),
              let rules = try? JSONDecoder().decode([URLRewriteRule].self, from: data)
        else { return BuiltInRewriteRules.all }
        return rules
    }

    // MARK: - Import / Export

    func exportJSON() throws -> Data {
        let export = SettingsExport(
            version: 3,
            activationMode: activationMode,
            defaultSelection: defaultSelectionBehavior,
            verticalThreshold: verticalThreshold,
            soundEffects: soundEffectsEnabled,
            launchAtLogin: launchAtLogin,
            globalUTMStripping: globalUTMStrippingEnabled,
            clipboardMonitoring: clipboardMonitoringEnabled,
            iCloudSync: iCloudSyncEnabled,
            browsers: loadBrowsers(),
            emailClients: loadEmailClients(),
            rules: loadRules().filter { !$0.isBuiltIn },
            globalRewriteRules: loadGlobalRewriteRules(),
            utmStripList: utmStripList
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
        saveBrowsers(imported.browsers)
        saveEmailClients(imported.emailClients)
        var allRules = BuiltInRules.all
        allRules.append(contentsOf: imported.rules)
        saveRules(allRules)
        saveGlobalRewriteRules(imported.globalRewriteRules)
        utmStripList = imported.utmStripList
    }

    func resetToDefaults() {
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
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
    var browsers: [BrowserEntry]
    var emailClients: [BrowserEntry]
    var rules: [Rule]
    var globalRewriteRules: [URLRewriteRule]
    var utmStripList: [String]
}
