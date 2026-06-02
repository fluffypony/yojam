import XCTest
@testable import Yojam
import YojamCore

final class RuleEngineTests: XCTestCase {
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
            sourceAppBundleId: "com.tinyspeck.slackmacgap")
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
            sourceAppBundleId: "com.tinyspeck.slackmacgap")
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
            sourceAppBundleId: "com.tinyspeck.slackmacgap")
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
