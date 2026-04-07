import XCTest
@testable import Yojam
import YojamCore

final class SyncConflictResolverTests: XCTestCase {
    func testRemoteAdditionsAppear() {
        let local = [
            BrowserEntry(id: UUID(), bundleIdentifier: "com.local", displayName: "Local")
        ]
        let remoteId = UUID()
        let remote = [
            BrowserEntry(id: remoteId, bundleIdentifier: "com.remote", displayName: "Remote")
        ]
        let merged = SyncConflictResolver.mergeBrowserLists(local: local, remote: remote)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.id == remoteId }))
    }

    func testNewerTimestampWins() {
        let id = UUID()
        let old = BrowserEntry(
            id: id, bundleIdentifier: "com.test", displayName: "Old",
            lastModifiedAt: Date(timeIntervalSince1970: 1000))
        let new = BrowserEntry(
            id: id, bundleIdentifier: "com.test", displayName: "New",
            lastModifiedAt: Date(timeIntervalSince1970: 2000))
        let merged = SyncConflictResolver.mergeBrowserLists(local: [old], remote: [new])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].displayName, "New")
    }

    func testDisjointListsMerge() {
        let a = BrowserEntry(bundleIdentifier: "com.a", displayName: "A")
        let b = BrowserEntry(bundleIdentifier: "com.b", displayName: "B")
        let merged = SyncConflictResolver.mergeBrowserLists(local: [a], remote: [b])
        XCTAssertEqual(merged.count, 2)
    }

    func testRewriteRuleMerge() {
        let local = [URLRewriteRule(name: "Local", matchPattern: "a", replacement: "b", scope: .global)]
        let remote = [URLRewriteRule(name: "Remote", matchPattern: "c", replacement: "d", scope: .global)]
        let merged = SyncConflictResolver.mergeRewriteRules(local: local, remote: remote)
        XCTAssertEqual(merged.count, 2)
    }

    func testRewriteRuleMergeLocalWinsOnConflict() {
        let id = UUID()
        let local = [URLRewriteRule(id: id, name: "Local", matchPattern: "a", replacement: "b", scope: .global)]
        let remote = [URLRewriteRule(id: id, name: "Remote", matchPattern: "c", replacement: "d", scope: .global)]
        let merged = SyncConflictResolver.mergeRewriteRules(local: local, remote: remote)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Local")
    }

    func testRuleMergeNewerWins() {
        let id = UUID()
        let old = Rule(id: id, name: "Old", matchType: .domain, pattern: "a.com",
                       targetBundleId: "com.test", targetAppName: "Test",
                       lastModifiedAt: Date(timeIntervalSince1970: 1000))
        let new = Rule(id: id, name: "New", matchType: .domain, pattern: "b.com",
                       targetBundleId: "com.test", targetAppName: "Test",
                       lastModifiedAt: Date(timeIntervalSince1970: 2000))
        let merged = SyncConflictResolver.mergeRules(local: [old], remote: [new])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "New")
    }
}
