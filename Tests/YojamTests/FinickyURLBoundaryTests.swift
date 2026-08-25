import XCTest
@testable import Yojam
import YojamCore

final class FinickyURLBoundaryTests: XCTestCase {
    func testV4StandardProtocolStringOperationsKeepTheColonBoundary() throws {
        try assertURLCases([
            URLCase(
                expression: #"url.protocol === "https:""#,
                matches: ["https://example.com/path"],
                rejects: ["http://example.com/path", "httpsx://example.com/path"]),
            URLCase(
                expression: #"url.protocol.includes("tt")"#,
                matches: ["https://example.com/path"],
                rejects: ["ftp://example.com/path"]),
            URLCase(
                expression: #"url.protocol.startsWith("ht")"#,
                matches: ["https://example.com/path", "http://example.com/path"],
                rejects: ["xhttps://example.com/path"]),
            URLCase(
                expression: #"url.protocol.endsWith("ps:")"#,
                matches: ["https://example.com/path"],
                rejects: ["http://example.com/path", "httpsx://example.com/path"]),
            URLCase(
                expression: #"url.protocol === "https""#,
                matches: [],
                rejects: ["https://example.com/path"]),
            URLCase(
                expression: #"url.protocol.includes(":")"#,
                matches: ["https://example.com/path", "ftp://example.com/path"],
                rejects: []),
            URLCase(
                expression: #"url.protocol.startsWith("https:")"#,
                matches: ["https://example.com/path"],
                rejects: ["httpsx://example.com/path"]),
            URLCase(
                expression: #"url.protocol.endsWith(":")"#,
                matches: ["https://example.com/path", "ftp://example.com/path"],
                rejects: []),
            URLCase(
                expression: #"url.protocol.endsWith("ps")"#,
                matches: [],
                rejects: ["https://example.com/path"]),
            URLCase(
                expression: #"url.protocol.includes(":x")"#,
                matches: [],
                rejects: ["https://example.com/path"]),
        ])
    }

    func testV4StandardSearchStringOperationsStayInsideTheQuery() throws {
        try assertURLCases([
            URLCase(
                expression: #"url.search === "?q=1""#,
                matches: [
                    "https://example.com/path?q=1",
                    "https://example.com/path?q=1#fragment",
                ],
                rejects: [
                    "https://example.com/path?q=10",
                    "https://example.com/path",
                ]),
            URLCase(
                expression: #"url.search.includes("q=1")"#,
                matches: ["https://example.com/path?x=0&q=1&z=2"],
                rejects: [
                    "https://example.com/path?q=2",
                    "https://example.com/path#q=1",
                ]),
            URLCase(
                expression: #"url.search.startsWith("?q=")"#,
                matches: ["https://example.com/path?q=1"],
                rejects: [
                    "https://example.com/path?x=1&q=2",
                    "https://example.com/path#?q=1",
                ]),
            URLCase(
                expression: #"url.search.endsWith("=1")"#,
                matches: [
                    "https://example.com/path?q=1",
                    "https://example.com/path?x=0&q=1#fragment",
                ],
                rejects: [
                    "https://example.com/path?q=1&x=2",
                    "https://example.com/path?q=2#=1",
                ]),
            URLCase(
                expression: #"url.search === "q=1""#,
                matches: [],
                rejects: ["https://example.com/path?q=1"]),
            URLCase(
                expression: #"url.search.startsWith("q=")"#,
                matches: [],
                rejects: ["https://example.com/path?q=1"]),
            URLCase(
                expression: #"url.search.includes("?")"#,
                matches: ["https://example.com/path?q=1"],
                rejects: [
                    "https://example.com/path",
                    "https://example.com/path?",
                ]),
            URLCase(
                expression: "url.search.includes(\"#\")",
                matches: [],
                rejects: ["https://example.com/path?q=1#fragment"]),
        ])
    }

