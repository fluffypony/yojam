import Foundation
import XCTest
@testable import Yojam
import YojamCore

final class BumprConfigParserTests: XCTestCase {
    func testParsesBumpr145ArchiveAndPreservesRuleOrder() throws {
        let parser = BumprConfigParser(applicationNameResolver: StubApplicationResolver(names: [
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Google Chrome",
        ]))

        let result = parser.parseCustomRulesArchive(try officialArchiveData())

        XCTAssertEqual(result.rules.map(\.name), ["Bumpr: github.com", "Bumpr: openai.com"])
        XCTAssertEqual(
            result.rules.map(\.targetBundleId),
            ["com.apple.Safari", "com.google.Chrome"]
        )
        XCTAssertEqual(result.rules.map(\.targetAppName), ["Safari", "Google Chrome"])
        XCTAssertEqual(result.rules.map(\.matchType), [.regex, .regex])
        XCTAssertEqual(result.rules.map(\.enabled), [true, true])
        XCTAssertEqual(result.rules.map(\.priority), [200, 200])
        XCTAssertEqual(result.rules[0].metadata?["bumprUseCount"], "0")
        XCTAssertEqual(
            result.rules[0].metadata?["bumprRuleId"],
            "4C6E9F35-F884-421F-A077-1B4BCC7ED8B2"
        )
        XCTAssertEqual(
            result.warnings,
            ["Skipped Bumpr's built-in sample rule for subtraction.com."]
        )

        let github = result.rules[0]
        XCTAssertTrue(matches(github, "https://github.com/path"))
        XCTAssertTrue(matches(github, "https://docs.github.com/path"))
        XCTAssertTrue(matches(github, "https://notgithub.com/path"))
        XCTAssertTrue(matches(github, "https://user@examplegithub.com:8443/path"))
        XCTAssertFalse(matches(github, "https://github.com.example/path"))
        XCTAssertFalse(matches(github, "https://NotGitHub.com/path"))
    }

    func testParsesCustomRulesDataFromPreferencesPlist() throws {
        let preferences = try PropertyListSerialization.data(
            fromPropertyList: ["CustomRules": try officialArchiveData()],
            format: .binary,
            options: 0
        )
        let parser = BumprConfigParser(applicationNameResolver: StubApplicationResolver(names: [
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Google Chrome",
        ]))

        let result = parser.parsePreferencesData(preferences)

        XCTAssertEqual(result.rules.map(\.name), ["Bumpr: github.com", "Bumpr: openai.com"])
    }

