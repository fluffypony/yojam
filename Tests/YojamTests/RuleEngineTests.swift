import XCTest
@testable import Yojam
import YojamCore

final class RuleEngineTests: XCTestCase {
    @MainActor
    func testUnavailableBuiltInRuleKeepsPortableEnabledState() {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }
        let rule = Rule(
            name: "Unavailable",
            enabled: true,
            matchType: .all,
            pattern: "",
            targetBundleId: "com.example.definitely-not-installed.yojam-test",
            targetAppName: "Unavailable",
            isBuiltIn: true)
        store.saveRules([rule])

        let engine = RuleEngine(settingsStore: store)

        XCTAssertTrue(engine.rules.first(where: { $0.id == rule.id })?.enabled == true)
    }

    @MainActor
    func testRuleEngineMigratesOnlyUnstampedBuiltInDisable() {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }
        let userModifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let availabilityDerived = Rule(
            name: "Derived",
            enabled: false,
            matchType: .all,
            pattern: "",
            targetBundleId: "com.example.derived",
            targetAppName: "Derived",
            isBuiltIn: true)
        let userDisabled = Rule(
            name: "User disabled",
            enabled: false,
            matchType: .all,
            pattern: "",
            targetBundleId: "com.example.user-disabled",
            targetAppName: "User disabled",
            isBuiltIn: true,
            lastModifiedAt: userModifiedAt)
        store.saveRules([availabilityDerived, userDisabled])

        let engine = RuleEngine(settingsStore: store)

        XCTAssertTrue(engine.rules.first {
            $0.id == availabilityDerived.id
        }?.enabled == true)
        let preserved = engine.rules.first { $0.id == userDisabled.id }
        XCTAssertFalse(preserved?.enabled == true)
        XCTAssertEqual(preserved?.lastModifiedAt, userModifiedAt)
    }

    @MainActor
    func testResetBuiltInPreservesDisabledStateAcrossReload() throws {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }
        store.saveRules(BuiltInRules.all)
        let engine = RuleEngine(settingsStore: store)
        let id = BuiltInRules.all[0].id

        engine.toggleRule(id)
        engine.resetBuiltInRule(id)
        engine.reloadRules()

        let reset = try XCTUnwrap(engine.rules.first { $0.id == id })
        XCTAssertFalse(reset.enabled)
        XCTAssertNotNil(reset.lastModifiedAt)
    }

    @MainActor
    func testDomainMatch() {
        let rule = Rule(
            name: "Test", matchType: .domain, pattern: "example.com",
            targetBundleId: "com.test", targetAppName: "Test")
        let engine = RuleEngine(settingsStore: SettingsStore())
        XCTAssertTrue(engine.matches(
            url: URL(string: "https://example.com/path")!, rule: rule))
        XCTAssertFalse(engine.matches(
            url: URL(string: "https://sub.example.com")!, rule: rule))
    }

    @MainActor
    func testDomainSuffixMatch() {
        let rule = Rule(
            name: "Test", matchType: .domainSuffix, pattern: "example.com",
            targetBundleId: "com.test", targetAppName: "Test")
        let engine = RuleEngine(settingsStore: SettingsStore())
        XCTAssertTrue(engine.matches(
            url: URL(string: "https://example.com/path")!, rule: rule))
        XCTAssertTrue(engine.matches(
            url: URL(string: "https://sub.example.com")!, rule: rule))
        XCTAssertFalse(engine.matches(
            url: URL(string: "https://notexample.com")!, rule: rule))
    }

    @MainActor
    func testURLContainsMatch() {
        let rule = Rule(
            name: "Test", matchType: .urlContains, pattern: "zoom.us/j/",
            targetBundleId: "com.test", targetAppName: "Test")
        let engine = RuleEngine(settingsStore: SettingsStore())
        XCTAssertTrue(engine.matches(
            url: URL(string: "https://zoom.us/j/123")!, rule: rule))
        XCTAssertFalse(engine.matches(
            url: URL(string: "https://zoom.us/other")!, rule: rule))
    }

    @MainActor
    func testRegexMatch() {
        let rule = Rule(
            name: "Test", matchType: .regex,
            pattern: #"^https://github\.com/[^/]+/[^/]+/pull/"#,
            targetBundleId: "com.test", targetAppName: "Test")
        let engine = RuleEngine(settingsStore: SettingsStore())
        XCTAssertTrue(engine.matches(
            url: URL(string: "https://github.com/user/repo/pull/42")!,
            rule: rule))
        XCTAssertFalse(engine.matches(
            url: URL(string: "https://github.com/user/repo/issues/42")!,
            rule: rule))
    }

    @MainActor
    func testSourceAppFiltering() {
        let rule = Rule(
            name: "From Slack", matchType: .domainSuffix,
            pattern: "github.com",
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome",
            sourceApps: [RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap")])
        let engine = RuleEngine(settingsStore: SettingsStore())
        engine.rules = [rule]
        XCTAssertNil(engine.evaluate(
            URL(string: "https://github.com/repo")!,
            sourceAppBundleId: "com.apple.mail"))
    }

    @MainActor
    func testSourceAppFilteringMatchesWhenSourceAndURLMatch() {
        let rule = Rule(
            name: "From Slack", matchType: .all,
            pattern: "",
            targetBundleId: "/bin/echo",
            targetAppName: "Echo",
            sourceApps: [RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap")])
        let engine = RuleEngine(settingsStore: SettingsStore())
        engine.rules = [rule]
        XCTAssertEqual(engine.evaluate(
            URL(string: "https://github.com/repo")!,
            sourceAppBundleId: "com.tinyspeck.slackmacgap")?.id, rule.id)
    }

    @MainActor
    func testPriorityOrderingCanPlaceBuiltInBeforeUserRule() {
        let engine = RuleEngine(settingsStore: SettingsStore())
        let userRule = Rule(
            name: "User", matchType: .urlContains, pattern: "zoom.us/j/",
            targetBundleId: "com.apple.Safari", targetAppName: "Safari",
            isBuiltIn: false, priority: 50)
        let builtIn = Rule(
            name: "BuiltIn", matchType: .urlContains, pattern: "zoom.us/j/",
            targetBundleId: "us.zoom.xos", targetAppName: "Zoom",
            isBuiltIn: true, priority: 10)
        engine.rules = [builtIn, userRule]
        let sorted = RuleOrdering.enabled(engine.rules)
        XCTAssertEqual(sorted.first?.name, "BuiltIn")
    }

    @MainActor
    func testPriorityOrdering() {
        let engine = RuleEngine(settingsStore: SettingsStore())
        let low = Rule(
            name: "Low", matchType: .domainSuffix, pattern: "example.com",
            targetBundleId: "com.a", targetAppName: "A", priority: 10)
        let high = Rule(
            name: "High", matchType: .domainSuffix, pattern: "example.com",
            targetBundleId: "com.b", targetAppName: "B", priority: 100)
        engine.rules = [high, low]
        let sorted = RuleOrdering.enabled(engine.rules)
        XCTAssertEqual(sorted.first?.name, "Low")
    }

    @MainActor
    func testMoveRuleReindexesPrioritiesAcrossBuiltInAndUserRules() {
        let engine = RuleEngine(settingsStore: SettingsStore())
        let slack = Rule(
            name: "All Slack", matchType: .all, pattern: "",
            targetBundleId: "org.mozilla.firefox", targetAppName: "Firefox",
            isBuiltIn: false, priority: 10,
            sourceApps: [RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap")])
        let linear = Rule(
            name: "Linear", matchType: .domainSuffix, pattern: "linear.app",
            targetBundleId: "com.linear", targetAppName: "Linear",
            isBuiltIn: true, priority: 20)

        engine.rules = [slack, linear]
        engine.moveRule(draggedId: linear.id, to: slack.id)

        let ordered = engine.orderedRules
        XCTAssertEqual(ordered.map(\.id), [linear.id, slack.id])
        XCTAssertLessThan(ordered[0].priority, ordered[1].priority)
    }

    @MainActor
    func testImportedRulesRunBeforeBuiltInsAndKeepSourceOrder() {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }
        let existing = Rule(
            name: "Existing", matchType: .domain, pattern: "existing.invalid",
            targetBundleId: "com.existing", targetAppName: "Existing",
            priority: 10)
        let builtIn = Rule(
            name: "Built-in", matchType: .all, pattern: "",
            targetBundleId: "/bin/echo", targetAppName: "Built-in",
            isBuiltIn: true, priority: 20)
        let firstImport = Rule(
            name: "First import", matchType: .all, pattern: "",
            targetBundleId: "/bin/echo", targetAppName: "First",
            priority: 500)
        let secondImport = Rule(
            name: "Second import", matchType: .all, pattern: "",
            targetBundleId: "/bin/echo", targetAppName: "Second",
            priority: 100)
        let engine = RuleEngine(settingsStore: store)
        engine.rules = [builtIn, existing]

        engine.addImportedRules([firstImport, secondImport])

        XCTAssertEqual(
            engine.orderedRules.map(\.id),
            [existing.id, firstImport.id, secondImport.id, builtIn.id])
        XCTAssertEqual(engine.orderedRules.map(\.priority), [10, 20, 30, 40])
        XCTAssertEqual(
            engine.evaluate(URL(string: "https://example.com")!)?.id,
            firstImport.id)
    }

    @MainActor
    func testDuplicateRulePreservesURLNormalizationAndSourceApps() throws {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }
        let original = Rule(
            name: "Imported Finicky route",
            matchType: .regex,
            pattern: #"^https://example\.com/$"#,
            urlNormalization: .whatwg,
            targetBundleId: "com.apple.Safari",
            targetAppName: "Safari",
            sourceApps: [RuleSourceApp(bundleId: "com.apple.mail", name: "Mail"),
                         RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")],
            metadata: ["importedFrom": "finicky"]
        )
        let engine = RuleEngine(settingsStore: store)
        engine.rules = [original]

        engine.duplicateRule(original.id)

        let copy = try XCTUnwrap(engine.rules.first { $0.id != original.id })
        XCTAssertEqual(copy.urlNormalization, .whatwg)
        XCTAssertEqual(copy.sourceApps, original.sourceApps)
        XCTAssertEqual(copy.metadata, original.metadata)
    }

    @MainActor
    func testChangingImportedFinickyMatchMakesRuleUserScoped() throws {
        let store = SettingsStore()
        let originalRules = store.loadRules()
        defer { store.saveRules(originalRules) }
        let original = Rule(
            name: "Imported Finicky route",
            matchType: .regex,
            pattern: #"^https://example\.com/$"#,
            urlNormalization: .whatwg,
            targetBundleId: "com.apple.Safari",
            targetAppName: "Safari",
            metadata: [
                "importedFrom": "finicky",
                "finickyWebOnly": "true",
            ])
        let engine = RuleEngine(settingsStore: store)
        engine.rules = [original]
        var edited = original
        edited.pattern = #"^mailto:.*$"#

        engine.updateRule(edited)

        let saved = try XCTUnwrap(engine.rules.first)
        XCTAssertEqual(saved.metadata?["importedFrom"], "finicky")
        XCTAssertNil(saved.metadata?["finickyWebOnly"])
    }

    @MainActor
    func testBuiltInNotionRulesCoverBothHosts() {
        let notionRules = BuiltInRules.all.filter {
            $0.targetBundleId == "notion.id"
        }
        let notionSO = URL(string: "https://www.notion.so/team/page")!
        let appNotion = URL(string: "https://app.notion.com/workspace/page")!

        XCTAssertTrue(notionRules.contains {
            RuleMatcher.evaluate(url: notionSO, against: $0).matched
        })
        XCTAssertTrue(notionRules.contains {
            RuleMatcher.evaluate(url: appNotion, against: $0).matched
        })
    }
}
