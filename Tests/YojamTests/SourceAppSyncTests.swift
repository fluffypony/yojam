import XCTest
@testable import Yojam
import YojamCore

final class SourceAppSyncTests: XCTestCase {
    private func workRule() -> Rule {
        Rule(name: "Work apps", matchType: .all, pattern: "",
             targetBundleId: "com.google.Chrome", targetAppName: "Chrome",
             sourceApps: [RuleSourceApp(bundleId: "com.apple.mail", name: "Mail"),
                          RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")],
             lastModifiedAt: Date(timeIntervalSince1970: 10))
    }

    private func echoFromLegacyClient(_ rule: Rule) throws -> Rule {
        var legacy = try JSONDecoder().decode(LegacyRule.self, from: JSONEncoder().encode(rule))
        legacy.name = "Edited on an older Mac"
        legacy.lastModifiedAt = Date(timeIntervalSince1970: 20)
        return try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(legacy))
    }

    func testSeparateSourceKeyRestoresListAfterOldClientWritesRule() throws {
        let original = workRule()
        let backup = try JSONDecoder().decode(
            ICloudSourceAppCompatibility.self,
            from: JSONEncoder().encode(ICloudSourceAppCompatibility(rules: [original])))
        let echoed = try echoFromLegacyClient(original)
        XCTAssertTrue(ICloudSourceAppCompatibility.hasLegacyGuard(echoed))

        let restored = backup.restoring(echoed, local: nil)
        XCTAssertEqual(restored.sourceApps, original.sourceApps)
        XCTAssertEqual(restored.name, "Edited on an older Mac")
        XCTAssertEqual(restored.lastModifiedAt, echoed.lastModifiedAt)
        let merged = try XCTUnwrap(SyncConflictResolver.mergeRules(
            local: [original], remote: [restored]).first)
        XCTAssertEqual(merged.sourceApps, original.sourceApps)
    }

    func testLocalListSurvivesWhenSourceKeyHasNotArrived() throws {
        let original = workRule()
        let backup = ICloudSourceAppCompatibility(rules: [])
        let restored = backup.restoring(try echoFromLegacyClient(original), local: original)
        XCTAssertEqual(restored.sourceApps, original.sourceApps)
    }

    func testMissingSourceKeyAndLocalRuleKeepsGuard() throws {
        let echoed = try echoFromLegacyClient(workRule())
        let restored = ICloudSourceAppCompatibility(rules: []).restoring(echoed, local: nil)
        XCTAssertTrue(ICloudSourceAppCompatibility.hasLegacyGuard(restored))
        XCTAssertFalse(RuleMatcher.evaluate(
            url: URL(string: "https://example.com")!, against: restored,
            sourceApp: "com.apple.mail").matched)
    }

    func testNewerLocalSourceEditWinsOverOlderBackup() throws {
        let original = workRule()
        let backup = ICloudSourceAppCompatibility(rules: [original])
        var local = original
        local.sourceApps = []
        local.lastModifiedAt = Date(timeIntervalSince1970: 15)
        let restored = backup.restoring(try echoFromLegacyClient(original), local: local)
        XCTAssertTrue(restored.sourceApps.isEmpty)
    }

    func testActualSourceEditDoesNotRestoreStaleList() {
        let original = workRule()
        let backup = ICloudSourceAppCompatibility(rules: [original])
        for apps in [[], [RuleSourceApp(bundleId: "com.apple.iCal")]] {
            var edited = original
            edited.sourceApps = apps
            XCTAssertEqual(backup.restoring(edited, local: original).sourceApps, apps)
        }
    }

    func testUnresolvedGuardCannotOverwriteStoredSourceList() throws {
        let original = workRule()
        let echoed = try echoFromLegacyClient(original)
        let backup = ICloudSourceAppCompatibility(rules: [original])
        let pushed = ICloudSourceAppCompatibility(rules: [echoed], previous: backup)
        XCTAssertEqual(pushed.restoring(echoed, local: nil).sourceApps, original.sourceApps)
    }

    private struct LegacyRule: Codable {
        let id: UUID
        var name: String
        let matchType: MatchType
        let pattern: String
        let targetBundleId: String
        let targetAppName: String
        let sourceAppBundleId: String?
        let sourceAppName: String?
        var lastModifiedAt: Date?
    }
}