    func testKeepsDisabledStateAndWarnsForMalformedRules() throws {
        let archive = try makeArchive([
            FixtureRule(
                identifier: "disabled",
                domain: "work.example.com",
                handlerIdentifier: "com.google.Chrome",
                enabled: false,
                useCount: 12
            ),
            FixtureRule(
                identifier: "missing-domain",
                domain: nil,
                handlerIdentifier: "com.apple.Safari",
                enabled: true,
                useCount: 0
            ),
            FixtureRule(
                identifier: "missing-handler",
                domain: "missing.example.com",
                handlerIdentifier: nil,
                enabled: true,
                useCount: 0
            ),
        ])
        let parser = BumprConfigParser(applicationNameResolver: StubApplicationResolver(names: [
            "com.google.Chrome": "Google Chrome",
        ]))

        let result = parser.parseCustomRulesArchive(archive)

        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.rules[0].name, "Bumpr: work.example.com")
        XCTAssertTrue(matches(result.rules[0], "https://mywork.example.com/path"))
        XCTAssertFalse(result.rules[0].enabled)
        XCTAssertEqual(result.rules[0].metadata?["bumprUseCount"], "12")
        XCTAssertTrue(result.warnings.contains { $0.contains("missing-domain") })
        XCTAssertTrue(result.warnings.contains { $0.contains("no browser bundle ID") })
    }

    func testKeepsUnresolvedBundleIdentifier() throws {
        let archive = try makeArchive([
            FixtureRule(
                identifier: "unresolved",
                domain: "example.com",
                handlerIdentifier: "com.example.MissingBrowser",
                enabled: true,
                useCount: 0
            ),
        ])
        let parser = BumprConfigParser(
            applicationNameResolver: StubApplicationResolver(names: [:])
        )

        let result = parser.parseCustomRulesArchive(archive)

        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.rules[0].targetBundleId, "com.example.MissingBrowser")
        XCTAssertEqual(result.rules[0].targetAppName, "com.example.MissingBrowser")
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("keeps that bundle ID"))
    }

    func testRejectsInvalidHostnamesAndBundleIdentifiers() throws {
        let archive = try makeArchive([
            FixtureRule(
                identifier: "bad-host",
                domain: "example.com/path",
                handlerIdentifier: "com.apple.Safari",
                enabled: true,
                useCount: 0
            ),
            FixtureRule(
                identifier: "bad-bundle",
                domain: "example.com",
                handlerIdentifier: "/Applications/Safari.app",
                enabled: true,
                useCount: 0
            ),
        ])
        let parser = BumprConfigParser(
            applicationNameResolver: StubApplicationResolver(names: [:])
        )

        let result = parser.parseCustomRulesArchive(archive)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("valid hostname") })
        XCTAssertTrue(result.warnings.contains { $0.contains("bundle ID is invalid") })
    }

    func testReportsMissingOrInvalidCustomRulesData() throws {
        let parser = BumprConfigParser(
            applicationNameResolver: StubApplicationResolver(names: [:])
        )
        let noRules = try PropertyListSerialization.data(
            fromPropertyList: ["Other": true],
            format: .xml,
            options: 0
        )
        let wrongType = try PropertyListSerialization.data(
            fromPropertyList: ["CustomRules": "not data"],
            format: .xml,
            options: 0
        )

        XCTAssertEqual(
            parser.parsePreferencesData(noRules).warnings,
            ["Bumpr preferences contain no custom rules."]
        )
        XCTAssertEqual(
            parser.parsePreferencesData(wrongType).warnings,
            ["Bumpr's CustomRules value is not valid data."]
        )
        XCTAssertTrue(
            parser.parseCustomRulesArchive(Data("invalid".utf8))
                .warnings.first?.contains("Could not decode Bumpr custom rules") == true
        )
    }

    func testCurrentPreferencesPathUsesBumprBundleIdentifier() {
        let home = URL(fileURLWithPath: "/Users/test")

        XCTAssertEqual(BumprConfigPaths.bundleIdentifier, "com.letsgo.Handler")
        XCTAssertEqual(
            BumprConfigPaths.preferencesURL(homeDirectory: home).path,
            "/Users/test/Library/Containers/com.letsgo.Handler/Data/Library/Preferences/com.letsgo.Handler.plist"
        )
    }

    private func officialArchiveData() throws -> Data {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Bumpr/bumpr-1.4.5-custom-rules.base64")
        let encoded = try String(contentsOf: fixtureURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try XCTUnwrap(Data(base64Encoded: encoded))
    }

    private func makeArchive(_ rules: [FixtureRule]) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("Bumpr.CustomRule", for: FixtureRule.self)
        archiver.setClassName("Bumpr.CustomRuleSet", for: FixtureRuleSet.self)
        archiver.encode(FixtureRuleSet(rules: rules), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func matches(_ rule: Rule, _ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return RuleMatcher.evaluate(url: url, against: rule).matched
    }
}

private struct StubApplicationResolver: BumprApplicationNameResolving {
    let names: [String: String]

    func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
        names[bundleIdentifier]
    }
}

@objc(YojamBumprFixtureRuleSet)
private final class FixtureRuleSet: NSObject, NSCoding {
    let rules: [FixtureRule]

    init(rules: [FixtureRule]) {
        self.rules = rules
    }

    required init?(coder: NSCoder) {
        rules = coder.decodeObject(forKey: "rules") as? [FixtureRule] ?? []
    }

    func encode(with coder: NSCoder) {
        coder.encode(rules, forKey: "rules")
    }
}

@objc(YojamBumprFixtureRule)
private final class FixtureRule: NSObject, NSCoding {
    let identifier: String?
    let domain: String?
    let handlerIdentifier: String?
    let enabled: Bool
    let useCount: Int

    init(
        identifier: String?,
        domain: String?,
        handlerIdentifier: String?,
        enabled: Bool,
        useCount: Int
    ) {
        self.identifier = identifier
        self.domain = domain
        self.handlerIdentifier = handlerIdentifier
        self.enabled = enabled
        self.useCount = useCount
    }

    required init?(coder: NSCoder) {
        identifier = coder.decodeObject(forKey: "id") as? String
        domain = coder.decodeObject(forKey: "domain") as? String
        handlerIdentifier = coder.decodeObject(forKey: "handlerId") as? String
        enabled = coder.decodeBool(forKey: "enabled")
        useCount = coder.decodeInteger(forKey: "useCount")
    }

    func encode(with coder: NSCoder) {
        coder.encode(identifier, forKey: "id")
        coder.encode(domain, forKey: "domain")
        coder.encode(handlerIdentifier, forKey: "handlerId")
        coder.encode(enabled, forKey: "enabled")
        coder.encode(useCount, forKey: "useCount")
    }
}
