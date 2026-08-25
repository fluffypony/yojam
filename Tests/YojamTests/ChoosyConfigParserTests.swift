import Foundation
import XCTest
@testable import Yojam
import YojamCore

final class ChoosyConfigParserTests: XCTestCase {
    func testParsesRealChoosy252ShapeAndWarnsForPromptBehaviours() throws {
        let result = ChoosyConfigParser.parse(
            data: try fixture("choosy-2.5.2-live.plist"),
            applicationResolver: resolveApplication)

        XCTAssertEqual(result.rules.count, 1)
        let rule = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(rule.name, "Audit GitHub rule")
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.targetBundleId, "com.google.Chrome")
        XCTAssertEqual(rule.targetAppName, "Google Chrome")
        XCTAssertEqual(rule.matchType, .regex)
        XCTAssertEqual(rule.metadata?["importedFrom"], "choosy")
        XCTAssertEqual(rule.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(matches(rule, "https://github.com/fluffypony/yojam"))
        XCTAssertFalse(matches(rule, "https://example.com/GITHUB.COM"))
        XCTAssertEqual(result.warnings.count, 3)
        XCTAssertTrue(result.warnings.contains { $0.contains("behaviour 4") })
        XCTAssertTrue(result.warnings.contains { $0.contains("behaviour 3") })
        XCTAssertTrue(result.warnings.contains { $0.contains("follows a skipped rule") })
    }

    func testParsesEverySupportedURLPredicateWithoutWeakeningCase() throws {
        let result = ChoosyConfigParser.parse(
            data: try fixture("choosy-2.5.2-predicates.plist"),
            applicationResolver: resolveApplication)

        XCTAssertEqual(result.rules.count, 11)
        XCTAssertEqual(result.rules.map(\.name), [
            "All URLs",
            "Exact URL",
            "Not exact URL",
            "Contains case sensitive",
            "Begins with",
            "Ends with",
            "Like whole URL",
            "Matches case sensitive",
            "Source and URL",
            "Split OR",
            "Split OR",
        ])

        let all = try rule(named: "All URLs", in: result)
        XCTAssertEqual(all.matchType, .all)
        XCTAssertTrue(matches(all, "https://anything.example/path"))

        let exact = try rule(named: "Exact URL", in: result)
        XCTAssertFalse(exact.enabled)
        XCTAssertEqual(exact.targetBundleId, "com.google.Chrome")
        XCTAssertTrue(matches(exact, "https://example.com/Exact"))
        XCTAssertFalse(matches(exact, "https://example.com/exact"))
        XCTAssertFalse(matches(exact, "https://example.com/Exact/more"))

        let notExact = try rule(named: "Not exact URL", in: result)
        XCTAssertFalse(matches(notExact, "https://example.com/private"))
        XCTAssertTrue(matches(notExact, "https://example.com/private/more"))
        XCTAssertTrue(matches(notExact, "https://example.com/Private"))

        let contains = try rule(named: "Contains case sensitive", in: result)
        XCTAssertTrue(matches(contains, "https://example.com/CasePath/item"))
        XCTAssertFalse(matches(contains, "https://example.com/casepath/item"))

        let begins = try rule(named: "Begins with", in: result)
        XCTAssertTrue(matches(begins, "https://start.example/path"))
        XCTAssertFalse(matches(begins, "http://start.example/path"))

        let ends = try rule(named: "Ends with", in: result)
        XCTAssertTrue(matches(ends, "https://example.com/path/finish"))
        XCTAssertFalse(matches(ends, "https://example.com/path/finish?query=1"))

        let like = try rule(named: "Like whole URL", in: result)
        XCTAssertTrue(matches(like, "https://sub.example.com/path"))
        XCTAssertFalse(matches(like, "https://sub.example.com/"))
        XCTAssertFalse(matches(like, "http://sub.example.com/path"))

        let regex = try rule(named: "Matches case sensitive", in: result)
        XCTAssertTrue(regex.pattern.contains("(?-i:"))
        XCTAssertTrue(matches(regex, "https://example.com/Case42"))
        XCTAssertFalse(matches(regex, "https://example.com/case42"))
        XCTAssertFalse(matches(regex, "https://example.com/Case42/more"))
    }