    func testV4StandardHashStringOperationsStayInsideTheFragment() throws {
        try assertURLCases([
            URLCase(
                expression: "url.hash === \"#section\"",
                matches: ["https://example.com/path#section"],
                rejects: [
                    "https://example.com/path#sections",
                    "https://example.com/path",
                ]),
            URLCase(
                expression: #"url.hash.includes("sect")"#,
                matches: ["https://example.com/path#section"],
                rejects: [
                    "https://example.com/section",
                    "https://example.com/path?value=section",
                ]),
            URLCase(
                expression: "url.hash.startsWith(\"#sec\")",
                matches: ["https://example.com/path#section"],
                rejects: ["https://example.com/path#xsection"]),
            URLCase(
                expression: #"url.hash.endsWith("tion")"#,
                matches: ["https://example.com/path#section"],
                rejects: ["https://example.com/path#section-more"]),
            URLCase(
                expression: #"url.hash === "section""#,
                matches: [],
                rejects: ["https://example.com/path#section"]),
            URLCase(
                expression: #"url.hash.startsWith("sec")"#,
                matches: [],
                rejects: ["https://example.com/path#section"]),
            URLCase(
                expression: "url.hash.includes(\"#\")",
                matches: ["https://example.com/path#section"],
                rejects: [
                    "https://example.com/path",
                    "https://example.com/path#",
                ]),
        ])
    }

    func testV4LegacyArgumentURLFieldsUseV3Values() throws {
        let cases = legacyURLCases(root: "arg.url")
        try assertURLCases(cases, parameter: "arg")
    }

    func testV4DestructuredLegacyURLFieldsUseV3Values() throws {
        let cases = legacyURLCases(root: "url")
        try assertURLCases(cases, parameter: "{ url }")
    }

