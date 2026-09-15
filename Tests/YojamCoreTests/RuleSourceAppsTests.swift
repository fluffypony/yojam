import XCTest
@testable import YojamCore

final class RuleSourceAppsTests: XCTestCase {
    private let workApps = [
        RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap", name: "Slack"),
        RuleSourceApp(bundleId: "com.apple.mail", name: "Mail"),
        RuleSourceApp(bundleId: "com.microsoft.teams2", name: "Microsoft Teams"),
        RuleSourceApp(bundleId: "com.apple.iCal", name: "Calendar"),
        RuleSourceApp(bundleId: "com.microsoft.Outlook", name: "Outlook"),
    ]

    private func rule(sourceApps: [RuleSourceApp]) -> Rule {
        Rule(name: "Work apps", matchType: .all, pattern: "",
             targetBundleId: "com.google.Chrome", targetAppName: "Chrome",
             sourceApps: sourceApps)
    }

    func testAnyOfFiveSourceAppsMatchesWhileOtherAndUnknownSourcesDoNot() {
        let rule = rule(sourceApps: workApps)
        let url = URL(string: "https://example.com")!
        for app in workApps {
            XCTAssertTrue(RuleMatcher.evaluate(url: url, against: rule, sourceApp: app.bundleId).matched)
        }
        for source in [nil, "com.apple.Safari", "com.apple.mail.helper"] {
            XCTAssertFalse(RuleMatcher.evaluate(url: url, against: rule, sourceApp: source).matched)
        }
    }

    func testEmptySourceListAllowsAnyOrUnknownSource() {
        let rule = rule(sourceApps: [])
        for source in [nil, "com.apple.Safari"] {
            XCTAssertTrue(RuleMatcher.evaluate(
                url: URL(string: "https://example.com")!, against: rule, sourceApp: source).matched)
        }
    }

    func testSourceListStillRequiresURLAndMachineMatch() {
        var rule = rule(sourceApps: workApps)
        rule.matchType = .domain
        rule.pattern = "work.example"
        rule.machineScopeIdentifiers = ["work-mac"]
        for app in workApps {
            XCTAssertTrue(RuleMatcher.evaluate(
                url: URL(string: "https://work.example")!, against: rule,
                sourceApp: app.bundleId, machineIdentifier: "work-mac").matched)
            XCTAssertFalse(RuleMatcher.evaluate(
                url: URL(string: "https://personal.example")!, against: rule,
                sourceApp: app.bundleId, machineIdentifier: "work-mac").matched)
            XCTAssertFalse(RuleMatcher.evaluate(
                url: URL(string: "https://work.example")!, against: rule,
                sourceApp: app.bundleId, machineIdentifier: "personal-mac").matched)
        }
    }

    func testSourceListSupportsSyntheticSources() {
        let rule = rule(sourceApps: [
            RuleSourceApp(bundleId: SourceAppSentinel.handoff),
            RuleSourceApp(bundleId: SourceAppSentinel.shareExtension),
        ])
        XCTAssertTrue(RuleMatcher.evaluate(
            url: URL(string: "https://example.com")!, against: rule,
            sourceApp: SourceAppSentinel.shareExtension).matched)
    }

    func testSourceAppsRoundTripWithNamesAndTargetProfile() throws {
        var rule = rule(sourceApps: workApps)
        rule.targetBrowserEntryId = UUID()
        rule.ruleProfileId = "Profile 3"
        let decoded = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule)
    }

    func testLegacySingleSourceMigratesWithItsName() throws {
        let data = Data("""
        {"id":"11111111-1111-1111-1111-111111111111",
         "sourceAppBundleId":"com.apple.mail","sourceAppName":"Mail"}
        """.utf8)
        let decoded = try JSONDecoder().decode(Rule.self, from: data)
        XCTAssertEqual(decoded.sourceApps, [RuleSourceApp(bundleId: "com.apple.mail", name: "Mail")])
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNotNil(encoded["sourceApps"])
    }

    func testMissingAndNullLegacySourceAllowAllSources() throws {
        for field in ["", ",\"sourceAppBundleId\":null"] {
            let data = Data("{\"id\":\"11111111-1111-1111-1111-111111111111\"\(field)}".utf8)
            XCTAssertTrue(try JSONDecoder().decode(Rule.self, from: data).sourceApps.isEmpty)
        }
    }

    func testExplicitEmptyListOverridesStaleLegacySource() throws {
        let data = Data("""
        {"id":"11111111-1111-1111-1111-111111111111",
         "sourceApps":[],"sourceAppBundleId":"com.apple.mail"}
        """.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Rule.self, from: data).sourceApps.isEmpty)
    }

    func testLegacyReaderCannotBroadenMultiSourceRule() throws {
        let original = rule(sourceApps: workApps)
        let legacy = try JSONDecoder().decode(LegacyRule.self, from: JSONEncoder().encode(original))
        for source in workApps.map(\.bundleId) + ["com.apple.Safari"] {
            XCTAssertNotEqual(legacy.sourceAppBundleId, source)
        }
        XCTAssertNotNil(legacy.sourceAppBundleId)
        let echoed = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(echoed.sourceApps, [RuleSourceApp.legacyMultiAppGuard])
        XCTAssertFalse(RuleMatcher.evaluate(
            url: URL(string: "https://example.com")!, against: echoed).matched)
    }

    func testLegacyReaderKeepsSingleSourceUsable() throws {
        let original = rule(sourceApps: [workApps[0]])
        let legacy = try JSONDecoder().decode(LegacyRule.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(legacy.sourceAppBundleId, workApps[0].bundleId)
        let echoed = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(echoed.sourceApps, original.sourceApps)
    }

    // The pre-1.3 decoder ignores unknown keys; its encoder only writes fields
    // declared in the old model. Keep that projection explicit in this test.
    private struct LegacyRule: Codable {
        let id: UUID
        let name: String
        let matchType: MatchType
        let pattern: String
        let targetBundleId: String
        let targetAppName: String
        let sourceAppBundleId: String?
        let sourceAppName: String?
    }
}
