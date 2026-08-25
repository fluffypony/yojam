import XCTest
@testable import Yojam
import YojamCore

final class FinickyConfigSafetyTests: XCTestCase {
    func testNullishCoalescingMatcherIsSkippedWithWarning() {
        let result = parser().parse(#"""
        export default {
              defaultBrowser: "Safari",
          handlers: [{
            match: (url) => url.hostname === "example.com" ?? true,
            browser: "Safari"
          }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains {
            $0.code == .unsupported && $0.message.contains("handler 1")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testThrowingTopLevelCallBeforeObjectSpreadRejectsWholeConfig() {
        let result = parser().parse(#"""
        const dynamicFields = loadHandlerFields();
        export default {
              defaultBrowser: "Safari",
          handlers: [{
            match: "https://safe.example/*",
            browser: "Safari",
            ...dynamicFields
          }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("top-level statement")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testComputedHandlerPropertyIsSkippedWithWarning() {
        let result = parser().parse(#"""
        export default {
              defaultBrowser: "Safari",
          handlers: [{
            ["match"]: "https://safe.example/*",
            browser: "Safari"
          }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.code == .unsupported },
                      result.warningMessages.joined(separator: "\n"))
    }

    func testEagerDynamicBrowserCallsRejectWholeConfig() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: "https://type.example/*",
              browser: {
                name: "Google Chrome",
                appType: chooseApplicationType()
              }
            },
            {
              match: "https://profile.example/*",
              browser: {
                name: "Google Chrome",
                profile: chooseProfile()
              }
            }
          ]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("top-level helper call")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testSearchAndHashComparisonsIncludeTheirDelimiters() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: (url) => url.search === "?q=1",
              browser: "Safari"
            },
            {
              match: (url) => url.hash === "#section",
              browser: "Safari"
            }
          ]
        };
        """#)

        XCTAssertEqual(result.rules.count, 2, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(result.warnings.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages[0].contains("default browser"))

        let search = try rule(forHandler: 1, in: result)
        XCTAssertTrue(matches("https://example.com/path?q=1", rule: search))
        XCTAssertTrue(matches("https://example.com/path?q=1#section", rule: search))
        XCTAssertFalse(matches("https://example.com/path?q=10", rule: search))
        XCTAssertFalse(matches("https://example.com/path", rule: search))

        let hash = try rule(forHandler: 2, in: result)
        XCTAssertTrue(matches("https://example.com/path#section", rule: hash))
        XCTAssertFalse(matches("https://example.com/path#sections", rule: hash))
        XCTAssertFalse(matches("https://example.com/path", rule: hash))
    }

    func testEmptySearchAndHashComparisonsMatchMissingComponents() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: (url) => url.search === "",
              browser: "Safari"
            },
            {
              match: (url) => url.hash === "",
              browser: "Safari"
            }
          ]
        };
        """#)

        XCTAssertEqual(result.rules.count, 2, result.warningMessages.joined(separator: "\n"))

        let search = try rule(forHandler: 1, in: result)
        XCTAssertTrue(matches("https://example.com/path", rule: search))
        XCTAssertTrue(matches("https://example.com/path#section", rule: search))
        XCTAssertFalse(matches("https://example.com/path?q=1", rule: search))

        let hash = try rule(forHandler: 2, in: result)
        XCTAssertTrue(matches("https://example.com/path", rule: hash))
        XCTAssertTrue(matches("https://example.com/path?q=1", rule: hash))
        XCTAssertFalse(matches("https://example.com/path#section", rule: hash))
    }

    func testV3URLFieldsUseLegacyValues() throws {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: ({ url }) => url.host === "example.com",
              browser: "Safari"
            },
            {
              match: ({ url }) => url.protocol === "https",
              browser: "Safari"
            },
            {
              match: ({ url }) => url.search === "q=1",
              browser: "Safari"
            },
            {
              match: ({ url }) => url.hash === "section",
              browser: "Safari"
            },
            {
              match: (options) => options.url.host === "options.example",
              browser: "Safari"
            },
            {
              match: ({ urlString }) => urlString.startsWith("https://raw.example"),
              browser: "Safari"
            }
          ]
        };
        """#, version: .v3)

        XCTAssertEqual(result.rules.count, 6, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(Set(result.rules.map(\.urlNormalization)), [.none])
        XCTAssertTrue(matches(
            "https://example.com:8443/path",
            rule: try rule(forHandler: 1, in: result)))
        XCTAssertTrue(matches(
            "https://anything.example/path",
            rule: try rule(forHandler: 2, in: result)))
        XCTAssertTrue(matches(
            "https://anything.example/path?q=1",
            rule: try rule(forHandler: 3, in: result)))
        XCTAssertTrue(matches(
            "https://anything.example/path#section",
            rule: try rule(forHandler: 4, in: result)))
        XCTAssertTrue(matches(
            "https://options.example:9443/path",
            rule: try rule(forHandler: 5, in: result)))
        XCTAssertTrue(matches(
            "https://raw.example/path",
            rule: try rule(forHandler: 6, in: result)))
    }

    func testV3RejectsURLFieldsThatDidNotExist() {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: ({ url }) => url.hostname === "example.com",
              browser: "Safari"
            },
            {
              match: ({ url }) => url.href.startsWith("https://example.com"),
              browser: "Safari"
            }
          ]
        };
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertEqual(result.warnings.count, 3)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("default browser") })
    }

    func testStringPredicateMethodsWithPositionArgumentsAreSkipped() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: (url) => url.pathname.includes("/docs", 4),
              browser: "Safari"
            },
            {
              match: (url) => url.pathname.startsWith("/docs", 2),
              browser: "Safari"
            },
            {
              match: (url) => url.pathname.endsWith(".pdf", 8),
              browser: "Safari"
            }
          ]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertGreaterThanOrEqual(
            result.warnings.filter { $0.code == .unsupported }.count,
            3,
            result.warningMessages.joined(separator: "\n"))
    }

    func testRewriteRegularExpressionSearchesAnywhereInURL() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [{
            match: /old\.example/,
            url: "https://new.example/"
          }]
        };
        """#)

        let rewrite = try XCTUnwrap(result.globalRewrites.first)
        XCTAssertEqual(result.globalRewrites.count, 1)
        XCTAssertTrue(RegexMatcher.matches(
            "https://old.example/path",
            pattern: rewrite.matchPattern))
        XCTAssertFalse(RegexMatcher.matches(
            "https://other.example/path",
            pattern: rewrite.matchPattern))
    }

    func testSkippedRewriteMarksLaterRewriteAndRoutesForReview() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [
            {
              match: "https://old.example/*",
              url: ({ url }) => ({ ...url, host: "dynamic.example" })
            },
            {
              match: "https://work.example/*",
              url: "https://new.example/"
            }
          ],
          handlers: [{
            match: "https://old.example/*",
            browser: "Safari"
          }]
        };
        """#)

        let rewrite = try XCTUnwrap(result.globalRewrites.first)
        let route = try rule(forHandler: 1, in: result)
        XCTAssertEqual(rewrite.metadata?["importRequiresReview"], "true")
        XCTAssertEqual(route.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("rewrite follows a skipped or partly imported")
        })
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("routes depend on a skipped or partly imported rewrite")
        })
    }

    func testPartlyImportedRewriteMarksItselfAndRoutesForReview() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [{
            match: [
              "https://supported.example/*",
              () => finicky.getModifierKeys().shift
            ],
            url: "https://new.example/"
          }],
          handlers: [{
            match: "https://supported.example/*",
            browser: "Safari"
          }]
        };
        """#)