    func testParsesSerializedChromiumProfileTargets() throws {
        let result = ChoosyConfigParser.parse(
            data: try fixture("choosy-2.5.2-profiles.plist"),
            applicationResolver: resolveApplication)

        XCTAssertTrue(result.warnings.isEmpty, result.warnings.joined(separator: "\n"))
        XCTAssertEqual(result.rules.map(\.targetBundleId), [
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
        ])
        XCTAssertEqual(result.rules.map(\.ruleProfileId), [
            "Profile 7",
            "Profile 3",
            "Default",
            "Profile 2",
        ])
        XCTAssertEqual(result.rules.map(\.ruleOpenInPrivateWindow), [
            false, false, false, false,
        ])
        XCTAssertEqual(result.rules.map(\.ruleOpenAsNewInstance), [
            true, true, true, true,
        ])
    }

    func testSourceEqualityAndURLConditionMapToOneExactRule() throws {
        let result = ChoosyConfigParser.parse(
            data: try fixture("choosy-2.5.2-predicates.plist"),
            applicationResolver: resolveApplication)
        let rule = try rule(named: "Source and URL", in: result)

        XCTAssertEqual(rule.sourceAppBundleId, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(rule.sourceAppName, "Slack")
        XCTAssertTrue(matches(
            rule,
            "https://example.com/github.com",
            sourceApp: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(matches(
            rule,
            "https://example.com/GITHUB.COM",
            sourceApp: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(matches(
            rule,
            "https://example.com/github.com",
            sourceApp: "com.apple.Mail"))
        XCTAssertTrue(result.warnings.contains { warning in
            warning.contains("app copies with the same bundle ID")
        })
    }

    func testORCreatesAdjacentRulesInPredicateOrder() throws {
        let result = ChoosyConfigParser.parse(
            data: try fixture("choosy-2.5.2-predicates.plist"),
            applicationResolver: resolveApplication)
        let alternatives = result.rules.filter { $0.name == "Split OR" }

        XCTAssertEqual(alternatives.count, 2)
        XCTAssertTrue(matches(alternatives[0], "https://one.example/path"))
        XCTAssertFalse(matches(alternatives[0], "https://two.example/path"))
        XCTAssertTrue(matches(alternatives[1], "https://two.example/path"))
        XCTAssertFalse(matches(alternatives[1], "https://one.example/path"))
    }

    func testRejectsDynamicNegatedUnsupportedAndInvalidRules() throws {
        let result = ChoosyConfigParser.parse(
            data: try fixture("choosy-2.5.2-unsupported.plist"),
            applicationResolver: resolveApplication)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertEqual(result.warnings.count, 6)
        XCTAssertTrue(result.warnings.contains { $0.contains("Dynamic state") })
        XCTAssertTrue(result.warnings.contains { $0.contains("NOT compounds") })
        XCTAssertTrue(result.warnings.contains { $0.contains("source-app comparisons") })
        XCTAssertTrue(result.warnings.contains { $0.contains("behaviour 3") })
        XCTAssertTrue(result.warnings.contains { $0.contains("one valid ChoosyBrowser") })
        XCTAssertTrue(result.warnings.contains { $0.contains("option [d]") })
    }

    func testWarnsForEveryNonFixedBehaviourCode() throws {
        let behaviourCodes = Array(0...5) + Array(7...9)
        let entries: [[String: Any]] = behaviourCodes.map { behaviour in
            [
                "title": "Behaviour \(behaviour)",
                "predicate": "TRUEPREDICATE",
                "enabled": true,
                "behaviour": behaviour,
                "behaviourArgument": "",
            ]
        }
        let result = ChoosyConfigParser.parse(
            data: try propertyListData(entries),
            applicationResolver: resolveApplication)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertEqual(result.warnings.count, behaviourCodes.count)
        for behaviour in behaviourCodes {
            XCTAssertTrue(result.warnings.contains { $0.contains("behaviour \(behaviour)") })
        }
    }

    func testANDPreservesEveryURLCondition() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([behaviour(
                title: "Both",
                predicate: "URL BEGINSWITH \"https://example.com/\" AND URL ENDSWITH \"/done\"")]),
            applicationResolver: resolveApplication)
        let rule = try XCTUnwrap(result.rules.first)

        XCTAssertTrue(matches(rule, "https://example.com/path/done"))
        XCTAssertFalse(matches(rule, "https://other.example/path/done"))
        XCTAssertFalse(matches(rule, "https://example.com/path/not-done-here"))
    }

    func testUnsupportedORSkipsTheWholeRule() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([behaviour(
                title: "Mixed OR",
                predicate: "URL CONTAINS \"safe.example\" OR runningBrowsers == \"1\"")]),
            applicationResolver: resolveApplication)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("runningBrowsers"))
    }

