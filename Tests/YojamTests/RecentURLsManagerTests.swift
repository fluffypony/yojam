import XCTest
@testable import Yojam
import YojamCore

final class RecentURLsManagerTests: XCTestCase {
    @MainActor
    func testPersistenceRestoresExactURLsInMostRecentFirstOrder() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = URL(string: "https://example.com/projects/first?tab=activity#latest")!
        let second = URL(string: "https://example.com/projects/second")!

        let manager = RecentURLsManager(sharedDefaults: defaults)
        manager.add(first, retention: .forever)
        manager.add(second, retention: .forever)

        let restored = RecentURLsManager(sharedDefaults: defaults)
        XCTAssertEqual(restored.recentURLs, [second, first])
        XCTAssertEqual(restored.recentURLs[1].absoluteString, first.absoluteString)
    }

    @MainActor
    func testAddingExistingURLMovesItToFrontWithoutDuplicatingIt() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = URL(string: "https://example.com/first")!
        let second = URL(string: "https://example.com/second")!

        let manager = RecentURLsManager(sharedDefaults: defaults)
        manager.add(first, retention: .forever)
        manager.add(second, retention: .forever)
        manager.add(first, retention: .forever)

        XCTAssertEqual(manager.recentURLs, [first, second])
    }

    @MainActor
    func testHistoryKeepsOnlyTenMostRecentURLsInOrder() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let urls = (0..<12).map { URL(string: "https://example.com/link/\($0)")! }

        let manager = RecentURLsManager(sharedDefaults: defaults)
        for url in urls {
            manager.add(url, retention: .forever)
        }

        XCTAssertEqual(manager.recentURLs, Array(urls.reversed().prefix(10)))
    }

    @MainActor
    func testClearRemovesInMemoryAndPersistedHistory() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let url = URL(string: "https://example.com/path")!
        let manager = RecentURLsManager(sharedDefaults: defaults)
        manager.add(url, retention: .forever)

        manager.clear()

        XCTAssertTrue(manager.recentURLs.isEmpty)
        XCTAssertEqual(
            defaults.stringArray(forKey: SharedRoutingStore.Keys.recentURLs),
            [])
        XCTAssertEqual(
            defaults.dictionary(forKey: SharedRoutingStore.Keys.recentURLTimestamps)?.count,
            0)
        XCTAssertTrue(RecentURLsManager(sharedDefaults: defaults).recentURLs.isEmpty)
    }

    @MainActor
    func testMenuEntryShowsPathAndRetainsExactStoredURL() {
        let url = URL(string: "https://example.com:8443/projects/alpha?tab=activity#latest")!

        let entry = StatusBarController.linkHistoryMenuEntry(for: url)

        XCTAssertEqual(entry.title, "example.com:8443/projects/alpha")
        XCTAssertEqual(entry.url, url)
        XCTAssertEqual(entry.url.absoluteString, url.absoluteString)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "RecentURLsManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