    func testV4LegacyURLStringAndOpenerBundleID() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          handlers: [
            {
              match: (arg) => arg.urlString.startsWith("https://raw.example/"),
              browser: "Safari"
            },
            {
              match: (arg) =>
                arg.opener.bundleId === "com.example.source" &&
                arg.url.host === "source.example",
              browser: "Safari"
            }
          ]
        };
        """#)

        XCTAssertEqual(result.rules.count, 2, result.warningMessages.joined(separator: "\n"))
        let rawURLRule = try rule(forHandler: 1, in: result)
        XCTAssertTrue(matches("https://raw.example/path", rule: rawURLRule))
        XCTAssertFalse(matches("http://raw.example/path", rule: rawURLRule))

        let openerRule = try rule(forHandler: 2, in: result)
        XCTAssertTrue(matches(
            "https://source.example/path",
            rule: openerRule,
            sourceApp: "com.example.source"))
        XCTAssertFalse(matches(
            "https://source.example/path",
            rule: openerRule,
            sourceApp: "com.example.other"))
        XCTAssertFalse(matches(
            "https://other.example/path",
            rule: openerRule,
            sourceApp: "com.example.source"))
    }

    func testV4StaticFunctionReturnedRewritesImport() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [
            {
              match: "https://old-one.example/*",
              url: () => "https://new-one.example/"
            },
            {
              match: "https://old-two.example/*",
              url: function () { return new URL("https://new-two.example/"); }
            },
            {
              match: "https://dynamic.example/*",
              url: (url) => url.href
            },
            {
              match: "https://called.example/*",
              url: () => chooseURL()
            }
          ]
        };
        """#)

        XCTAssertEqual(result.globalRewrites.count, 2, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(
            Set(result.globalRewrites.map(\.replacement)),
            ["https://new-one.example/", "https://new-two.example/"])
        XCTAssertTrue(result.warningMessages.contains { $0.contains("rewrite 3") })
        XCTAssertTrue(result.warningMessages.contains { $0.contains("rewrite 4") })
    }

    func testV4TwoArgumentURLRewriteUsesWHATWGResolution() throws {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [{
            match: "https://old.example/*",
            url: new URL("../final path?value=1", "HTTPS://NEW.EXAMPLE/base/path/")
          }]
        };
        """#)

        let rewrite = try XCTUnwrap(result.globalRewrites.first)
        XCTAssertEqual(result.globalRewrites.count, 1, result.warningMessages.joined(separator: "\n"))
        XCTAssertEqual(rewrite.replacement, "https://new.example/base/final%20path?value=1")
    }

    func testV4IncompleteHTTPRewritesAreInvalid() {
        let result = parser().parse(#"""
        export default {
          defaultBrowser: "Safari",
          rewrite: [
            { match: "https://one.example/*", url: "https:" },
            { match: "https://two.example/*", url: "https://" },
            { match: "https://three.example/*", url: () => "https:" },
            { match: "https://four.example/*", url: () => new URL("https://") }
          ]
        };
        """#)

        XCTAssertTrue(result.globalRewrites.isEmpty)
        XCTAssertEqual(
            result.warningMessages.filter { $0.contains("Finicky rewrite") }.count,
            4,
            result.warningMessages.joined(separator: "\n"))
    }

    private func legacyURLCases(root: String) -> [URLCase] {
        [
            URLCase(
                expression: #"\#(root).host === "legacy.example""#,
                matches: ["https://legacy.example:8443/path"],
                rejects: ["https://other.example:8443/path"]),
            URLCase(
                expression: #"\#(root).pathname === "/docs/start""#,
                matches: ["https://example.com/docs/start?q=1#section"],
                rejects: ["https://example.com/docs/start-more"]),
            URLCase(
                expression: #"\#(root).protocol === "https""#,
                matches: ["https://example.com/path"],
                rejects: ["http://example.com/path"]),
            URLCase(
                expression: #"\#(root).search === "q=1""#,
                matches: ["https://example.com/path?q=1#section"],
                rejects: ["https://example.com/path?q=10"]),
            URLCase(
                expression: #"\#(root).hash === "section""#,
                matches: ["https://example.com/path#section"],
                rejects: ["https://example.com/path#sections"]),
        ]
    }

    private func assertURLCases(
        _ cases: [URLCase],
        parameter: String = "url",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let handlers = cases.map {
            "{ match: (\(parameter)) => \($0.expression), browser: \"Safari\" }"
        }.joined(separator: ",\n")
        let result = parser().parse(
            "export default { defaultBrowser: \"Safari\", handlers: [\(handlers)] };")

        XCTAssertEqual(
            result.rules.count,
            cases.count,
            result.warningMessages.joined(separator: "\n"),
            file: file,
            line: line)
        for (offset, item) in cases.enumerated() {
            let importedRule = try rule(forHandler: offset + 1, in: result)
            for url in item.matches {
                XCTAssertTrue(
                    matches(url, rule: importedRule),
                    "Expected handler \(offset + 1) to match \(url): \(item.expression)",
                    file: file,
                    line: line)
            }
            for url in item.rejects {
                XCTAssertFalse(
                    matches(url, rule: importedRule),
                    "Expected handler \(offset + 1) to reject \(url): \(item.expression)",
                    file: file,
                    line: line)
            }
        }
    }

    private func parser() -> FinickyConfigParser {
        FinickyConfigParser(applicationResolver: BoundaryApplicationResolver())
    }

    private func rule(
        forHandler index: Int,
        in result: FinickyParseResult
    ) throws -> Rule {
        try XCTUnwrap(result.rules.first {
            $0.metadata?["finickyHandlerIndex"] == String(index)
        })
    }

    private func matches(
        _ rawURL: String,
        rule: Rule,
        sourceApp: String? = nil
    ) -> Bool {
        guard let url = URL(string: rawURL) else {
            XCTFail("Could not make the test URL: \(rawURL)")
            return false
        }
        return RuleMatcher.evaluate(
            url: url,
            against: rule,
            sourceApp: sourceApp
        ).matched
    }
}

private struct URLCase {
    var expression: String
    var matches: [String]
    var rejects: [String]
}

private struct BoundaryApplicationResolver: FinickyApplicationResolving {
    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication? {
        guard reference.value == "Safari" || reference.value == "com.apple.Safari" else {
            return nil
        }
        return FinickyResolvedApplication(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari")
    }
}
