import XCTest
@testable import YojamCore

final class URLNormalizationTests: XCTestCase {
    func testWhatWGNormalizationMatchesBrowserURLSerialization() {
        let cases = [
            ("https://EXAMPLE.com", "https://example.com/"),
            ("https://example.com:443/path", "https://example.com/path"),
            ("https://example.com/a/%2e%2e/b", "https://example.com/b"),
        ]

        for (input, expected) in cases {
            XCTAssertEqual(URLNormalizationMode.whatwg.normalize(input), expected)
        }
    }

    func testRuleMatcherUsesWhatWGURLButLeavesStandardRulesUnchanged() throws {
        let input = try XCTUnwrap(URL(
            string: "https://EXAMPLE.com:443/a/%2e%2e/b"
        ))
        let whatwgRule = Rule(
            name: "Finicky",
            matchType: .regex,
            pattern: #"^https://example\.com/b$"#,
            urlNormalization: .whatwg,
            targetBundleId: "com.apple.Safari",
            targetAppName: "Safari"
        )
        let standardRule = Rule(
            name: "Yojam",
            matchType: .regex,
            pattern: #"^https://example\.com/b$"#,
            targetBundleId: "com.apple.Safari",
            targetAppName: "Safari"
        )

        XCTAssertTrue(RuleMatcher.evaluate(url: input, against: whatwgRule).matched)
        XCTAssertFalse(RuleMatcher.evaluate(url: input, against: standardRule).matched)
    }

    func testRewriteEngineNormalizesBeforeEachWhatWGRewrite() throws {
        let input = try XCTUnwrap(URL(
            string: "https://EXAMPLE.com:443/a/%2e%2e/b"
        ))
        let rules = [
            URLRewriteRule(
                name: "First",
                matchPattern: #"^https://example\.com/b$"#,
                replacement: "https://DEST.example:443/a/%2e%2e/final",
                urlNormalization: .whatwg
            ),
            URLRewriteRule(
                name: "Second",
                matchPattern: #"^https://dest\.example/final$"#,
                replacement: "https://DONE.example:443/a/%2e%2e/final",
                urlNormalization: .whatwg
            ),
        ]

        XCTAssertEqual(
            URLRewriteEngine.apply(rules, to: input).absoluteString,
            "https://done.example/final"
        )
    }

    func testRewriteEnginePreservesStandardRuleInput() throws {
        let input = try XCTUnwrap(URL(
            string: "https://EXAMPLE.com:443/a/%2e%2e/b"
        ))
        let rule = URLRewriteRule(
            name: "No match",
            matchPattern: #"^https://example\.com/b$"#,
            replacement: "https://done.example/"
        )

        XCTAssertEqual(
            URLRewriteEngine.apply([rule], to: input).absoluteString,
            input.absoluteString
        )
    }

    func testLegacyCodableDataDefaultsToNoNormalization() throws {
        let ruleJSON = #"""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Legacy",
          "enabled": true,
          "matchType": "regex",
          "pattern": ".*",
          "targetBundleId": "com.apple.Safari",
          "targetAppName": "Safari"
        }
        """#
        let rewriteJSON = #"""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "Legacy",
          "enabled": true,
          "matchPattern": ".*",
          "replacement": "https://example.com/",
          "isRegex": true,
          "scope": { "type": "global" }
        }
        """#

        let rule = try JSONDecoder().decode(Rule.self, from: Data(ruleJSON.utf8))
        let rewrite = try JSONDecoder().decode(
            URLRewriteRule.self,
            from: Data(rewriteJSON.utf8)
        )

        XCTAssertEqual(rule.urlNormalization, .none)
        XCTAssertEqual(rewrite.urlNormalization, .none)
        XCTAssertNil(rewrite.metadata)
    }

    func testRewriteCodableRoundTripsNormalizationAndMetadata() throws {
        let rewrite = URLRewriteRule(
            name: "Imported",
            matchPattern: ".*",
            replacement: "https://example.com/",
            urlNormalization: .whatwg,
            metadata: ["importRequiresReview": "true"]
        )

        let decoded = try JSONDecoder().decode(
            URLRewriteRule.self,
            from: JSONEncoder().encode(rewrite)
        )

        XCTAssertEqual(decoded.urlNormalization, .whatwg)
        XCTAssertEqual(decoded.metadata, rewrite.metadata)
    }
}