        let rewrite = try XCTUnwrap(result.globalRewrites.first)
        let route = try rule(forHandler: 1, in: result)
        XCTAssertEqual(rewrite.metadata?["importRequiresReview"], "true")
        XCTAssertEqual(route.metadata?["importRequiresReview"], "true")
    }

    func testV3ConstantHandlerURLBecomesRuleRewrite() throws {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{
            match: "old.example/*",
            url: "https://new.example/",
            browser: "Safari"
          }]
        };
        """#, version: .v3)

        let rule = try XCTUnwrap(result.rules.first)
        let rewrite = try XCTUnwrap(rule.rewriteRules.first)
        XCTAssertEqual(result.rules.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(rule.rewriteRules.count, 1)
        XCTAssertEqual(rewrite.replacement, "https://new.example/")
        XCTAssertEqual(rewrite.scope, .rule(rule.id))
    }

    func testV3DynamicHandlerURLSkipsWholeHandler() {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{
            match: "old.example/*",
            url: ({ url }) => ({ ...url, protocol: "https" }),
            browser: "Safari"
          }]
        };
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.code == .unsupported },
                      result.warningMessages.joined(separator: "\n"))
    }

    @MainActor
    func testFinickyArgumentsPreserveURLDeliverySemantics() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: "https://omitted.example/*",
              browser: { name: "Google Chrome" }
            },
            {
              match: "https://empty.example/*",
              browser: { name: "Google Chrome", args: [] }
            },
            {
              match: "https://custom.example/*",
              browser: { name: "Google Chrome", args: ["--kiosk"] }
            },
            {
              match: "https://empty-argument.example/*",
              browser: { name: "Google Chrome", args: [""] }
            },
            {
              match: "https://literal-placeholder.example/*",
              browser: { name: "Google Chrome", args: ["$URL"] }
            }
          ]
        };
        """#)

        XCTAssertEqual(result.rules.count, 4, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages.contains { $0.contains("handler 5") })
        let omitted = try rule(forHandler: 1, in: result)
        let empty = try rule(forHandler: 2, in: result)
        let custom = try rule(forHandler: 3, in: result)
        let emptyArgument = try rule(forHandler: 4, in: result)

        XCTAssertNil(omitted.ruleCustomLaunchArgs)
        XCTAssertNil(omitted.metadata?["finickySuppressAutomaticURL"])
        XCTAssertEqual(omitted.metadata?["finickyExactBrowserAction"], "true")
        XCTAssertEqual(omitted.ruleOpenInPrivateWindow, false)
        XCTAssertEqual(omitted.ruleOpenAsNewInstance, false)
        XCTAssertNil(empty.ruleCustomLaunchArgs)
        XCTAssertNil(empty.metadata?["finickySuppressAutomaticURL"])
        XCTAssertEqual(custom.ruleCustomLaunchArgs, "--kiosk")
        XCTAssertEqual(custom.metadata?["finickySuppressAutomaticURL"], "true")
        XCTAssertEqual(custom.ruleOpenAsNewInstance, false)
        XCTAssertFalse(custom.ruleCustomLaunchArgs?.contains("$URL") ?? true)

        let url = try XCTUnwrap(URL(string: "https://custom.example/path"))
        XCTAssertEqual(AppDelegate.customLaunchArguments(
            template: try XCTUnwrap(custom.ruleCustomLaunchArgs),
            url: url,
            profile: nil,
            bundleId: nil,
            privateWindow: false,
            appendURLIfMissing: false,
            usesFinickyArgumentSemantics: true), ["--kiosk"])

        XCTAssertEqual(emptyArgument.ruleCustomLaunchArgs, "''")
        XCTAssertEqual(
            emptyArgument.metadata?["finickySuppressAutomaticURL"],
            "true")
        XCTAssertEqual(AppDelegate.customLaunchArguments(
            template: try XCTUnwrap(emptyArgument.ruleCustomLaunchArgs),
            url: url,
            profile: nil,
            bundleId: nil,
            privateWindow: false,
            appendURLIfMissing: false,
            usesFinickyArgumentSemantics: true), [""])
    }

    @MainActor
    func testV3CustomArgumentsStartANewInstanceWithoutAProfile() throws {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: "custom.example/*",
              browser: { name: "Google Chrome", args: ["--user-data-dir=/tmp/finicky"] }
            },
            {
              match: "empty.example/*",
              browser: { name: "Google Chrome", args: [] }
            }
          ]
        };
        """#, version: .v3)

        let custom = try rule(forHandler: 1, in: result)
        XCTAssertEqual(custom.ruleCustomLaunchArgs, "--user-data-dir=/tmp/finicky")
        XCTAssertEqual(custom.ruleOpenAsNewInstance, true)
        XCTAssertEqual(custom.metadata?["finickySuppressAutomaticURL"], "true")
        XCTAssertEqual(AppDelegate.customLaunchArguments(
            template: try XCTUnwrap(custom.ruleCustomLaunchArgs),
            url: try XCTUnwrap(URL(string: "https://custom.example/path")),
            profile: nil,
            bundleId: nil,
            privateWindow: false,
            appendURLIfMissing: false,
            usesFinickyArgumentSemantics: true), ["--user-data-dir=/tmp/finicky"])

        let empty = try rule(forHandler: 2, in: result)
        XCTAssertNil(empty.ruleCustomLaunchArgs)
        XCTAssertEqual(empty.ruleOpenAsNewInstance, false)
        XCTAssertNil(empty.metadata?["finickySuppressAutomaticURL"])
    }

    func testDynamicRegularExpressionFlagsRejectWholeConfig() {
        let result = parser().parse(#"""
        const flags = chooseFlags();
        export default {
          defaultBrowser: "Safari",
          handlers: [{ match: new RegExp("dynamic", flags), browser: "Safari" }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
        XCTAssertTrue(result.warnings.contains { $0.code == .invalid },
                      result.warningMessages.joined(separator: "\n"))
    }

    func testStatefulRegularExpressionFlagsAreSkipped() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            { match: /global/g, browser: "Safari" },
            { match: /indices/d, browser: "Safari" },
            { match: /unicodeSets/v, browser: "Safari" }
          ]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertEqual(
            result.warningMessages.filter { $0.contains("regex flag") }.count,
            3,
            result.warningMessages.joined(separator: "\n"))
    }

    func testV4RejectsInvalidURLShortenerOptionBeforeImport() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          options: { urlShorteners: 42 },
          handlers: [{ match: "https://example.com/*", browser: "Safari" }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
        XCTAssertTrue(result.warnings.contains {
            $0.code == .invalid && $0.message.contains("options")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testEveryImportDeclarationRejectsTheWholeConfig() {
        let imports = [
            #"import "./setup.js";"#,
            #"import { target } from "./values.js";"#,
            #"import type { Target } from "./types.js";"#,
        ]

        for declaration in imports {
            let result = parser().parse(#"""
            \#(declaration)
            export default {
              defaultBrowser: "Safari",
              handlers: [{ match: "https://example.com/*", browser: "Safari" }]
            };
            """#)

            XCTAssertTrue(result.rules.isEmpty, declaration)
            XCTAssertFalse(result.handlerPipelineIsComplete, declaration)
            XCTAssertTrue(result.warningMessages.contains {
                $0.contains("imports can load code")
            }, result.warningMessages.joined(separator: "\n"))
        }
    }

    func testUnsafeFinickyTopLevelCallsRejectTheWholeConfig() {
        let calls = [
            "finicky.noSuchMethod();",
            "finicky.matchHostnames(42);",
        ]

        for call in calls {
            let result = parser().parse(#"""
            \#(call)
            export default {
              defaultBrowser: "Safari",
              handlers: [{ match: "https://example.com/*", browser: "Safari" }]
            };
            """#)

            XCTAssertTrue(result.rules.isEmpty, call)
            XCTAssertFalse(result.handlerPipelineIsComplete, call)
            XCTAssertTrue(result.warningMessages.contains {
                $0.contains("top-level helper call")
            }, result.warningMessages.joined(separator: "\n"))
        }
    }

    func testSameStatementDeclarationOrderPreservesJavaScriptTDZ() {
        let rejected = parser().parse(#"""
        const config = { defaultBrowser: "Safari", handlers },
              handlers = [{ match: "https://example.com/*", browser: "Safari" }];
        export default config;
        """#)
        let accepted = parser().parse(#"""
        const handlers = [{ match: "https://example.com/*", browser: "Safari" }],
              config = { defaultBrowser: "Safari", handlers };
        export default config;
        """#)

        XCTAssertTrue(rejected.rules.isEmpty)
        XCTAssertFalse(rejected.handlerPipelineIsComplete)
        XCTAssertTrue(rejected.warningMessages.contains {
            $0.contains("stop Finicky before it exports")
        }, rejected.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(accepted.rules.count, 1, accepted.warningMessages.joined(separator: "\n"))
    }

    func testRewriteRequiresAnAbsoluteURL() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [
            { match: "one.example/*", url: "/relative/path" },
            { match: "two.example/*", url: "relative/path" },
            { match: "three.example/*", url: "//scheme-relative.example/path" }
          ]
        };
        """#)

        XCTAssertTrue(result.globalRewrites.isEmpty)
        XCTAssertGreaterThanOrEqual(
            result.warnings.filter { $0.code == .unsupported || $0.code == .invalid }.count,
            3,
            result.warningMessages.joined(separator: "\n"))
    }

    func testMutableBindingWithLaterAssignmentIsSkipped() {
        let result = parser().parse(#"""
        let target = "Safari";
        target = "Google Chrome";
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: "https://example.com/*",
            browser: target
          }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.code == .unsupported },
                      result.warningMessages.joined(separator: "\n"))
    }

    func testMultipleModuleExportsAssignmentsAreSkippedAsAmbiguous() {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{ match: "https://first.example/*", browser: "Safari" }]
        };
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{ match: "https://last.example/*", browser: "Google Chrome" }]
        };
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains {
            $0.code == .unsupported && $0.message.contains("more than one")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testDynamicLastModuleExportsDoesNotFallBackToEarlierConfig() {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{ match: "https://first.example/*", browser: "Safari" }]
        };
        module.exports = loadConfig();
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testIgnoredDefaultBrowserAndOptionsProduceWarnings() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          options: { keepRunning: true, hideIcon: true },
          handlers: [{
            match: "https://example.com/*",
            browser: "Google Chrome"
          }]
        };
        """#)

        XCTAssertEqual(result.rules.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warnings.contains {
            $0.code == .unsupported && $0.message.contains("default browser")
        }, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warnings.contains {
            $0.code == .unsupported && $0.message.contains("options")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testCatchAllAfterSkippedHandlerRequiresManualSelection() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: () => finicky.getModifierKeys().shift,
              browser: "Safari"
            },
            {
              match: () => true,
              browser: "Google Chrome"
            }
          ]
        };
        """#)

        let fallback = try rule(forHandler: 2, in: result)
        XCTAssertEqual(fallback.matchType, .all)
        XCTAssertEqual(fallback.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("route follows a skipped or partly imported")
        })
    }

    func testProfileFolderShapeDoesNotReplaceProfileDiscovery() {
        let parser = FinickyConfigParser(
            applicationResolver: SafetyApplicationResolver(),
            profileResolver: MissingProfileResolver())
        let result = parser.parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: "https://profile.example/*",
            browser: { name: "Google Chrome", profile: "Default" }
          }]
        };
        """#)

        XCTAssertEqual(result.rules.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertNil(result.rules.first?.ruleProfileId)
        XCTAssertEqual(result.rules.first?.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warnings.contains {
            $0.code == .unresolvedProfile && $0.message.contains("resolve and launch")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testV3IgnoresProfilesForBrowsersFinickyDidNotSupport() {
        let parser = FinickyConfigParser(
            applicationResolver: SafetyApplicationResolver(),
            profileResolver: AnyProfileResolver())
        let result = parser.parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: "firefox.example/*",
              browser: { name: "Firefox", profile: "Work" }
            },
            {
              match: "opera.example/*",
              browser: { name: "Opera", profile: "Work" }
            },
            {
              match: "chromium.example/*",
              browser: { name: "Chromium", profile: "Work" }
            }
          ]
        };
        """#, version: .v3)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.rules.allSatisfy { $0.ruleProfileId == nil })
        XCTAssertTrue(result.rules.allSatisfy { $0.ruleOpenAsNewInstance == false })
    }

    func testV4ProfileAliasesAndPathsKeepTheAppRouteForReview() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: "https://alias.example/*",
              browser: { name: "Chrome Alias", profile: "Work" }
            },
            {
              match: "https://path.example/*",
              browser: {
                name: "/Applications/Google Chrome.app",
                appType: "path",
                profile: "Work"
              }
            },
            {
              match: "https://literal.example/*",
              browser: { name: "Google Chrome", profile: "Work" }
            }
          ]
        };
        """#)

        XCTAssertEqual(result.rules.count, 3, result.warningMessages.joined(separator: "\n"))
        for index in [1, 2] {
            let rule = try rule(forHandler: index, in: result)
            XCTAssertNil(rule.ruleProfileId)
            XCTAssertEqual(rule.metadata?["importRequiresReview"], "true")
        }
        let literal = try rule(forHandler: 3, in: result)
        XCTAssertEqual(literal.ruleProfileId, "Work")
        XCTAssertEqual(literal.metadata?["importRequiresReview"], "true")
    }

    func testV3LiteralURLShortenersImportWithoutManualReview() {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          options: { urlShorteners: ["t.co"] },
          rewrite: [{ match: "old.example/*", url: "https://new.example/" }],
          handlers: [{ match: "route.example/*", browser: "Safari" }]
        };
        """#, version: .v3)

        XCTAssertEqual(result.rules.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(result.globalRewrites.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertNil(result.rules.first?.metadata?["importRequiresReview"])
        XCTAssertNil(result.globalRewrites.first?.metadata?["importRequiresReview"])
        XCTAssertTrue(result.handlerPipelineIsComplete)
        XCTAssertTrue(result.rewritePipelineIsComplete)
        XCTAssertEqual(
            result.shortlinkPolicy,
            .replace(hosts: ["t.co"], mode: .exactHostHTTPS))
    }

    func testV3DynamicURLShortenersRequireManualReview() {
        let result = parser().parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          options: { urlShorteners: loadShorteners() },
          rewrite: [{ match: "old.example/*", url: "https://new.example/" }],
          handlers: [{ match: "route.example/*", browser: "Safari" }]
        };
        """#, version: .v3)

        XCTAssertEqual(result.rules.first?.metadata?["importRequiresReview"], "true")
        XCTAssertEqual(
            result.globalRewrites.first?.metadata?["importRequiresReview"],
            "true")
        XCTAssertEqual(result.shortlinkPolicy, .unknownDynamic)
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("dynamic URL shortener policy")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testCatchAllAfterPartlyImportedHandlerRequiresManualSelection() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: [
                "https://supported.example/*",
                () => finicky.getModifierKeys().shift
              ],
              browser: "Safari"
            },
            {
              match: () => true,
              browser: "Google Chrome"
            }
          ]
        };
        """#)

        XCTAssertEqual(result.rules.count, 2, result.warningMessages.joined(separator: "\n"))
        let fallback = try rule(forHandler: 2, in: result)
        XCTAssertEqual(fallback.matchType, .all)
        XCTAssertEqual(fallback.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("route follows a skipped or partly imported")
        })
    }

    func testSpecificRouteAfterSkippedHandlerRequiresManualSelection() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: () => finicky.getModifierKeys().shift,
              browser: "Safari"
            },
            {
              match: "https://github.com/*",
              browser: "Google Chrome"
            }
          ]
        };
        """#)

        let route = try rule(forHandler: 2, in: result)
        XCTAssertEqual(route.metadata?["importRequiresReview"], "true")
    }

    func testCatchAllBranchBesideSkippedMatcherRequiresManualSelection() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: [
              () => finicky.getModifierKeys().shift,
              () => true
            ],
            browser: "Safari"
          }]
        };
        """#)

        let fallback = try rule(forHandler: 1, in: result)
        XCTAssertEqual(fallback.matchType, .all)
        XCTAssertEqual(fallback.metadata?["importRequiresReview"], "true")
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("catch-all branch beside a skipped")
        })
    }

    func testApproximateBrowserActionsRequireManualSelection() throws {
        let explicitPath = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: "https://explicit-path.example/*",
            browser: {
              name: "/Applications/Google Chrome.app",
              appType: "path"
            }
          }]
        };
        """#)
        let automaticPath = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: "https://automatic-path.example/*",
            browser: "/Applications/Google Chrome.app"
          }]
        };
        """#)
        let background = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: "https://background.example/*",
            browser: {
              name: "Safari",
              openInBackground: true
            }
          }]
        };
        """#)

        XCTAssertEqual(
            try rule(forHandler: 1, in: explicitPath)
                .metadata?["importRequiresReview"],
            "true")
        XCTAssertEqual(
            try rule(forHandler: 1, in: automaticPath)
                .metadata?["importRequiresReview"],
            "true")
        XCTAssertEqual(
            try rule(forHandler: 1, in: background)
                .metadata?["importRequiresReview"],
            "true")
        XCTAssertTrue(explicitPath.warningMessages.contains {
            $0.contains("application path")
        })
        XCTAssertTrue(automaticPath.warningMessages.contains {
            $0.contains("application path")
        })
        XCTAssertTrue(background.warningMessages.contains {
            $0.contains("background")
        })
    }

    func testRulesJSONRejectsNonArrayRulesWithWarning() {
        let result = parser().parseRulesJSON(Data(#"""
        {
          "defaultBrowser": "Safari",
          "rules": "not an array"
        }
        """#.utf8))

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.code == .invalid },
                      result.warningMessages.joined(separator: "\n"))
    }

    func testRulesJSONRejectsAllEntriesWhenOneTypedEntryIsInvalid() {
        let result = parser().parseRulesJSON(Data(#"""
        {
          "defaultBrowser": "Safari",
          "rules": [
            {
              "match": "valid.example/*",
              "browser": "Safari"
            },
            {
              "match": 42,
              "browser": "Safari"
            },
            {
              "match": "missing-browser.example/*"
            },
            {
              "match": [],
              "browser": "Safari"
            },
            {
              "match": ["", "also-valid.example/*"],
              "browser": "Safari"
            }
          ]
        }
        """#.utf8))

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
        XCTAssertEqual(
            result.warnings.filter { $0.code == .invalid }.count,
            2,
            result.warningMessages.joined(separator: "\n"))
    }

    func testParseResultReportsIndependentPipelineCompleteness() {
        let complete = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [{
            match: "https://old.example/*",
            url: "https://new.example/"
          }],
          handlers: [{
            match: "https://route.example/*",
            browser: "Safari"
          }]
        };
        """#)
        let incompleteHandler = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: () => finicky.getModifierKeys().shift,
            browser: "Safari"
          }]
        };
        """#)
        let incompleteRewrite = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [{
            match: "https://old.example/*",
            url: ({ url }) => ({ ...url, host: "dynamic.example" })
          }],
          handlers: [{
            match: "https://route.example/*",
            browser: "Safari"
          }]
        };
        """#)

        XCTAssertTrue(complete.handlerPipelineIsComplete)
        XCTAssertTrue(complete.rewritePipelineIsComplete)
        XCTAssertFalse(incompleteHandler.handlerPipelineIsComplete)
        XCTAssertTrue(incompleteHandler.rewritePipelineIsComplete)
        XCTAssertTrue(incompleteRewrite.handlerPipelineIsComplete)
        XCTAssertFalse(incompleteRewrite.rewritePipelineIsComplete)
    }

    func testRulesJSONInvalidEntryRejectsLaterRoutesAtomically() {
        let result = parser().parseRulesJSON(Data(#"""
        {
          "rules": [
            {
              "match": 42,
              "browser": "Safari"
            },
            {
              "match": "later.example/*",
              "browser": "Safari"
            }
          ]
        }
        """#.utf8))

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
        XCTAssertTrue(result.rewritePipelineIsComplete)
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("one unit")
        })
    }

    func testRulesJSONMixedMatchArrayRejectsAllRoutesAtomically() {
        let result = parser().parseRulesJSON(Data(#"""
        {
          "rules": [
            {
              "match": ["partial.example/*", 42],
              "browser": "Safari"
            },
            {
              "match": "later.example/*",
              "browser": "Google Chrome"
            }
          ]
        }
        """#.utf8))

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertFalse(result.handlerPipelineIsComplete)
    }

    func testFinickyFourImportsJavaScriptHandlersBeforeRulesJSONHandlers() throws {
        let result = try importFinicky(
            javaScript: #"""
            export default {
              defaultBrowser: "Safari",
              handlers: [{
                match: "javascript.example/*",
                browser: "Safari"
              }]
            };
            """#,
            rulesJSON: #"""
            {
              "rules": [{
                "match": "json.example/*",
                "browser": "Google Chrome"
              }]
            }
            """#)

        XCTAssertEqual(result.rules.count, 2, result.warnings.joined(separator: "\n"))
        XCTAssertTrue(matches("https://javascript.example/path", rule: result.rules[0]))
        XCTAssertTrue(matches("https://json.example/path", rule: result.rules[1]))
        XCTAssertNil(result.rules[0].metadata?["importRequiresReview"])
        XCTAssertNil(result.rules[1].metadata?["importRequiresReview"])
    }

    func testFinickyFourMarksRulesJSONAfterIncompleteJavaScriptPipeline() throws {
        let sources = [
            #"""
            export default {
              defaultBrowser: "Safari",
              handlers: [{
                match: [
                  "javascript.example/*",
                  () => finicky.getModifierKeys().shift
                ],
                browser: "Safari"
              }]
            };
            """#,
            #"""
            export default {
              defaultBrowser: "Safari",
              rewrite: [{
                match: "https://old.example/*",
                url: ({ url }) => ({ ...url, host: "dynamic.example" })
              }]
            };
            """#,
        ]

        for source in sources {
            let result = try importFinicky(
                javaScript: source,
                rulesJSON: #"""
                {
                  "rules": [{
                    "match": "json.example/*",
                    "browser": "Safari"
                  }]
                }
                """#)
            let jsonRule = try XCTUnwrap(result.rules.first {
                matches("https://json.example/path", rule: $0)
            })

            XCTAssertEqual(jsonRule.metadata?["importRequiresReview"], "true")
            XCTAssertTrue(result.warnings.contains {
                $0.contains("rules.json routes follow a skipped or partly imported")
            }, result.warnings.joined(separator: "\n"))
        }
    }

    func testJavaScriptRegexCaseFlagIsPreservedExactly() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            { match: /CaseSensitive/, browser: "Safari" },
            { match: /CaseInsensitive/i, browser: "Safari" }
          ]
        };
        """#)

        let sensitive = try rule(forHandler: 1, in: result)
        XCTAssertTrue(matches("https://example.com/CaseSensitive", rule: sensitive))
        XCTAssertFalse(matches("https://example.com/casesensitive", rule: sensitive))

        let insensitive = try rule(forHandler: 2, in: result)
        XCTAssertTrue(matches("https://example.com/caseinsensitive", rule: insensitive))
    }

    private func parser() -> FinickyConfigParser {
        FinickyConfigParser(
            applicationResolver: SafetyApplicationResolver(),
            profileResolver: SafetyProfileResolver())
    }

    private func importFinicky(
        javaScript: String,
        rulesJSON: String
    ) throws -> ConfigImporter.ImportResult {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true)
        try javaScript.write(
            to: root.appendingPathComponent(".finicky.js"),
            atomically: true,
            encoding: .utf8)
        let rulesURL = FinickyConfigPaths.rulesJSONURL(homeDirectory: root)
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data(rulesJSON.utf8).write(to: rulesURL, options: .atomic)

        return ConfigImporter.importFinicky(
            homeDirectory: root,
            currentAppInstalled: true,
            legacyBookmarkData: nil)
    }

    private func rule(
        forHandler index: Int,
        in result: FinickyParseResult
    ) throws -> Rule {
        try XCTUnwrap(result.rules.first {
            $0.metadata?["finickyHandlerIndex"] == String(index)
        })
    }

    private func matches(_ url: String, rule: Rule) -> Bool {
        switch rule.matchType {
        case .all:
            return true
        case .regex:
            return RegexMatcher.matches(url, pattern: rule.pattern)
        default:
            XCTFail("Safety fixture produced unexpected match type \(rule.matchType)")
            return false
        }
    }
}

