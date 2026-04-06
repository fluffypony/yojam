import XCTest
@testable import Yojam

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
        store.soundEffectsEnabled = false
        store.verticalThreshold = 15
        store.globalUTMStrippingEnabled = true
        store.resetToDefaults()
        XCTAssertTrue(store.soundEffectsEnabled)
        XCTAssertEqual(store.verticalThreshold, 8)
        XCTAssertFalse(store.globalUTMStrippingEnabled)
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
}
