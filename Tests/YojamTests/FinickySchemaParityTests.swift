import XCTest

@testable import Yojam
import YojamCore

final class FinickySchemaParityTests: XCTestCase {
    func testObjectAccessorsAreNotImportedAsSchemaValues() {
        let result = parser.parse(#"""
        export default {
          get defaultBrowser() { return "Safari"; },
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("getter or setter") })
    }

    func testModuleExportsRequiresADirectAssignment() {
        let result = parser.parse(#"""
        module.exports ||= {
          defaultBrowser: "Safari",
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("direct module.exports") })
    }

    func testTopLevelTDZAndAbortExpressionsRejectTheWholeConfiguration() {
        let sources = [
            #"""
            export default {
              defaultBrowser: browser,
              handlers: [{ match: "safe.example/*", browser: "Safari" }]
            };
            const browser = "Safari";
            """#,
            #"""
            const unused = missingName;
            export default {
              defaultBrowser: "Safari",
              handlers: [{ match: "safe.example/*", browser: "Safari" }]
            };
            """#,
        ]

        for source in sources {
            let result = parser.parse(source)
            XCTAssertTrue(result.rules.isEmpty, result.warningMessages.joined(separator: "\n"))
            XCTAssertTrue(result.warnings.contains { $0.code == .invalid })
        }
    }

    func testFinickyThreeRejectsUnknownKeysAtEverySchemaLevel() {
        let result = parser.parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{
            match: "safe.example/*",
            browser: "Safari",
            browesr: "Google Chrome"
          }]
        };
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("shape that Finicky rejects") })
    }

    func testVersionSpecificOptionsAndApplicationTypesMatchFinickySchemas() {
        let v3Options = parser.parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          options: { checkForUpdates: true },
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        """#, version: .v3)
        let v3Path = parser.parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{
            match: "safe.example/*",
            browser: { name: "/Applications/Safari.app", appType: "path" }
          }]
        };
        """#, version: .v3)
        let v4Path = parser.parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{
            match: "safe.example/*",
            browser: { name: "/Applications/Safari.app", appType: "appPath" }
          }]
        };
        """#)

        XCTAssertTrue(v3Options.rules.isEmpty)
        XCTAssertTrue(v3Path.rules.isEmpty)
        XCTAssertTrue(v4Path.rules.isEmpty)
    }

    func testFinickyFourValidatesButDoesNotUseURLShorteners() {
        let invalid = parser.parse(#"""
        export default {
          defaultBrowser: "Safari",
          options: { urlShorteners: 42 },
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        """#)
        let valid = parser.parse(#"""
        export default {
          defaultBrowser: "Safari",
          options: { urlShorteners: ["custom.example"] },
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        """#)

        XCTAssertTrue(invalid.rules.isEmpty)
        XCTAssertEqual(valid.rules.count, 1, valid.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(
            valid.shortlinkPolicy,
            .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS))
    }

    func testSparseTopLevelArraysAndV4MatchersAreRejected() {
        let sources = [
            #"""
            export default {
              defaultBrowser: "Safari",
              handlers: [, { match: "safe.example/*", browser: "Safari" }]
            };
            """#,
            #"""
            export default {
              defaultBrowser: "Safari",
              rewrite: [, { match: "old.example/*", url: "https://new.example/" }]
            };
            """#,
            #"""
            export default {
              defaultBrowser: "Safari",
              handlers: [{ match: [, "safe.example/*"], browser: "Safari" }]
            };
            """#,
        ]

        for source in sources {
            let result = parser.parse(source)
            XCTAssertTrue(result.rules.isEmpty)
            XCTAssertTrue(result.globalRewrites.isEmpty)
            XCTAssertTrue(result.warnings.contains { $0.code == .invalid })
        }
    }

    func testFinickyThreeMatcherHolesKeepArraySomeSemantics() {
        let result = parser.parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{ match: [, "safe.example/*"], browser: "Safari" }]
        };
        """#, version: .v3)

        XCTAssertEqual(result.rules.count, 1, result.warningMessages.joined(separator: "\n"))
    }

    func testInvalidTopLevelURLConstructorRejectsTheConfiguration() {
        let result = parser.parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [{ match: "old.example/*", url: new URL() }]
        };
        """#)

        XCTAssertTrue(result.globalRewrites.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.code == .invalid })
    }

    func testFinickyThreeRequiresCommonJSExportSyntax() {
        let result = parser.parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("module.exports") })
    }

    func testApplicationAutodetectionDiffersByFinickyVersion() {
        let resolver = WorkspaceFinickyApplicationResolver()
        let reference = FinickyApplicationReference(value: "foo-bar", kind: .automatic)

        XCTAssertEqual(
            resolver.resolveApplication(reference, version: .v4),
            FinickyResolvedApplication(
                bundleIdentifier: "foo-bar",
                displayName: "foo-bar"))
        XCTAssertNil(resolver.resolveApplication(reference, version: .v3))
    }

    func testRulesJSONRejectsBadRootScalarTypesAtomically() {
        for key in ["defaultBrowser", "defaultProfile"] {
            let result = parser.parseRulesJSON(Data(#"""
            {
              "\#(key)": 42,
              "rules": [{ "match": "safe.example/*", "browser": "Safari" }]
            }
            """#.utf8))
            XCTAssertTrue(result.rules.isEmpty)
            XCTAssertFalse(result.handlerPipelineIsComplete)
        }
    }

    func testRulesJSONSkipsNullAndIncompleteRowsButKeepsValidRows() {
        let result = parser.parseRulesJSON(Data(#"""
        {
          "defaultBrowser": null,
          "defaultProfile": null,
          "rules": [
            { "match": null, "browser": "Safari" },
            { "match": "missing-browser.example/*", "browser": null },
            { "match": "safe.example/*", "browser": "Safari", "profile": null }
          ]
        }
        """#.utf8))

        XCTAssertEqual(result.rules.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertTrue(result.warningMessages.contains { $0.contains("incomplete") })
    }

    private let parser = FinickyConfigParser(
        applicationResolver: SchemaParityApplicationResolver())
}

private struct SchemaParityApplicationResolver: FinickyApplicationResolving {
    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication? {
        switch reference.value {
        case "Safari":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari")
        case "/Applications/Safari.app":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari")
        default:
            return nil
        }
    }
}
