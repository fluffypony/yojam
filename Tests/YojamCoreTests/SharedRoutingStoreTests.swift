import XCTest
@testable import YojamCore

@MainActor
final class SharedRoutingStoreTests: IsolatedRoutingTestCase {
    func testStoreInitializes() {
        let store = makeSharedStore()
        // Use a separate suite even when the test host has App Group entitlements.
        XCTAssertNotNil(store.defaults)
    }

    func testSuiteNameIsCorrect() {
        XCTAssertEqual(SharedRoutingStore.suiteName, "group.org.yojam.shared")
    }

    func testKeysAreNotEmpty() {
        XCTAssertFalse(SharedRoutingStore.Keys.browsers.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.emailClients.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.phoneClients.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.rules.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.globalRewriteRules.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.utmStripList.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.activationMode.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.defaultSelection.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.globalUTMStripping.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.isEnabled.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.learnedDomainPreferences.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.recentURLs.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.recentURLTimestamps.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.shortlinkResolutionEnabled.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.shortlinkResolutionHosts.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.shortlinkResolutionMode.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.localMachineIdentifier.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.localMachineName.isEmpty)
    }

    func testKeysAreUnique() {
        let allKeys = [
            SharedRoutingStore.Keys.browsers,
            SharedRoutingStore.Keys.emailClients,
            SharedRoutingStore.Keys.phoneClients,
            SharedRoutingStore.Keys.rules,
            SharedRoutingStore.Keys.globalRewriteRules,
            SharedRoutingStore.Keys.utmStripList,
            SharedRoutingStore.Keys.activationMode,
            SharedRoutingStore.Keys.defaultSelection,
            SharedRoutingStore.Keys.globalUTMStripping,
            SharedRoutingStore.Keys.isEnabled,
            SharedRoutingStore.Keys.learnedDomainPreferences,
            SharedRoutingStore.Keys.recentURLs,
            SharedRoutingStore.Keys.recentURLTimestamps,
            SharedRoutingStore.Keys.shortlinkResolutionEnabled,
            SharedRoutingStore.Keys.shortlinkResolutionHosts,
            SharedRoutingStore.Keys.shortlinkResolutionMode,
            SharedRoutingStore.Keys.verticalThreshold,
            SharedRoutingStore.Keys.soundEffects,
            SharedRoutingStore.Keys.localMachineIdentifier,
            SharedRoutingStore.Keys.localMachineName,
        ]
        let unique = Set(allKeys)
        XCTAssertEqual(unique.count, allKeys.count, "All keys should be unique")
    }

    func testReadWriteRoundTripString() {
        let store = makeSharedStore()
        let key = "test_roundtrip_string_\(UUID().uuidString)"
        store.defaults.set("hello", forKey: key)
        XCTAssertEqual(store.defaults.string(forKey: key), "hello")
        store.defaults.removeObject(forKey: key)
    }

    func testReadWriteRoundTripBool() {
        let store = makeSharedStore()
        let key = "test_roundtrip_bool_\(UUID().uuidString)"
        store.defaults.set(true, forKey: key)
        XCTAssertTrue(store.defaults.bool(forKey: key))
        store.defaults.removeObject(forKey: key)
    }

    func testReadWriteRoundTripData() {
        let store = makeSharedStore()
        let key = "test_roundtrip_data_\(UUID().uuidString)"
        let data = "test payload".data(using: .utf8)!
        store.defaults.set(data, forKey: key)
        XCTAssertEqual(store.defaults.data(forKey: key), data)
        store.defaults.removeObject(forKey: key)
    }

    func testReadWriteRoundTripArray() {
        let store = makeSharedStore()
        let key = "test_roundtrip_array_\(UUID().uuidString)"
        let array = ["utm_source", "fbclid", "gclid"]
        store.defaults.set(array, forKey: key)
        XCTAssertEqual(store.defaults.stringArray(forKey: key), array)
        store.defaults.removeObject(forKey: key)
    }

    func testMissingKeyReturnsNil() {
        let store = makeSharedStore()
        let key = "nonexistent_key_\(UUID().uuidString)"
        XCTAssertNil(store.defaults.string(forKey: key))
        XCTAssertNil(store.defaults.data(forKey: key))
    }

    func testIsUsingAppGroupFlagReported() {
        let store = makeSharedStore()
        XCTAssertFalse(store.isUsingAppGroup)
    }

    func testLocalMachineIdentifierPersists() {
        let store = makeSharedStore()
        let first = store.localMachineIdentifier
        let second = store.localMachineIdentifier
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }
}
