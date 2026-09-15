import XCTest
@testable import Yojam
import YojamCore

class IsolatedSettingsTestCase: XCTestCase {
    let appSuiteName = "org.yojam.tests.app.\(UUID().uuidString)"
    let routingSuiteName = "org.yojam.tests.routing.\(UUID().uuidString)"
    let configDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("yojam-tests-\(UUID().uuidString)", isDirectory: true)

    func makeSharedStore() -> SharedRoutingStore {
        SharedRoutingStore(suiteName: routingSuiteName)
    }

    @MainActor
    func makeSettingsStore(updateLoginItem: @escaping (Bool) throws -> Void = { _ in }) -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: appSuiteName)!,
                      defaultsDomainName: appSuiteName, sharedStore: makeSharedStore(),
                      updateLoginItem: updateLoginItem)
    }

    @MainActor
    func makeConfigFileManager(
        settingsStore: SettingsStore,
        writeDelay: TimeInterval = 0.3,
        onImport: (() -> Void)? = nil,
        onWrite: (() -> Void)? = nil
    ) -> ConfigFileManager {
        ConfigFileManager(settingsStore: settingsStore,
                          defaultConfigPath: configDirectory.appendingPathComponent("config.json"),
                          writeDelay: writeDelay, onImport: onImport, onWrite: onWrite)
    }

    @MainActor
    func makeRoutingSuggestionEngine(
        saveDelay: TimeInterval = 2.0,
        onPersistedChange: @escaping @MainActor () -> Void = {}
    ) -> RoutingSuggestionEngine {
        RoutingSuggestionEngine(sharedDefaults: makeSharedStore().defaults,
                                saveDelay: saveDelay, onPersistedChange: onPersistedChange)
    }

    override func tearDown() {
        UserDefaults(suiteName: appSuiteName)?.removePersistentDomain(forName: appSuiteName)
        UserDefaults(suiteName: routingSuiteName)?.removePersistentDomain(forName: routingSuiteName)
        try? FileManager.default.removeItem(at: configDirectory)
        super.tearDown()
    }
}
