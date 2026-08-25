import XCTest
import Combine
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
    func testShortlinkPolicyRoundTripsThroughSettingsExport() throws {
        let store = SettingsStore()
        let originalEnabled = store.shortlinkResolutionEnabled
        let originalHosts = store.shortlinkResolutionHosts
        let originalMode = store.shortlinkResolutionMode
        defer {
            store.shortlinkResolutionHosts = originalHosts
            store.shortlinkResolutionMode = originalMode
            store.shortlinkResolutionEnabled = originalEnabled
        }
        store.shortlinkResolutionHosts = ["Custom.Example", "t.co"]
        store.shortlinkResolutionMode = .exactHostHTTPS
        store.shortlinkResolutionEnabled = true

        let exported = try store.exportJSON()
        let decoded = try JSONDecoder().decode(SettingsExport.self, from: exported)
        XCTAssertEqual(decoded.version, SettingsExport.currentVersion)
        XCTAssertEqual(SettingsExport.currentVersion, 6)
        store.shortlinkResolutionHosts = ShortlinkResolver.defaultShortenerHosts
        store.shortlinkResolutionMode = .exactHostHTTPAndHTTPS
        store.shortlinkResolutionEnabled = false
        try store.importJSON(exported)

        XCTAssertTrue(store.shortlinkResolutionEnabled)
        XCTAssertEqual(store.shortlinkResolutionHosts, ["custom.example", "t.co"])
        XCTAssertEqual(store.shortlinkResolutionMode, .exactHostHTTPS)
    }

    @MainActor
    func testLegacySettingsExportUsesOriginalYojamShortlinkPolicy() throws {
        let store = SettingsStore()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportJSON()) as? [String: Any])
        object.removeValue(forKey: "shortlinkResolutionEnabled")
        object.removeValue(forKey: "shortlinkResolutionHosts")
        object.removeValue(forKey: "shortlinkResolutionMode")

        let decoded = try JSONDecoder().decode(
            SettingsExport.self,
            from: JSONSerialization.data(withJSONObject: object))

        XCTAssertFalse(decoded.shortlinkResolutionEnabled)
        XCTAssertEqual(
            Set(decoded.shortlinkResolutionHosts),
            ShortlinkResolver.defaultShortenerHosts)
        XCTAssertEqual(decoded.shortlinkResolutionMode, .exactHostHTTPAndHTTPS)
    }

    @MainActor
    func testLegacySettingsImportKeepsCurrentShortlinkPolicy() throws {
        let store = SettingsStore()
        let originalEnabled = store.shortlinkResolutionEnabled
        let originalHosts = store.shortlinkResolutionHosts
        let originalMode = store.shortlinkResolutionMode
        defer {
            store.shortlinkResolutionHosts = originalHosts
            store.shortlinkResolutionMode = originalMode
            store.shortlinkResolutionEnabled = originalEnabled
        }

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportJSON()) as? [String: Any])
        object.removeValue(forKey: "shortlinkResolutionEnabled")
        object.removeValue(forKey: "shortlinkResolutionHosts")
        object.removeValue(forKey: "shortlinkResolutionMode")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        store.shortlinkResolutionHosts = ["custom.example"]
        store.shortlinkResolutionMode = .exactHostHTTPS
        store.shortlinkResolutionEnabled = true
        try store.importJSON(legacyData)

        XCTAssertEqual(store.shortlinkResolutionHosts, ["custom.example"])
        XCTAssertEqual(store.shortlinkResolutionMode, .exactHostHTTPS)
        XCTAssertTrue(store.shortlinkResolutionEnabled)
    }

    @MainActor
    func testCanonicalShortlinkHostsPersistAndPublishRoutingChange() {
        let store = SettingsStore()
        let originalHosts = store.shortlinkResolutionHosts
        let defaults = store.sharedStore.defaults
        let key = SharedRoutingStore.Keys.shortlinkResolutionHosts
        let originalStoredValue = defaults.object(forKey: key)
        defer {
            store.shortlinkResolutionHosts = originalHosts
            if let originalStoredValue {
                defaults.set(originalStoredValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        var changeCount = 0
        let cancellable = store.routingDataDidChange.sink { changeCount += 1 }
        store.shortlinkResolutionHosts = [" Custom.Example. ", "T.CO"]

        XCTAssertEqual(store.shortlinkResolutionHosts, ["custom.example", "t.co"])
        XCTAssertEqual(
            defaults.stringArray(forKey: key),
            ["custom.example", "t.co"])
        XCTAssertEqual(changeCount, 1)
        cancellable.cancel()
    }

    @MainActor
    func testICloudScalarSettingsPublishRoutingChanges() {
        let store = SettingsStore()
        let originalClipboard = store.clipboardMonitoringEnabled
        let originalDebug = store.debugLoggingEnabled
        let originalInterval = store.periodicRescanInterval
        defer {
            store.clipboardMonitoringEnabled = originalClipboard
            store.debugLoggingEnabled = originalDebug
            store.periodicRescanInterval = originalInterval
        }

        var changeCount = 0
        let cancellable = store.routingDataDidChange.sink { changeCount += 1 }
        store.clipboardMonitoringEnabled.toggle()
        store.debugLoggingEnabled.toggle()
        store.periodicRescanInterval = originalInterval == 3600 ? 3601 : 3600

        XCTAssertEqual(changeCount, 3)
        cancellable.cancel()
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
    func testSavePhoneClientsRoundTrip() {
        let store = SettingsStore()
        let original = store.loadPhoneClients()
        defer { store.savePhoneClients(original) }

        let clients = [
            BrowserEntry(bundleIdentifier: "com.apple.FaceTime", displayName: "FaceTime"),
            BrowserEntry(bundleIdentifier: "com.microsoft.teams2", displayName: "Teams"),
        ]
        store.savePhoneClients(clients)

        let loaded = store.loadPhoneClients()
        XCTAssertEqual(loaded.map(\.displayName), ["FaceTime", "Teams"])
    }

    @MainActor
    func testGlobalRewriteLoadOnlyDeduplicatesExactBehaviour() {
        let store = SettingsStore()
        let original = store.loadGlobalRewriteRules()
        defer { store.saveGlobalRewriteRules(original) }

        let base = URLRewriteRule(
            name: "Shared text",
            matchPattern: "https://example.com/(.*)",
            replacement: "https://example.net/$1",
            isRegex: true,
            scope: .global,
            urlNormalization: .none)
        let exactDuplicate = URLRewriteRule(
            name: base.name,
            enabled: base.enabled,
            matchPattern: base.matchPattern,
            replacement: base.replacement,
            isRegex: base.isRegex,
            scope: base.scope,
            urlNormalization: base.urlNormalization)
        let variants = [
            URLRewriteRule(
                name: base.name,
                enabled: false,
                matchPattern: base.matchPattern,
                replacement: base.replacement,
                isRegex: base.isRegex,
                scope: base.scope,
                urlNormalization: base.urlNormalization),
            URLRewriteRule(
                name: base.name,
                enabled: base.enabled,
                matchPattern: base.matchPattern,
                replacement: base.replacement,
                isRegex: false,
                scope: base.scope,
                urlNormalization: base.urlNormalization),
            URLRewriteRule(
                name: base.name,
                enabled: base.enabled,
                matchPattern: base.matchPattern,
                replacement: base.replacement,
                isRegex: base.isRegex,
                scope: .browser("com.example.browser"),
                urlNormalization: base.urlNormalization),
            URLRewriteRule(
                name: base.name,
                enabled: base.enabled,
                matchPattern: base.matchPattern,
                replacement: base.replacement,
                isRegex: base.isRegex,
                scope: base.scope,
                urlNormalization: .whatwg),
            URLRewriteRule(
                name: base.name,
                enabled: base.enabled,
                matchPattern: base.matchPattern,
                replacement: base.replacement,
                isRegex: base.isRegex,
                scope: base.scope,
                urlNormalization: base.urlNormalization,
                metadata: ["importedFrom": "finicky"]),
        ]

        store.saveGlobalRewriteRules([base, exactDuplicate] + variants)

        let loaded = store.loadGlobalRewriteRules()
        let expected = [base] + variants
        let expectedIds = Set(expected.map(\.id))
        XCTAssertEqual(loaded.filter { expectedIds.contains($0.id) }, expected)
        XCTAssertFalse(loaded.contains { $0.id == exactDuplicate.id })
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
    func testPortableConfigMirrorIgnoresMachineLocalBrowserState() throws {
        let store = SettingsStore()
        let originalBrowsers = store.loadBrowsers()
        defer { store.saveBrowsers(originalBrowsers) }

        let id = UUID()
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var entry = BrowserEntry(
            id: id,
            bundleIdentifier: "com.example.browser",
            displayName: "Example",
            isInstalled: false,
            lastSeenAt: Date(timeIntervalSince1970: 100),
            lastModifiedAt: modifiedAt)
        store.saveBrowsers([entry])
        let first = try store.exportConfigMirrorJSON()

        entry.isInstalled = true
        entry.lastSeenAt = Date(timeIntervalSince1970: 200)
        store.saveBrowsers([entry])
        let second = try store.exportConfigMirrorJSON()

        XCTAssertEqual(first, second)
        let decoded = try JSONDecoder().decode(SettingsExport.self, from: second)
        XCTAssertTrue(try XCTUnwrap(decoded.browsers.first).isInstalled)
        XCTAssertNil(decoded.browsers.first?.lastSeenAt)
        XCTAssertEqual(decoded.browsers.first?.lastModifiedAt, modifiedAt)
    }

    @MainActor
    func testConfigMirrorImportPreservesLocalBrowserState() throws {
        let store = SettingsStore()
        let originalBrowsers = store.loadBrowsers()
        defer { store.saveBrowsers(originalBrowsers) }

        let id = UUID()
        let localLastSeen = Date(timeIntervalSince1970: 300)
        let local = BrowserEntry(
            id: id,
            bundleIdentifier: "com.example.browser",
            displayName: "Before",
            isInstalled: false,
            lastSeenAt: localLastSeen,
            lastModifiedAt: Date(timeIntervalSince1970: 100))
        store.saveBrowsers([local])

        var imported = try JSONDecoder().decode(
            SettingsExport.self, from: store.exportJSON())
        imported.browsers[0].displayName = "After"
        imported.browsers[0].isInstalled = true
        imported.browsers[0].lastSeenAt = Date(timeIntervalSince1970: 400)
        imported.browsers[0].lastModifiedAt = Date(timeIntervalSince1970: 500)

        try store.importConfigMirrorJSON(try JSONEncoder().encode(imported))

        let result = try XCTUnwrap(store.loadBrowsers().first)
        XCTAssertEqual(result.displayName, "After")
        XCTAssertFalse(result.isInstalled)
        XCTAssertEqual(result.lastSeenAt, localLastSeen)
        XCTAssertEqual(result.lastModifiedAt, Date(timeIntervalSince1970: 500))
    }

    @MainActor
    func testConfigMirrorImportRechecksRetargetedBrowserState() throws {
        let store = SettingsStore()
        let originalBrowsers = store.loadBrowsers()
        defer { store.saveBrowsers(originalBrowsers) }

        let id = UUID()
        let local = BrowserEntry(
            id: id,
            bundleIdentifier: "/bin/echo",
            displayName: "Installed",
            isInstalled: true,
            lastSeenAt: Date(timeIntervalSince1970: 300))
        store.saveBrowsers([local])

        var imported = try JSONDecoder().decode(
            SettingsExport.self, from: store.exportJSON())
        imported.browsers[0].bundleIdentifier =
            "/definitely/not/an/installed/yojam-test-browser"
        imported.browsers[0].displayName = "Missing"

        try store.importConfigMirrorJSON(try JSONEncoder().encode(imported))

        let result = try XCTUnwrap(store.loadBrowsers().first)
        XCTAssertEqual(result.displayName, "Missing")
        XCTAssertFalse(result.isInstalled)
        XCTAssertNil(result.lastSeenAt)
    }

    @MainActor
    func testIdenticalConfigMirrorImportEmitsNoRoutingChanges() throws {
        let store = SettingsStore()
        let data = try store.exportConfigMirrorJSON()
        var notificationCount = 0
        let cancellable = store.routingDataDidChange.sink {
            notificationCount += 1
        }
        defer { cancellable.cancel() }

        try store.importConfigMirrorJSON(data)

        XCTAssertEqual(notificationCount, 0)
    }

    @MainActor
    func testLearnedPreferenceImportEmitsConfigChange() throws {
        let store = SettingsStore()
        let defaults = store.sharedStore.defaults
        let key = SharedRoutingStore.Keys.learnedDomainPreferences
        let originalData = defaults.data(forKey: key)
        var imported = try JSONDecoder().decode(
            SettingsExport.self, from: store.exportJSON())
        let domain = "imported-\(UUID().uuidString).invalid"
        imported.learnedDomainPreferences[domain] = ["browser-a": 3]
        var configNotificationCount = 0
        var routingNotificationCount = 0
        let configCancellable = store.configMirrorDataDidChange.sink {
            configNotificationCount += 1
        }
        let routingCancellable = store.routingDataDidChange.sink {
            routingNotificationCount += 1
        }
        defer {
            configCancellable.cancel()
            routingCancellable.cancel()
            if let originalData {
                defaults.set(originalData, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        try store.importJSON(try JSONEncoder().encode(imported))

        XCTAssertEqual(configNotificationCount, 1)
        XCTAssertEqual(routingNotificationCount, 0)
    }

    @MainActor
    func testConfigMirrorSettingsEmitExpectedRoutingChanges() {
        let store = SettingsStore()
        let originalClipboardMonitoring = store.clipboardMonitoringEnabled
        let originalICloudSync = store.iCloudSyncEnabled
        let originalDebugLogging = store.debugLoggingEnabled
        let originalRescanInterval = store.periodicRescanInterval
        let originalSuppressedDomains = store.suppressedClipboardDomains
        let originalPickerLayout = store.pickerLayout
        let originalPickerDirection = store.pickerDirectionOverride
        let originalRetention = store.recentURLRetention
        let originalRetentionMinutes = store.recentURLRetentionMinutes

        var configNotificationCount = 0
        var routingNotificationCount = 0
        let configCancellable = store.configMirrorDataDidChange.sink {
            configNotificationCount += 1
        }
        let routingCancellable = store.routingDataDidChange.sink {
            routingNotificationCount += 1
        }
        defer {
            configCancellable.cancel()
            routingCancellable.cancel()
            store.clipboardMonitoringEnabled = originalClipboardMonitoring
            store.iCloudSyncEnabled = originalICloudSync
            store.debugLoggingEnabled = originalDebugLogging
            store.periodicRescanInterval = originalRescanInterval
            store.suppressedClipboardDomains = originalSuppressedDomains
            store.pickerLayout = originalPickerLayout
            store.pickerDirectionOverride = originalPickerDirection
            store.recentURLRetention = originalRetention
            store.recentURLRetentionMinutes = originalRetentionMinutes
        }

        store.clipboardMonitoringEnabled.toggle()
        store.iCloudSyncEnabled.toggle()
        store.debugLoggingEnabled.toggle()
        store.periodicRescanInterval += 1
        store.suppressedClipboardDomains.append("mirror-event-\(UUID().uuidString).invalid")
        store.pickerLayout = originalPickerLayout == .auto ? .smallHorizontal : .auto
        store.pickerDirectionOverride = originalPickerDirection == .system ? .ltr : .system
        store.recentURLRetention = originalRetention == .never ? .forever : .never
        store.recentURLRetentionMinutes = originalRetentionMinutes == 1 ? 2 : 1

        XCTAssertEqual(configNotificationCount, 9)
        XCTAssertEqual(routingNotificationCount, 3)
    }

    @MainActor
    func testDeletedBuiltInRuleIdsEmitOnlyWhenTheyChange() {
        let store = SettingsStore()
        let originalDeletedIds = store.deletedBuiltInRuleIds()
        let newId = UUID()
        var configNotificationCount = 0
        var routingNotificationCount = 0
        let configCancellable = store.configMirrorDataDidChange.sink {
            configNotificationCount += 1
        }
        let routingCancellable = store.routingDataDidChange.sink {
            routingNotificationCount += 1
        }
        defer {
            configCancellable.cancel()
            routingCancellable.cancel()
            store.clearDeletedBuiltInRuleIds()
            for id in originalDeletedIds {
                store.addDeletedBuiltInRuleId(id)
            }
        }

        store.addDeletedBuiltInRuleId(newId)
        store.addDeletedBuiltInRuleId(newId)
        store.clearDeletedBuiltInRuleIds()
        store.clearDeletedBuiltInRuleIds()

        XCTAssertEqual(configNotificationCount, 2)
        XCTAssertEqual(routingNotificationCount, 0)
    }

    @MainActor
    func testConfigFileManagerWritesMirrorOnlySettingChange() async throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalDebugLogging = store.debugLoggingEnabled
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        store.configFilePath = path.path
        var writeCount = 0
        let wroteChange = expectation(description: "mirror-only config write")
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0.05,
            onWrite: {
                writeCount += 1
                if writeCount == 2 { wroteChange.fulfill() }
            })
        defer {
            manager = nil
            store.configFilePath = originalPath
            store.debugLoggingEnabled = originalDebugLogging
            try? FileManager.default.removeItem(at: path)
        }
        manager?.start()
        XCTAssertEqual(writeCount, 1)

        store.debugLoggingEnabled.toggle()

        await fulfillment(of: [wroteChange], timeout: 1)
        let written = try JSONDecoder().decode(
            SettingsExport.self, from: Data(contentsOf: path))
        XCTAssertEqual(written.debugLoggingEnabled, store.debugLoggingEnabled)
        XCTAssertEqual(writeCount, 2)
    }

    @MainActor
    func testConfigFileManagerSkipsByteIdenticalWrite() throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        store.configFilePath = path.path
        var writeCount = 0
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0,
            onWrite: { writeCount += 1 })
        defer {
            manager = nil
            store.configFilePath = originalPath
            try? FileManager.default.removeItem(at: path)
        }

        manager?.writeConfig()
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: path.path)
        manager?.writeConfig()
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: path.path)

        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(
            firstAttributes[.systemFileNumber] as? NSNumber,
            secondAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(
            firstAttributes[.modificationDate] as? Date,
            secondAttributes[.modificationDate] as? Date)
    }

    @MainActor
    func testConfigFileManagerPreservesInvalidExistingMirror() throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        let invalidData = Data("{\n".utf8)
        try invalidData.write(to: path, options: .atomic)
        store.configFilePath = path.path
        var writeCount = 0
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0,
            onWrite: { writeCount += 1 })
        defer {
            manager = nil
            store.configFilePath = originalPath
            try? FileManager.default.removeItem(at: path)
        }

        manager?.start()

        XCTAssertEqual(try Data(contentsOf: path), invalidData)
        XCTAssertEqual(writeCount, 0)
    }

    @MainActor
    func testStartupImportMigratesAvailabilityDerivedBuiltInDisable() throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalRules = store.loadRules()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        defer {
            store.configFilePath = originalPath
            store.saveRules(originalRules)
            try? FileManager.default.removeItem(at: path)
        }

        let builtInId = BuiltInRules.all[0].id
        store.saveRules(BuiltInRules.all)
        let engine = RuleEngine(settingsStore: store)
        var mirror = try JSONDecoder().decode(
            SettingsExport.self, from: store.exportConfigMirrorJSON())
        let mirrorIndex = try XCTUnwrap(
            mirror.rules.firstIndex { $0.id == builtInId })
        mirror.rules[mirrorIndex].enabled = false
        mirror.rules[mirrorIndex].lastModifiedAt = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(mirror).write(to: path, options: .atomic)
        store.configFilePath = path.path
        let manager = ConfigFileManager(settingsStore: store) {
            engine.reloadRules()
        }

        manager.start()

        XCTAssertTrue(try XCTUnwrap(
            engine.rules.first { $0.id == builtInId }).enabled)
        let canonicalMirror = try JSONDecoder().decode(
            SettingsExport.self, from: Data(contentsOf: path))
        XCTAssertTrue(try XCTUnwrap(
            canonicalMirror.rules.first { $0.id == builtInId }).enabled)
    }

    @MainActor
    func testPortableConfigMirrorSortsDeletedBuiltInRuleIds() throws {
        let store = SettingsStore()
        let originalDeletedIds = store.deletedBuiltInRuleIds()
        defer {
            store.clearDeletedBuiltInRuleIds()
            for id in originalDeletedIds {
                store.addDeletedBuiltInRuleId(id)
            }
        }
        store.clearDeletedBuiltInRuleIds()
        let deletedIds = BuiltInRules.all.prefix(2).map(\.id)
        for id in deletedIds {
            store.addDeletedBuiltInRuleId(id)
        }

        let exported = try JSONDecoder().decode(
            SettingsExport.self, from: store.exportConfigMirrorJSON())

        XCTAssertEqual(
            exported.deletedBuiltInRuleIds,
            deletedIds.map(\.uuidString).sorted())
    }

    @MainActor
    func testConfigFileManagerDebouncesBurstIntoOneWrite() async throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalThreshold = store.verticalThreshold
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        store.configFilePath = path.path
        var writeCount = 0
        let wroteBurst = expectation(description: "debounced config write")
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0.05,
            onWrite: {
                writeCount += 1
                if writeCount == 2 { wroteBurst.fulfill() }
            })
        defer {
            manager = nil
            store.configFilePath = originalPath
            store.verticalThreshold = originalThreshold
            try? FileManager.default.removeItem(at: path)
        }
        manager?.start()
        XCTAssertEqual(writeCount, 1)

        store.verticalThreshold = 9
        store.verticalThreshold = 10
        store.verticalThreshold = 11

        await fulfillment(of: [wroteBurst], timeout: 1)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(writeCount, 2)
    }

    @MainActor
    func testExternalConfigImportIsNotWrittenBack() async throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalThreshold = store.verticalThreshold
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        let initialData = try store.exportConfigMirrorJSON()
        try initialData.write(to: path, options: .atomic)
        store.configFilePath = path.path

        var importCount = 0
        var writeCount = 0
        let importedExternalChange = expectation(description: "external config import")
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0.05,
            onImport: {
                importCount += 1
                if importCount == 2 { importedExternalChange.fulfill() }
            },
            onWrite: { writeCount += 1 })
        defer {
            manager = nil
            store.configFilePath = originalPath
            store.verticalThreshold = originalThreshold
            try? FileManager.default.removeItem(at: path)
        }
        manager?.start()
        XCTAssertEqual(importCount, 1)
        XCTAssertEqual(writeCount, 0)

        var external = try JSONDecoder().decode(SettingsExport.self, from: initialData)
        external.verticalThreshold = 12
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(external).write(to: path, options: .atomic)

        await fulfillment(of: [importedExternalChange], timeout: 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.verticalThreshold, 12)
        XCTAssertEqual(writeCount, 0)
    }

    @MainActor
    func testRapidExternalReplacementsImportLatestMirror() async throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalThreshold = store.verticalThreshold
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-config.json")
        let initialData = try store.exportConfigMirrorJSON()
        try initialData.write(to: path, options: .atomic)
        store.configFilePath = path.path
        let importedLatest = expectation(description: "latest config replacement imported")
        var writeCount = 0
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0.05,
            onImport: {
                if store.verticalThreshold == 13 {
                    importedLatest.fulfill()
                }
            },
            onWrite: { writeCount += 1 })
        defer {
            manager = nil
            store.configFilePath = originalPath
            store.verticalThreshold = originalThreshold
            try? FileManager.default.removeItem(at: path)
        }
        manager?.start()

        var first = try JSONDecoder().decode(
            SettingsExport.self, from: initialData)
        first.verticalThreshold = 12
        var latest = first
        latest.verticalThreshold = 13
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(first).write(to: path, options: .atomic)
        try encoder.encode(latest).write(to: path, options: .atomic)

        await fulfillment(of: [importedLatest], timeout: 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.verticalThreshold, 13)
        XCTAssertEqual(writeCount, 0)
    }

    @MainActor
    func testConfigFileManagerSwitchesToPublishedCustomPath() async throws {
        let store = SettingsStore()
        let originalPath = store.configFilePath
        let originalThreshold = store.verticalThreshold
        let firstPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-first.json")
        let secondPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-\(UUID().uuidString)-second.json")
        let initialData = try store.exportConfigMirrorJSON()
        try initialData.write(to: firstPath, options: .atomic)
        var secondExport = try JSONDecoder().decode(
            SettingsExport.self, from: initialData)
        secondExport.verticalThreshold = 13
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(secondExport).write(to: secondPath, options: .atomic)
        store.configFilePath = firstPath.path
        let wroteNewPath = expectation(description: "new config path written")
        var manager: ConfigFileManager? = ConfigFileManager(
            settingsStore: store,
            writeDelay: 0.05,
            onWrite: {
                if store.verticalThreshold == 14 {
                    wroteNewPath.fulfill()
                }
            })
        defer {
            manager = nil
            store.configFilePath = originalPath
            store.verticalThreshold = originalThreshold
            try? FileManager.default.removeItem(at: firstPath)
            try? FileManager.default.removeItem(at: secondPath)
        }
        manager?.start()

        store.configFilePath = secondPath.path

        XCTAssertEqual(manager?.configPath, secondPath.standardizedFileURL)
        XCTAssertEqual(store.verticalThreshold, 13)
        XCTAssertEqual(try Data(contentsOf: firstPath), initialData)

        store.verticalThreshold = 14
        await fulfillment(of: [wroteNewPath], timeout: 2)
        let written = try JSONDecoder().decode(
            SettingsExport.self, from: Data(contentsOf: secondPath))
        XCTAssertEqual(written.verticalThreshold, 14)
        XCTAssertEqual(try Data(contentsOf: firstPath), initialData)
    }

    @MainActor
    func testRepeatedMissingEmailClientRemovalDoesNotResave() {
        let store = SettingsStore()
        let originalBrowsers = store.loadBrowsers()
        let originalEmailClients = store.loadEmailClients()
        let originalPhoneClients = store.loadPhoneClients()
        defer {
            store.saveBrowsers(originalBrowsers)
            store.saveEmailClients(originalEmailClients)
            store.savePhoneClients(originalPhoneClients)
        }

        let bundleId = "com.example.missing-mail"
        store.saveBrowsers([])
        store.saveEmailClients([
            BrowserEntry(
                bundleIdentifier: bundleId,
                displayName: "Missing Mail",
                isInstalled: true)
        ])
        store.savePhoneClients([])
        let manager = BrowserManager(settingsStore: store)
        var notificationCount = 0
        let cancellable = store.routingDataDidChange.sink {
            notificationCount += 1
        }
        defer { cancellable.cancel() }

        XCTAssertTrue(manager.handleAppRemoved(bundleId: bundleId))
        let firstRemovalNotifications = notificationCount
        XCTAssertEqual(firstRemovalNotifications, 1)
        XCTAssertFalse(manager.handleAppRemoved(bundleId: bundleId))
        XCTAssertEqual(notificationCount, firstRemovalNotifications)
    }

    @MainActor
    func testRepeatedInstalledBrowserEventDoesNotResaveOrSuggestDuplicate() {
        let store = SettingsStore()
        let originalBrowsers = store.loadBrowsers()
        defer { store.saveBrowsers(originalBrowsers) }
        let bundleId = "com.example.installed-browser"
        store.saveBrowsers([
            BrowserEntry(
                bundleIdentifier: bundleId,
                displayName: "Installed Browser",
                isInstalled: false)
        ])
        let manager = BrowserManager(settingsStore: store)
        var notificationCount = 0
        let cancellable = store.routingDataDidChange.sink {
            notificationCount += 1
        }
        defer { cancellable.cancel() }
        let appURL = URL(fileURLWithPath: "/Applications/Installed Browser.app")

        manager.handleAppInstalled(bundleId: bundleId, appURL: appURL)
        let firstInstallationNotifications = notificationCount
        manager.handleAppInstalled(bundleId: bundleId, appURL: appURL)

        XCTAssertEqual(firstInstallationNotifications, 1)
        XCTAssertEqual(notificationCount, firstInstallationNotifications)
        XCTAssertTrue(manager.suggestedBrowsers.isEmpty)
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
