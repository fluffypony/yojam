import XCTest
@testable import Yojam
import YojamCore

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testFirstLaunchKeyPersistence() {
        let store = SettingsStore()
        let initial = store.isFirstLaunch
        store.isFirstLaunch = false
        let store2 = SettingsStore()
        XCTAssertFalse(store2.isFirstLaunch)
        store.isFirstLaunch = initial
    }

    @MainActor
    func testResetToDefaultsUpdatesInMemory() {
        let store = SettingsStore()
        store.soundEffectsEnabled = true
        store.verticalThreshold = 15
        store.globalUTMStrippingEnabled = true
        store.configFilePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
            .path
        store.resetToDefaults()
        XCTAssertFalse(store.soundEffectsEnabled)
        XCTAssertEqual(store.verticalThreshold, 8)
        XCTAssertFalse(store.globalUTMStrippingEnabled)
        XCTAssertNil(store.configFilePath)
    }

    @MainActor
    func testImportExportRoundTrip() throws {
        let store = SettingsStore()
        store.verticalThreshold = 12
        store.soundEffectsEnabled = false
        store.debugLoggingEnabled = true

        let exported = try store.exportJSON()

        store.verticalThreshold = 8
        store.soundEffectsEnabled = true
        store.debugLoggingEnabled = false
        try store.importJSON(exported)

        XCTAssertEqual(store.verticalThreshold, 12)
        XCTAssertFalse(store.soundEffectsEnabled)
        XCTAssertTrue(store.debugLoggingEnabled)
    }

    @MainActor
    func testLoadRulesMergesNewBuiltIns() {
        let store = SettingsStore()
        let partial = Array(BuiltInRules.all.prefix(3))
        store.saveRules(partial)
        let loaded = store.loadRules()
        XCTAssertGreaterThan(loaded.count, partial.count)
    }

    @MainActor
    func testLoadRulesAddsAppNotionBuiltInToOlderSavedRules() {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }

        let appNotionId = UUID(uuidString: "550e8400-e29b-41d4-a716-44665544001a")!
        let olderRules = BuiltInRules.all.filter { $0.id != appNotionId }
        store.saveRules(olderRules)

        let loaded = store.loadRules()
        let appNotion = loaded.first { $0.id == appNotionId }
        XCTAssertEqual(appNotion?.pattern, "app.notion.com")
        XCTAssertEqual(appNotion?.targetBundleId, "notion.id")
    }

    @MainActor
    func testSaveBrowsersRoundTrip() {
        let store = SettingsStore()
        let original = store.loadBrowsers()
        let browsers = [
            BrowserEntry(bundleIdentifier: "com.test.a", displayName: "A"),
            BrowserEntry(bundleIdentifier: "com.test.b", displayName: "B"),
        ]
        store.saveBrowsers(browsers)
        let loaded = store.loadBrowsers()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].displayName, "A")
        XCTAssertEqual(loaded[1].displayName, "B")
        store.saveBrowsers(original)
    }

    @MainActor
    func testLoadRulesUpdatesBuiltInDefinitions() {
        let store = SettingsStore()
        // Save built-in rules with one disabled
        var rules = BuiltInRules.all
        rules[0].enabled = false
        store.saveRules(rules)

        let loaded = store.loadRules()
        // The first built-in should still be disabled (user state preserved)
        let firstBuiltIn = loaded.first(where: { $0.id == BuiltInRules.all[0].id })
        XCTAssertNotNil(firstBuiltIn)
        XCTAssertFalse(firstBuiltIn!.enabled)
        // But the definition (name, pattern, etc.) should match current code
        XCTAssertEqual(firstBuiltIn!.name, BuiltInRules.all[0].name)
    }

    @MainActor
    func testLoadRulesDropsRemovedBuiltIns() {
        let store = SettingsStore()
        // Create a fake saved rule with a removed built-in ID
        var rules = BuiltInRules.all
        let removedId = UUID(uuidString: "550e8400-e29b-41d4-a716-44665544000a")!
        rules.append(Rule(id: removedId, name: "Google Maps", matchType: .domain,
                          pattern: "maps.google.com", targetBundleId: "com.google.Maps",
                          targetAppName: "Google Maps", isBuiltIn: true))
        store.saveRules(rules)

        let loaded = store.loadRules()
        XCTAssertFalse(loaded.contains(where: { $0.id == removedId }))
    }

    @MainActor
    func testImportPreservesBuiltInStates() throws {
        let store = SettingsStore()
        // Disable a built-in rule
        var rules = BuiltInRules.all
        rules[0].enabled = false
        store.saveRules(rules)

        // Export with custom rules only
        let exported = try store.exportJSON()

        // Import should preserve the disabled state
        try store.importJSON(exported)
        let loaded = store.loadRules()
        let firstBuiltIn = loaded.first(where: { $0.id == BuiltInRules.all[0].id })
        XCTAssertNotNil(firstBuiltIn)
        XCTAssertFalse(firstBuiltIn!.enabled)
    }

    @MainActor
    func testSuppressedClipboardDomainsExportImport() throws {
        let store = SettingsStore()
        store.suppressedClipboardDomains = ["example.com", "test.org"]

        let exported = try store.exportJSON()
        store.suppressedClipboardDomains = []
        try store.importJSON(exported)

        XCTAssertEqual(store.suppressedClipboardDomains, ["example.com", "test.org"])
    }

    @MainActor
    func testCustomConfigFilePathPersistsLocally() {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        defer { store.configFilePath = originalPath }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
            .path
        store.configFilePath = path

        let reloaded = SettingsStore()
        XCTAssertEqual(reloaded.configFilePath, path)
    }

    @MainActor
    func testConfigFileManagerUsesCustomConfigPath() {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        defer { store.configFilePath = originalPath }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        store.configFilePath = path.path

        let manager = ConfigFileManager(settingsStore: store)
        XCTAssertEqual(manager.configPath, path.standardizedFileURL)
    }

    @MainActor
    func testConfigFileManagerImportsExistingConfigOnStart() throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalThreshold = store.verticalThreshold
        defer {
            store.configFilePath = originalPath
            store.verticalThreshold = originalThreshold
        }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        store.verticalThreshold = 13
        try store.exportJSON().write(to: path)
        store.verticalThreshold = 8
        store.configFilePath = path.path

        let manager = ConfigFileManager(settingsStore: store)
        manager.start()

        XCTAssertEqual(store.verticalThreshold, 13)
    }

    @MainActor
    func testConfigFileManagerNotifiesAfterStartupImport() throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        defer { store.configFilePath = originalPath }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        try store.exportJSON().write(to: path)
        store.configFilePath = path.path

        var imported = false
        let manager = ConfigFileManager(settingsStore: store) {
            imported = true
        }
        manager.start()

        XCTAssertTrue(imported)
    }

    @MainActor
    func testConfigMirrorImportRequiresExplicitYojamVersion() throws {
        let store = SettingsStore()
        let originalThreshold = store.verticalThreshold
        defer { store.verticalThreshold = originalThreshold }
        store.verticalThreshold = 14

        XCTAssertThrowsError(try store.importConfigMirrorJSON(Data("{}".utf8)))
        XCTAssertThrowsError(try store.importConfigMirrorJSON(Data(#"{"version":5}"#.utf8)))
        XCTAssertEqual(store.verticalThreshold, 14)
    }

    @MainActor
    func testImportDisablesRulesWithCustomLaunchArgs() throws {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }

        let ruleId = UUID()
        let rule = Rule(
            id: ruleId,
            name: "Imported custom args",
            enabled: true,
            matchType: .domain,
            pattern: "example.com",
            targetBundleId: "org.mozilla.firefox",
            targetAppName: "Firefox",
            ruleCustomLaunchArgs: "--profile /tmp/test-profile")
        let export = SettingsExport(
            version: 5,
            activationMode: .always,
            defaultSelection: .alwaysFirst,
            verticalThreshold: 8,
            soundEffects: false,
            launchAtLogin: false,
            globalUTMStripping: false,
            clipboardMonitoring: false,
            iCloudSync: false,
            debugLoggingEnabled: false,
            periodicRescanInterval: 1800,
            browsers: [],
            emailClients: [],
            rules: [rule],
            globalRewriteRules: [],
            utmStripList: UTMStripper.defaultParameters)

        try store.importJSON(try JSONEncoder().encode(export))

        let imported = try XCTUnwrap(store.loadRules().first { $0.id == ruleId })
        XCTAssertFalse(imported.enabled)
        XCTAssertEqual(imported.ruleCustomLaunchArgs, "--profile /tmp/test-profile")
    }
}
