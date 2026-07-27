import XCTest
@testable import Yojam
import YojamCore

final class RoutingSuggestionEngineTests: XCTestCase {
    @MainActor
    func testNoSuggestionBelowThreshold() {
        let engine = RoutingSuggestionEngine()
        engine.clearAll()
        engine.recordChoice(domain: "example.com", entryId: "browser-a")
        engine.recordChoice(domain: "example.com", entryId: "browser-a")
        // Below minimum confidence of 3
        XCTAssertNil(engine.suggestion(for: "example.com"))
    }

    @MainActor
    func testSuggestionAfterThreshold() {
        let engine = RoutingSuggestionEngine()
        engine.clearAll()
        for _ in 0..<4 {
            engine.recordChoice(domain: "test.com", entryId: "browser-x")
        }
        XCTAssertEqual(engine.suggestion(for: "test.com"), "browser-x")
    }

    @MainActor
    func testNoSuggestionWhenSplit() {
        let engine = RoutingSuggestionEngine()
        engine.clearAll()
        // 2 choices for A, 2 for B — total 4 but neither > 70%
        engine.recordChoice(domain: "split.com", entryId: "a")
        engine.recordChoice(domain: "split.com", entryId: "a")
        engine.recordChoice(domain: "split.com", entryId: "b")
        engine.recordChoice(domain: "split.com", entryId: "b")
        XCTAssertNil(engine.suggestion(for: "split.com"))
    }

    @MainActor
    func testClearAll() {
        let engine = RoutingSuggestionEngine()
        for _ in 0..<5 {
            engine.recordChoice(domain: "clear.com", entryId: "x")
        }
        XCTAssertNotNil(engine.suggestion(for: "clear.com"))
        engine.clearAll()
        XCTAssertNil(engine.suggestion(for: "clear.com"))
    }

    @MainActor
    func testUnknownDomainReturnsNil() {
        let engine = RoutingSuggestionEngine()
        XCTAssertNil(engine.suggestion(for: "never-seen.com"))
    }

    @MainActor
    func testPersistedPreferenceEmitsConfigMirrorChangeOnce() throws {
        let store = SettingsStore()
        let defaults = store.sharedStore.defaults
        let key = SharedRoutingStore.Keys.learnedDomainPreferences
        let originalData = defaults.data(forKey: key)
        let domain = "mirror-event-\(UUID().uuidString).invalid"
        var notificationCount = 0
        let cancellable = store.configMirrorDataDidChange.sink {
            notificationCount += 1
        }
        defer {
            cancellable.cancel()
            if let originalData {
                defaults.set(originalData, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        let engine = RoutingSuggestionEngine {
            store.configMirrorDataDidChange.send()
        }

        engine.recordChoice(domain: domain, entryId: "browser-a")
        engine.removePreference(for: "missing-\(UUID().uuidString).invalid")
        engine.removePreference(for: "missing-\(UUID().uuidString).invalid")

        XCTAssertEqual(notificationCount, 1)
        let exported = try JSONDecoder().decode(
            SettingsExport.self, from: store.exportConfigMirrorJSON())
        XCTAssertEqual(exported.learnedDomainPreferences[domain], ["browser-a": 1])
    }

    @MainActor
    func testReloadCancelsPendingSaveAndKeepsImportedPreferences() async throws {
        let defaults = SharedRoutingStore().defaults
        let key = SharedRoutingStore.Keys.learnedDomainPreferences
        let originalData = defaults.data(forKey: key)
        defer {
            if let originalData {
                defaults.set(originalData, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: key)
        let engine = RoutingSuggestionEngine(saveDelay: 0.05)
        engine.recordChoice(domain: "pending.invalid", entryId: "browser-a")

        let imported = ["imported.invalid": ["browser-b": 3]]
        let importedData = try JSONEncoder().encode(imported)
        defaults.set(importedData, forKey: key)
        engine.reloadFromDefaults()

        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(defaults.data(forKey: key), importedData)
        XCTAssertEqual(engine.suggestion(for: "imported.invalid"), "browser-b")
        XCTAssertNil(engine.suggestion(for: "pending.invalid"))
    }
}
