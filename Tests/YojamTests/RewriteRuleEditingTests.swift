import XCTest
@testable import Yojam
import YojamCore

final class RewriteRuleEditingTests: XCTestCase {
    @MainActor
    func testApplyingEditPreservesIdentityOrderEnabledStateAndScope() {
        let first = URLRewriteRule(
            name: "First",
            matchPattern: "first.example",
            replacement: "first.test",
            scope: .global)
        let originalModifiedAt = Date(timeIntervalSince1970: 1_000)
        let original = URLRewriteRule(
            name: "Original",
            enabled: false,
            matchPattern: "original.example",
            replacement: "original.test",
            isRegex: false,
            scope: .global,
            urlNormalization: .whatwg,
            metadata: ["importRequiresReview": "true"],
            lastModifiedAt: originalModifiedAt)
        let last = URLRewriteRule(
            name: "Last",
            matchPattern: "last.example",
            replacement: "last.test",
            scope: .global)
        let rules = [first, original, last]
        let edited = URLRewriteRule(
            id: original.id,
            name: "Edited",
            enabled: true,
            matchPattern: #"^https://original\.example/(.*)"#,
            replacement: "https://edited.test/$1",
            isRegex: true,
            scope: .browser("should-not-replace-scope"),
            lastModifiedAt: originalModifiedAt)
        let modifiedAt = Date(timeIntervalSince1970: 2_000)

        let updated = PipelineTab.rewriteRulesByApplyingEdit(
            edited,
            to: rules,
            modifiedAt: modifiedAt)

        XCTAssertEqual(updated.map(\.id), rules.map(\.id))
        XCTAssertEqual(updated[0], first)
        XCTAssertEqual(updated[2], last)
        XCTAssertEqual(updated[1].id, original.id)
        XCTAssertEqual(updated[1].name, "Edited")
        XCTAssertFalse(updated[1].enabled)
        XCTAssertEqual(updated[1].matchPattern, #"^https://original\.example/(.*)"#)
        XCTAssertEqual(updated[1].replacement, "https://edited.test/$1")
        XCTAssertTrue(updated[1].isRegex)
        XCTAssertEqual(updated[1].scope, .global)
        XCTAssertEqual(updated[1].urlNormalization, .whatwg)
        XCTAssertEqual(updated[1].metadata, ["importRequiresReview": "true"])
        XCTAssertEqual(updated[1].lastModifiedAt, modifiedAt)
    }

    @MainActor
    func testApplyingEditForUnknownIdentityLeavesRulesUnchanged() {
        let rules = [
            URLRewriteRule(
                name: "Existing",
                matchPattern: "example.com",
                replacement: "example.test",
                scope: .global),
        ]
        let unknown = URLRewriteRule(
            name: "Unknown",
            matchPattern: "unknown.example",
            replacement: "unknown.test",
            scope: .global)

        let updated = PipelineTab.rewriteRulesByApplyingEdit(
            unknown,
            to: rules,
            modifiedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(updated, rules)
    }

    @MainActor
    func testChangingImportedFinickyRewriteMatchMakesItUserScoped() throws {
        let original = URLRewriteRule(
            name: "Imported",
            matchPattern: #"^https://example\.com/(.*)$"#,
            replacement: "https://example.net/$1",
            scope: .global,
            urlNormalization: .whatwg,
            metadata: [
                "importedFrom": "finicky",
                "finickyWebOnly": "true",
            ])
        let edited = URLRewriteRule(
            id: original.id,
            name: original.name,
            matchPattern: #"^mailto:(.*)$"#,
            replacement: "mailto:$1",
            scope: .global)

        let updated = PipelineTab.rewriteRulesByApplyingEdit(edited, to: [original])
        let saved = try XCTUnwrap(updated.first)

        XCTAssertEqual(saved.metadata?["importedFrom"], "finicky")
        XCTAssertNil(saved.metadata?["finickyWebOnly"])
    }
}
