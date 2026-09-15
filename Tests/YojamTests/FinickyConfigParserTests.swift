import XCTest
@testable import Yojam
import YojamCore

final class FinickyConfigParserTests: XCTestCase {
    func testIssue35ShapeImportsFunctionsRegexProfileAndArguments() throws {
        let source = try String(contentsOf: fixtureURL("issue-35-shape.js"), encoding: .utf8)

        let result = makeParser().parse(source)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(result.warnings.count, 2, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages.contains { $0.contains("default browser") })
        XCTAssertTrue(result.warningMessages.contains { $0.contains("options") })
        XCTAssertTrue(result.globalRewrites.isEmpty)

        let sourceOnly = try XCTUnwrap(result.rules.first {
            $0.metadata?["finickyHandlerIndex"] == "1"
        })
        XCTAssertEqual(sourceOnly.matchType, .all)
        XCTAssertEqual(sourceOnly.pattern, "")
        XCTAssertEqual(sourceOnly.sourceApps.first?.bundleId, "com.example.password-manager")
        XCTAssertEqual(sourceOnly.targetBundleId, "com.apple.Safari")

        let profileRoutes = result.rules.filter {
            $0.metadata?["finickyHandlerIndex"] == "2"
        }
        XCTAssertEqual(profileRoutes.count, 1)
        XCTAssertEqual(Set(profileRoutes.map(\.targetBundleId)), ["com.google.Chrome"])
        XCTAssertEqual(Set(profileRoutes.compactMap(\.ruleProfileId)), ["Profile 7"])
        XCTAssertEqual(Set(profileRoutes.compactMap(\.ruleCustomLaunchArgs)), [
            "--app-id=example-app-id "
                + "--app-launch-url-for-shortcuts-menu-item=$URL",
        ])
        XCTAssertEqual(Set(profileRoutes.compactMap(\.ruleOpenAsNewInstance)), [true])

        let fallbackRoute = try XCTUnwrap(profileRoutes.first)
        XCTAssertTrue(fallbackRoute.sourceApps.isEmpty)
        XCTAssertTrue(RegexMatcher.matches(
            "https://meet.example.test/room",
            pattern: fallbackRoute.pattern
        ))
        XCTAssertFalse(RegexMatcher.matches(
            "https://accounts.example.test/sign-in",
            pattern: fallbackRoute.pattern
        ))

        let regexRoute = try XCTUnwrap(result.rules.first {
            $0.metadata?["finickyHandlerIndex"] == "3"
        })
        XCTAssertTrue(RegexMatcher.matches(
            "https://calendar.example.test/events/42",
            pattern: regexRoute.pattern
        ))
    }

    func testTypeScriptAliasesArraysSpreadsAndBrowserObject() {
        let source = #"""
        interface FinickyConfig { handlers: unknown[] }
        const matches = [
          "https://Example.com/*",
          /^https:\/\/Secure\.example\/.*$/,
          new RegExp("^https://Exact\\.example/.*$")
        ];
        const browser = {
          name: "com.google.Chrome",
          appType: "bundleId",
          profile: "Work"
        };
        const action = { browser };
        const handler = ({ match: matches, ...action } as const);
        export default ({ defaultBrowser: "Safari", handlers: [handler] } satisfies FinickyConfig);
        """#

        let result = makeParser().parse(source)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(result.warnings.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages[0].contains("default browser"))
        XCTAssertEqual(Set(result.rules.map(\.targetBundleId)), ["com.google.Chrome"])
        XCTAssertEqual(Set(result.rules.compactMap(\.ruleProfileId)), ["Profile 7"])
        XCTAssertEqual(Set(result.rules.map(\.urlNormalization)), [.whatwg])

        let wildcard = result.rules[0]
        XCTAssertFalse(RuleMatcher.evaluate(
            url: URL(string: "https://Example.com/a/path")!,
            against: wildcard
        ).matched)

        let literal = result.rules[1]
        XCTAssertTrue(literal.pattern.hasPrefix("(?-i:"))
        XCTAssertFalse(RuleMatcher.evaluate(
            url: URL(string: "https://Secure.example/a")!,
            against: literal
        ).matched)

        let constructor = result.rules[2]
        XCTAssertFalse(RuleMatcher.evaluate(
            url: URL(string: "https://Exact.example/a")!,
            against: constructor
        ).matched)
    }

    func testSupportedFunctionPredicateAndHostnameHelper() throws {
        let source = #"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: (url, options) =>
                options.opener.bundleId === "com.tinyspeck.slackmacgap" &&
                url.hostname.endsWith(".corp.example") &&
                url.pathname.startsWith("/docs"),
              browser: "Safari"
            },
            {
              match: finicky.matchHostnames([
                "calendar.example.com",
                "meet.example.com"
              ]),
              browser: "Google Chrome"
            }
          ]
        };
        """#

        let result = makeParser().parse(source)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(result.warnings.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages[0].contains("default browser"))
        let predicateRule = try XCTUnwrap(result.rules.first {
            $0.sourceApps.first?.bundleId == "com.tinyspeck.slackmacgap"
        })
        XCTAssertTrue(RuleMatcher.evaluate(
            url: URL(string: "https://handbook.corp.example/docs/start")!,
            against: predicateRule,
            sourceApp: "com.tinyspeck.slackmacgap"
        ).matched)
        XCTAssertFalse(RuleMatcher.evaluate(
            url: URL(string: "https://handbook.corp.example/help/start")!,
            against: predicateRule,
            sourceApp: "com.tinyspeck.slackmacgap"
        ).matched)
        XCTAssertTrue(RuleMatcher.evaluate(
            url: URL(string: "https://handbook.CORP.example/docs/start")!,
            against: predicateRule,
            sourceApp: "com.tinyspeck.slackmacgap"
        ).matched)
    }