private struct SafetyApplicationResolver: FinickyApplicationResolving {
    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication? {
        switch reference.value {
        case "Safari", "com.apple.Safari":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari")
        case "Google Chrome", "com.google.Chrome", "Chrome Alias",
             "/Applications/Google Chrome.app":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.google.Chrome",
                displayName: "Google Chrome")
        case "Firefox", "org.mozilla.firefox":
            return FinickyResolvedApplication(
                bundleIdentifier: "org.mozilla.firefox",
                displayName: "Firefox")
        case "Opera", "com.operasoftware.Opera":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.operasoftware.Opera",
                displayName: "Opera")
        case "Chromium", "org.chromium.Chromium":
            return FinickyResolvedApplication(
                bundleIdentifier: "org.chromium.Chromium",
                displayName: "Chromium")
        default:
            return nil
        }
    }
}

private struct SafetyProfileResolver: FinickyProfileResolving {
    func resolveProfile(
        named name: String,
        browserBundleIdentifier: String,
        version: FinickyConfigVersion
    ) -> (id: String, name: String)? {
        guard browserBundleIdentifier == "com.google.Chrome" else { return nil }
        return (id: name, name: name)
    }
}

private struct MissingProfileResolver: FinickyProfileResolving {
    func resolveProfile(
        named name: String,
        browserBundleIdentifier: String,
        version: FinickyConfigVersion
    ) -> (id: String, name: String)? {
        nil
    }
}

private struct AnyProfileResolver: FinickyProfileResolving {
    func resolveProfile(
        named name: String,
        browserBundleIdentifier: String,
        version: FinickyConfigVersion
    ) -> (id: String, name: String)? {
        (id: name, name: name)
    }
}