    func testCatchAllAfterSkippedRuleRequiresManualSelection() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([
                behaviour(
                    title: "Unsupported first",
                    predicate: "runningBrowsers == \"1\""),
                behaviour(
                    title: "Fallback",
                    predicate: "TRUEPREDICATE"),
            ]),
            applicationResolver: resolveApplication)

        let fallback = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(fallback.matchType, .all)
        XCTAssertEqual(fallback.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warnings.contains { $0.contains("follows a skipped rule") })
    }

    func testSpecificRuleAfterSkippedRuleRequiresManualSelection() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([
                behaviour(
                    title: "Unsupported first",
                    predicate: "runningBrowsers == \"1\""),
                behaviour(
                    title: "GitHub",
                    predicate: "URL CONTAINS \"github.com\""),
            ]),
            applicationResolver: resolveApplication)

        let route = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(route.matchType, .regex)
        XCTAssertEqual(route.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warnings.contains { $0.contains("follows a skipped rule") })
    }

    func testRuleAfterDisabledUnsupportedRuleDoesNotRequireReview() throws {
        var disabledPrompt = behaviour(
            title: "Disabled prompt",
            predicate: "TRUEPREDICATE")
        disabledPrompt["enabled"] = false
        disabledPrompt["behaviour"] = 3

        let result = ChoosyConfigParser.parse(
            data: try propertyListData([
                disabledPrompt,
                behaviour(
                    title: "GitHub",
                    predicate: "URL CONTAINS \"github.com\""),
            ]),
            applicationResolver: resolveApplication)

        let route = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(route.name, "GitHub")
        XCTAssertNil(route.metadata?["importRequiresReview"])
        XCTAssertTrue(result.warnings.contains { $0.contains("behaviour 3") })
        XCTAssertFalse(result.warnings.contains { $0.contains("follows a skipped rule") })
    }

    func testRuleAfterDisabledMalformedEntriesDoesNotRequireReview() throws {
        var missingTitle = behaviour(
            title: "Removed",
            predicate: "TRUEPREDICATE")
        missingTitle.removeValue(forKey: "title")
        missingTitle["enabled"] = false
        var missingPredicate = behaviour(
            title: "Missing predicate",
            predicate: "TRUEPREDICATE")
        missingPredicate.removeValue(forKey: "predicate")
        missingPredicate["enabled"] = false

        let result = ChoosyConfigParser.parse(
            data: try propertyListData([
                missingTitle,
                missingPredicate,
                behaviour(
                    title: "Fallback",
                    predicate: "TRUEPREDICATE"),
            ]),
            applicationResolver: resolveApplication)

        let fallback = try XCTUnwrap(result.rules.first)
        XCTAssertEqual(fallback.name, "Fallback")
        XCTAssertNil(fallback.metadata?["importRequiresReview"])
        XCTAssertFalse(result.warnings.contains { $0.contains("follows a skipped rule") })
    }

    func testSourcePathRuleAndFollowingRuleRequireManualSelection() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([
                behaviour(
                    title: "Slack source",
                    predicate: "sourceApp == \"/Applications/Slack.app\" AND URL CONTAINS \"internal.example\""),
                behaviour(
                    title: "Fallback",
                    predicate: "TRUEPREDICATE"),
            ]),
            applicationResolver: resolveApplication)

        let sourceRule = try rule(named: "Slack source", in: result)
        let fallback = try rule(named: "Fallback", in: result)
        XCTAssertEqual(sourceRule.metadata?["importRequiresReview"], "true")
        XCTAssertEqual(fallback.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warnings.contains {
            $0.contains("app copies with the same bundle ID")
        })
        XCTAssertTrue(result.warnings.contains {
            $0.contains("follows a skipped rule")
        })
    }

    func testSourcePathReviewMarkerDoesNotHideExactSiblingAlternative() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([behaviour(
                title: "Mixed source",
                predicate: "sourceApp == \"/Applications/Slack.app\" OR URL CONTAINS \"public.example\"")]),
            applicationResolver: resolveApplication)

        XCTAssertEqual(result.rules.count, 2, result.warnings.joined(separator: "\n"))
        let sourceRule = try XCTUnwrap(result.rules.first {
            $0.sourceAppBundleId == "com.tinyspeck.slackmacgap"
        })
        let exactURLRule = try XCTUnwrap(result.rules.first {
            $0.sourceAppBundleId == nil
        })
        XCTAssertEqual(sourceRule.metadata?["importRequiresReview"], "true")
        XCTAssertNil(exactURLRule.metadata?["importRequiresReview"])
    }

    func testRuleAfterDisabledSourcePathRuleDoesNotRequireReview() throws {
        var disabledSource = behaviour(
            title: "Disabled source",
            predicate: "sourceApp == \"/Applications/Slack.app\"")
        disabledSource["enabled"] = false

        let result = ChoosyConfigParser.parse(
            data: try propertyListData([
                disabledSource,
                behaviour(
                    title: "Fallback",
                    predicate: "TRUEPREDICATE"),
            ]),
            applicationResolver: resolveApplication)

        let source = try rule(named: "Disabled source", in: result)
        let fallback = try rule(named: "Fallback", in: result)
        XCTAssertFalse(source.enabled)
        XCTAssertEqual(source.metadata?["importRequiresReview"], "true")
        XCTAssertNil(fallback.metadata?["importRequiresReview"])
        XCTAssertFalse(result.warnings.contains { $0.contains("follows a skipped rule") })
    }

    func testRejectsInvalidResolvedBundleIdentifier() throws {
        let result = ChoosyConfigParser.parse(
            data: try propertyListData([behaviour(
                title: "Invalid target",
                predicate: "TRUEPREDICATE")]),
            applicationResolver: { _ in
                ChoosyConfigParser.ResolvedApplication(
                    bundleIdentifier: "Google Chrome",
                    displayName: "Chrome")
            })

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("one valid ChoosyBrowser"))
    }

    func testPureSourcePathAndWarningHelpers() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        XCTAssertEqual(
            ChoosyConfigParser.sourcePaths(homeDirectory: home).map(\.path),
            ["/Users/test/Library/Application Support/Choosy/behaviours.plist"])
        XCTAssertEqual(
            ChoosyConfigParser.warning(
                index: 2,
                title: "  My\n rule  ",
                reason: "it is unsupported."),
            "Skipping Choosy rule \"My rule\": it is unsupported.")
        XCTAssertEqual(
            ChoosyConfigParser.warning(
                index: 2,
                title: nil,
                reason: "it is invalid."),
            "Skipping Choosy rule at position 3: it is invalid.")
    }

    func testMalformedAndWrongTopLevelPlistsReturnWarnings() throws {
        let malformed = ChoosyConfigParser.parse(
            data: Data("not a plist".utf8),
            applicationResolver: resolveApplication)
        let dictionary = ChoosyConfigParser.parse(
            data: try propertyListData(["rules": []]),
            applicationResolver: resolveApplication)

        XCTAssertTrue(malformed.rules.isEmpty)
        XCTAssertEqual(malformed.warnings.count, 1)
        XCTAssertTrue(dictionary.rules.isEmpty)
        XCTAssertEqual(
            dictionary.warnings,
            ["Choosy behaviours.plist does not contain a top-level array."])
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("Choosy", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        return try Data(contentsOf: url)
    }

    private func resolveApplication(_ url: URL) -> ChoosyConfigParser.ResolvedApplication? {
        switch url.standardizedFileURL.path {
        case "/Applications/Safari.app":
            return .init(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        case "/Applications/Google Chrome.app":
            return .init(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
        case "/Applications/Microsoft Edge.app":
            return .init(bundleIdentifier: "com.microsoft.edgemac", displayName: "Microsoft Edge")
        case "/Applications/Brave Browser.app":
            return .init(bundleIdentifier: "com.brave.Browser", displayName: "Brave Browser")
        case "/Applications/Vivaldi.app":
            return .init(bundleIdentifier: "com.vivaldi.Vivaldi", displayName: "Vivaldi")
        case "/Applications/Slack.app":
            return .init(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack")
        default:
            return nil
        }
    }

    private func rule(
        named name: String,
        in result: ChoosyConfigParser.Result
    ) throws -> Rule {
        try XCTUnwrap(result.rules.first { $0.name == name })
    }

    private func matches(_ rule: Rule, _ url: String, sourceApp: String? = nil) -> Bool {
        guard let url = URL(string: url) else { return false }
        return RuleMatcher.evaluate(
            url: url,
            against: rule,
            sourceApp: sourceApp).matched
    }

    private func behaviour(title: String, predicate: String) -> [String: Any] {
        [
            "title": title,
            "predicate": predicate,
            "enabled": true,
            "behaviour": 6,
            "behaviourArgument": [
                "path": "/Applications/Safari.app",
                "type": "ChoosyBrowser",
            ],
        ]
    }

    private func propertyListData(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0)
    }
}
