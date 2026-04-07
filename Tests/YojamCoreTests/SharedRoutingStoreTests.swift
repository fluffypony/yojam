import XCTest
@testable import YojamCore

@MainActor
final class SharedRoutingStoreTests: XCTestCase {
    func testStoreInitializes() {
        let store = SharedRoutingStore()
        // In test environment without entitlements, falls back to .standard
        XCTAssertNotNil(store.defaults)
    }

    func testSuiteNameIsCorrect() {
        XCTAssertEqual(SharedRoutingStore.suiteName, "group.org.yojam.shared")
    }

    func testKeysAreNotEmpty() {
        XCTAssertFalse(SharedRoutingStore.Keys.browsers.isEmpty)
        XCTAssertFalse(SharedRoutingStore.Keys.emailClients.isEmpty)
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
    }

    func testKeysAreUnique() {
        let allKeys = [
            SharedRoutingStore.Keys.browsers,
            SharedRoutingStore.Keys.emailClients,
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
            SharedRoutingStore.Keys.verticalThreshold,
            SharedRoutingStore.Keys.soundEffects,
        ]
        let unique = Set(allKeys)
        XCTAssertEqual(unique.count, allKeys.count, "All keys should be unique")
    }

    func testReadWriteRoundTripString() {
        let store = SharedRoutingStore()
        let key = "test_roundtrip_string_\(UUID().uuidString)"
        store.defaults.set("hello", forKey: key)
        XCTAssertEqual(store.defaults.string(forKey: key), "hello")
        store.defaults.removeObject(forKey: key)
    }

    func testReadWriteRoundTripBool() {
        let store = SharedRoutingStore()
        let key = "test_roundtrip_bool_\(UUID().uuidString)"
        store.defaults.set(true, forKey: key)
        XCTAssertTrue(store.defaults.bool(forKey: key))
        store.defaults.removeObject(forKey: key)
    }

    func testReadWriteRoundTripData() {
        let store = SharedRoutingStore()
        let key = "test_roundtrip_data_\(UUID().uuidString)"
        let data = "test payload".data(using: .utf8)!
        store.defaults.set(data, forKey: key)
        XCTAssertEqual(store.defaults.data(forKey: key), data)
        store.defaults.removeObject(forKey: key)
    }

    func testReadWriteRoundTripArray() {
        let store = SharedRoutingStore()
        let key = "test_roundtrip_array_\(UUID().uuidString)"
        let array = ["utm_source", "fbclid", "gclid"]
        store.defaults.set(array, forKey: key)
        XCTAssertEqual(store.defaults.stringArray(forKey: key), array)
        store.defaults.removeObject(forKey: key)
    }

    func testMissingKeyReturnsNil() {
        let store = SharedRoutingStore()
        let key = "nonexistent_key_\(UUID().uuidString)"
        XCTAssertNil(store.defaults.string(forKey: key))
        XCTAssertNil(store.defaults.data(forKey: key))
    }

    func testIsUsingAppGroupFlagReported() {
        let store = SharedRoutingStore()
        // In test environment, the App Group may or may not be available
        // depending on code signing. Just verify the flag is set consistently.
        if UserDefaults(suiteName: SharedRoutingStore.suiteName) != nil {
            XCTAssertTrue(store.isUsingAppGroup)
        } else {
            XCTAssertFalse(store.isUsingAppGroup)
        }
    }
}
