import XCTest
@testable import Yojam

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testFirstLaunchKeyPersistence() {
        let store = SettingsStore()
        let initial = store.isFirstLaunch
        store.isFirstLaunch = false
        // Creating a new store should read the saved value
        let store2 = SettingsStore()
        XCTAssertFalse(store2.isFirstLaunch)
        // Restore
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

        // Reset and import
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
        // Save some rules
        let partial = Array(BuiltInRules.all.prefix(3))
        store.saveRules(partial)
        // Load should merge in the remaining built-in rules
        let loaded = store.loadRules()
        XCTAssertGreaterThan(loaded.count, partial.count)
    }

    @MainActor
    func testSaveBrowsersRoundTrip() {
        let store = SettingsStore()
        let browsers = [
            BrowserEntry(bundleIdentifier: "com.test.a", displayName: "A"),
            BrowserEntry(bundleIdentifier: "com.test.b", displayName: "B"),
        ]
        store.saveBrowsers(browsers)
        let loaded = store.loadBrowsers()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].displayName, "A")
        XCTAssertEqual(loaded[1].displayName, "B")
    }
}