    func testImportedMatchersUseWhatWGURLSerialization() {
        let source = #"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: [
              /^https:\/\/example\.com\/$/,
              /^https:\/\/example\.com\/path$/,
              /^https:\/\/example\.com\/b$/
            ],
            browser: "Safari"
          }]
        };
        """#

        let result = makeParser().parse(source)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(Set(result.rules.map(\.urlNormalization)), [.whatwg])
        XCTAssertTrue(RuleMatcher.evaluate(
            url: URL(string: "https://EXAMPLE.com")!,
            against: result.rules[0]
        ).matched)
        XCTAssertTrue(RuleMatcher.evaluate(
            url: URL(string: "https://example.com:443/path")!,
            against: result.rules[1]
        ).matched)
        XCTAssertTrue(RuleMatcher.evaluate(
            url: URL(string: "https://example.com/a/%2e%2e/b")!,
            against: result.rules[2]
        ).matched)
    }

    func testV3WildcardAddsHTTPProtocolAndExpandsStars() throws {
        let source = #"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{ match: "*.example.com/*", browser: "Safari" }]
        };
        """#

        let result = makeParser().parse(source, version: .v3)

        let rule = try XCTUnwrap(result.rules.first)
        XCTAssertTrue(RegexMatcher.matches(
            "https://docs.example.com/path",
            pattern: rule.pattern
        ))
        XCTAssertTrue(RegexMatcher.matches(
            "http://docs.example.com/path",
            pattern: rule.pattern
        ))
        XCTAssertFalse(RegexMatcher.matches(
            "https://docs.example.com",
            pattern: rule.pattern
        ))
    }

    func testUnsupportedHandlersAndRewriteEachHaveLocatedWarning() {
        let source = #"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: () => finicky.getModifierKeys().shift,
              browser: "Safari"
            },
            {
              match: "https://example.com/*",
              browser: () => chooseBrowser()
            }
          ],
          rewrite: [
            {
              match: "https://old.example/*",
              url: ({ url }) => new URL(url.pathname, "https://new.example")
            }
          ]
        };
        """#

        let result = makeParser().parse(source)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.globalRewrites.isEmpty)
        XCTAssertEqual(result.warnings.count, 4)
        XCTAssertTrue(result.warnings.allSatisfy { $0.code == .unsupported })
        XCTAssertTrue(result.warnings.allSatisfy { $0.line != nil && $0.column != nil })
        XCTAssertTrue(result.warningMessages.contains { $0.contains("handler 1") })
        XCTAssertTrue(result.warningMessages.contains { $0.contains("handler 2") })
        XCTAssertTrue(result.warningMessages.contains { $0.contains("rewrite 1") })
    }

    func testStaticSourceIsParsedButNeverExecuted() {
        let source = #"""
        globalThis.yojamImporterWasExecuted = true;
        throw new Error("User source ran");
        export default {
          defaultBrowser: "Safari",
          handlers: [{ match: "https://safe.example/*", browser: "Safari" }]
        };
        """#

        let result = makeParser().parse(source)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("stop Finicky") })
    }

    func testRulesJSONImportsArraysAndProfiles() {
        let data = Data(#"""
        {
          "defaultBrowser": "Google Chrome",
          "rules": [
            {
              "match": ["example.com/*", "github.com/*"],
              "browser": "Safari"
            },
            {
              "match": "linear.app/*",
              "browser": "Google Chrome",
              "profile": "Work"
            }
          ]
        }
        """#.utf8)

        let result = makeParser().parseRulesJSON(data)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(result.warnings.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages[0].contains("default browser"))
        XCTAssertEqual(result.rules.last?.targetBundleId, "com.google.Chrome")
        XCTAssertEqual(result.rules.last?.ruleProfileId, "Profile 7")
    }

    func testConstantRewriteIsReturnedSeparately() throws {
        let source = #"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [
            {
              match: "https://old.example/*",
              url: "https://new.example/"
            }
          ]
        };
        """#

        let result = makeParser().parse(source)

        XCTAssertTrue(result.rules.isEmpty)
        let rewrite = try XCTUnwrap(result.globalRewrites.first)
        XCTAssertEqual(result.globalRewrites.count, 1)
        XCTAssertEqual(rewrite.scope, .global)
        XCTAssertEqual(rewrite.urlNormalization, .whatwg)
        XCTAssertEqual(rewrite.replacement, "https://new.example/")
        XCTAssertTrue(RegexMatcher.matches(
            "https://old.example/path",
            pattern: rewrite.matchPattern
        ))
        XCTAssertFalse(RegexMatcher.matches(
            "https://other.example/path",
            pattern: rewrite.matchPattern
        ))
        XCTAssertEqual(
            URLRewriteEngine.apply(
                [rewrite],
                to: URL(string: "https://OLD.example:443/a/%2e%2e/path")!
            ).absoluteString,
            "https://new.example/"
        )
    }

    func testStableConfigPathsCoverAllFinickyFourLocationsAndRulesJSON() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        XCTAssertEqual(
            FinickyConfigPaths.stableConfigURLs(homeDirectory: home).map(\.path),
            [
                "/Users/example/.finicky.js",
                "/Users/example/.finicky.ts",
                "/Users/example/.config/finicky.js",
                "/Users/example/.config/finicky.ts",
                "/Users/example/.config/finicky/finicky.js",
                "/Users/example/.config/finicky/finicky.ts",
            ]
        )
        XCTAssertEqual(
            FinickyConfigPaths.rulesJSONURL(homeDirectory: home).path,
            "/Users/example/Library/Application Support/Finicky/rules.json"
        )
    }

    func testFinickyFourUsesNewestValidCachedCustomConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent(
            "Library/Caches/Finicky",
            isDirectory: true)
        let olderConfig = root.appendingPathComponent("old.js")
        let newerConfig = root.appendingPathComponent("custom/config.ts")
        try FileManager.default.createDirectory(
            at: newerConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: cache,
            withIntermediateDirectories: true)
        try "export default {};".write(to: olderConfig, atomically: true, encoding: .utf8)
        try "export default {};".write(to: newerConfig, atomically: true, encoding: .utf8)

        let oldRecord = cache.appendingPathComponent("config_cache_old.json")
        let newRecord = cache.appendingPathComponent("config_cache_new.json")
        try JSONSerialization.data(withJSONObject: [
            "configPath": olderConfig.path,
        ]).write(to: oldRecord)
        try JSONSerialization.data(withJSONObject: [
            "configPath": newerConfig.path,
        ]).write(to: newRecord)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: oldRecord.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newRecord.path)

        XCTAssertEqual(
            FinickyConfigPaths.preferredConfigURL(
                homeDirectory: root,
                version: .v4)?.path,
            newerConfig.path)
    }

    func testFinickyFourCacheMustMatchTheSelectedAppVersion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent(
            "Library/Caches/Finicky",
            isDirectory: true)
        let selectedConfig = root.appendingPathComponent("selected.js")
        let otherConfig = root.appendingPathComponent("other.js")
        try FileManager.default.createDirectory(
            at: cache,
            withIntermediateDirectories: true)
        try "export default {};".write(
            to: selectedConfig,
            atomically: true,
            encoding: .utf8)
        try "export default {};".write(
            to: otherConfig,
            atomically: true,
            encoding: .utf8)

        let selectedRecord = cache.appendingPathComponent("config_cache_selected.json")
        let newerOtherRecord = cache.appendingPathComponent("config_cache_other.json")
        try JSONSerialization.data(withJSONObject: [
            "appVersion": "4.1.0",
            "configPath": selectedConfig.path,
        ]).write(to: selectedRecord)
        try JSONSerialization.data(withJSONObject: [
            "appVersion": "4.2.0",
            "configPath": otherConfig.path,
        ]).write(to: newerOtherRecord)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: selectedRecord.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerOtherRecord.path)

        XCTAssertEqual(
            FinickyConfigPaths.preferredConfigURL(
                homeDirectory: root,
                version: .v4,
                appVersion: "4.1.0")?.path,
            selectedConfig.path)
    }

    func testFinickyThreeUsesLegacyBookmarkBeforeStablePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stable = root.appendingPathComponent(".finicky.js")
        let custom = root.appendingPathComponent("custom.js")
        try "module.exports = {};".write(to: stable, atomically: true, encoding: .utf8)
        try "module.exports = {};".write(to: custom, atomically: true, encoding: .utf8)
        let bookmark = try custom.bookmarkData()

        XCTAssertEqual(
            FinickyConfigPaths.preferredConfigURL(
                homeDirectory: root,
                version: .v3,
                legacyBookmarkData: bookmark)?.path,
            custom.path)
    }

    func testFinickyThreeFallsBackOnlyToDotFinickyJavaScript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".config"),
            withIntermediateDirectories: true)
        try "export default {};".write(
            to: root.appendingPathComponent(".finicky.ts"),
            atomically: true,
            encoding: .utf8)
        try "export default {};".write(
            to: root.appendingPathComponent(".config/finicky.js"),
            atomically: true,
            encoding: .utf8)

        XCTAssertNil(FinickyConfigPaths.preferredConfigURL(
            homeDirectory: root,
            version: .v3))

        let legacy = root.appendingPathComponent(".finicky.js")
        try "module.exports = {};".write(
            to: legacy,
            atomically: true,
            encoding: .utf8)
        XCTAssertEqual(
            FinickyConfigPaths.preferredConfigURL(
                homeDirectory: root,
                version: .v3)?.path,
            legacy.path)
    }

    func testKnownBrowserNameResolvesWithoutInstalledApplication() {
        let resolver = WorkspaceFinickyApplicationResolver()

        XCTAssertEqual(
            resolver.resolveApplication(FinickyApplicationReference(
                value: "Google Chrome Canary",
                kind: .appName), version: .v4),
            FinickyResolvedApplication(
                bundleIdentifier: "com.google.Chrome.canary",
                displayName: "Google Chrome Canary"))
    }

    private func makeParser() -> FinickyConfigParser {
        FinickyConfigParser(
            applicationResolver: StubFinickyApplicationResolver(),
            profileResolver: StubFinickyProfileResolver()
        )
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Finicky")
            .appendingPathComponent(name)
    }
}

private struct StubFinickyApplicationResolver: FinickyApplicationResolving {
    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication? {
        switch reference.value {
        case "Safari", "com.apple.Safari":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari"
            )
        case "Google Chrome", "com.google.Chrome":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.google.Chrome",
                displayName: "Google Chrome"
            )
        default:
            return nil
        }
    }
}

private struct StubFinickyProfileResolver: FinickyProfileResolving {
    func resolveProfile(
        named name: String,
        browserBundleIdentifier: String,
        version: FinickyConfigVersion
    ) -> (id: String, name: String)? {
        guard browserBundleIdentifier == "com.google.Chrome" else { return nil }
        switch name {
        case "LendInvest": return (id: "Profile 3", name: name)
        case "Work": return (id: "Profile 7", name: name)
        default: return nil
        }
    }
}
