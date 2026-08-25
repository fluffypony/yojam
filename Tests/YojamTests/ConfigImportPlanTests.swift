import XCTest
@testable import Yojam
import YojamCore

final class ConfigImportPlanTests: XCTestCase {
    func testPlanKeepsSelectedItemsAndSkipsExistingSemanticDuplicates() {
        let existingRule = makeRule(name: "Existing")
        let duplicateRule = makeRule(name: "Imported copy")
        let newRule = makeRule(
            name: "New route",
            pattern: "new.example.com",
            targetBundleID: "com.google.Chrome")
        let existingRewrite = URLRewriteRule(
            name: "Existing rewrite",
            matchPattern: #"^https://old\.example/(.*)$"#,
            replacement: "https://new.example/$1")
        let duplicateRewrite = URLRewriteRule(
            name: "Imported copy",
            matchPattern: #"^https://old\.example/(.*)$"#,
            replacement: "https://new.example/$1")
        let newRewrite = URLRewriteRule(
            name: "New rewrite",
            matchPattern: #"^https://m\.example/(.*)$"#,
            replacement: "https://example/$1")
        let result = ConfigImporter.ImportResult(
            rules: [duplicateRule, newRule],
            rewriteRules: [duplicateRewrite, newRewrite],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS))

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: Set([duplicateRule.id, newRule.id]),
            selectedRewriteIDs: Set([duplicateRewrite.id, newRewrite.id]),
            existingRules: [existingRule],
            existingRewriteRules: [existingRewrite])

        XCTAssertEqual(plan.rules.map(\.id), [newRule.id])
        XCTAssertEqual(plan.rewriteRules.map(\.id), [newRewrite.id])
        XCTAssertEqual(plan.duplicateRuleCount, 1)
        XCTAssertEqual(plan.duplicateRewriteCount, 1)
        XCTAssertTrue(plan.enablesShortlinkResolution)
    }

    func testPlanDoesNotImportUnselectedItems() {
        let route = makeRule(name: "Route")
        let rewrite = URLRewriteRule(
            name: "Rewrite",
            matchPattern: "old",
            replacement: "new",
            isRegex: false)
        let result = ConfigImporter.ImportResult(
            rules: [route],
            rewriteRules: [rewrite],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS))

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [],
            selectedRewriteIDs: [],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertTrue(plan.rules.isEmpty)
        XCTAssertTrue(plan.rewriteRules.isEmpty)
        XCTAssertEqual(plan.duplicateItemCount, 0)
        XCTAssertFalse(plan.enablesShortlinkResolution)
    }

    func testCaseSensitiveRegexRulesAreNotCollapsed() {
        let first = makeRule(name: "Upper", matchType: .regex, pattern: "ABC")
        let second = makeRule(name: "Lower", matchType: .regex, pattern: "abc")
        let result = ConfigImporter.ImportResult(
            rules: [first, second],
            warnings: [],
            source: .choosy)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: Set([first.id, second.id]),
            selectedRewriteIDs: [],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertEqual(plan.rules.count, 2)
    }

    func testPlanKeepsRuleWhenExistingRuleHasDifferentEnabledState() {
        let existing = makeRule(name: "Disabled existing")
        var disabledExisting = existing
        disabledExisting.enabled = false
        let imported = makeRule(name: "Enabled import")
        let result = ConfigImporter.ImportResult(
            rules: [imported],
            warnings: [],
            source: .finicky)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [imported.id],
            selectedRewriteIDs: [],
            existingRules: [disabledExisting],
            existingRewriteRules: [])

        XCTAssertEqual(plan.rules.map(\.id), [imported.id])
        XCTAssertEqual(plan.duplicateRuleCount, 0)
    }

    func testPlanKeepsRewriteWhenExistingRewriteHasDifferentEnabledState() {
        let existing = URLRewriteRule(
            name: "Disabled existing",
            enabled: false,
            matchPattern: "old.example",
            replacement: "new.example",
            isRegex: false)
        let imported = URLRewriteRule(
            name: "Enabled import",
            matchPattern: "old.example",
            replacement: "new.example",
            isRegex: false)
        let result = ConfigImporter.ImportResult(
            rules: [],
            rewriteRules: [imported],
            warnings: [],
            source: .finicky)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [],
            selectedRewriteIDs: [imported.id],
            existingRules: [],
            existingRewriteRules: [existing])

        XCTAssertEqual(plan.rewriteRules.map(\.id), [imported.id])
        XCTAssertEqual(plan.duplicateRewriteCount, 0)
    }

    func testFinickyRouteKeepsExplicitlySelectedRewritePipeline() {
        let route = makeRule(name: "Finicky route")
        let rewrite = URLRewriteRule(
            name: "Finicky rewrite",
            matchPattern: "old.example",
            replacement: "new.example")
        let result = ConfigImporter.ImportResult(
            rules: [route],
            rewriteRules: [rewrite],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS))

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [route.id],
            selectedRewriteIDs: [rewrite.id],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertEqual(plan.rules.map(\.id), [route.id])
        XCTAssertEqual(plan.rewriteRules.map(\.id), [rewrite.id])
        XCTAssertTrue(plan.enablesShortlinkResolution)
    }

    func testFinickyRouteIsDroppedWhenAReviewRewriteIsNotSelected() {
        let route = makeRule(name: "Finicky route")
        let exactRewrite = URLRewriteRule(
            name: "Exact rewrite",
            matchPattern: "old.example",
            replacement: "new.example")
        let reviewRewrite = URLRewriteRule(
            name: "Review rewrite",
            matchPattern: "dynamic.example",
            replacement: "review.example",
            metadata: ["importRequiresReview": "true"])
        let result = ConfigImporter.ImportResult(
            rules: [route],
            rewriteRules: [exactRewrite, reviewRewrite],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS))

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [route.id],
            selectedRewriteIDs: [exactRewrite.id],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertTrue(plan.rules.isEmpty)
        XCTAssertEqual(plan.rewriteRules.map(\.id), [exactRewrite.id])
    }

    func testFinickyRouteImportsAfterEveryRewriteIsSelected() {
        let route = makeRule(name: "Finicky route")
        let exactRewrite = URLRewriteRule(
            name: "Exact rewrite",
            matchPattern: "old.example",
            replacement: "new.example")
        let reviewRewrite = URLRewriteRule(
            name: "Review rewrite",
            matchPattern: "dynamic.example",
            replacement: "review.example",
            metadata: ["importRequiresReview": "true"])
        let result = ConfigImporter.ImportResult(
            rules: [route],
            rewriteRules: [exactRewrite, reviewRewrite],
            warnings: [],
            source: .finicky)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [route.id],
            selectedRewriteIDs: [exactRewrite.id, reviewRewrite.id],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertEqual(plan.rules.map(\.id), [route.id])
        XCTAssertEqual(
            plan.rewriteRules.map(\.id),
            [exactRewrite.id, reviewRewrite.id])
    }

    func testDuplicateOnlyFinickyImportKeepsShortlinkSettingsUnchanged() {
        let existing = makeRule(name: "Existing")
        let duplicate = makeRule(name: "Duplicate")
        let result = ConfigImporter.ImportResult(
            rules: [duplicate],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS))

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [duplicate.id],
            selectedRewriteIDs: [],
            existingRules: [existing],
            existingRewriteRules: [])

        XCTAssertNil(plan.shortlinkPolicyChange)
        XCTAssertFalse(plan.enablesShortlinkResolution)
    }

    func testKnownEmptyFinickyPolicyPreservesOptOut() {
        let route = makeRule(name: "Route")
        let result = ConfigImporter.ImportResult(
            rules: [route],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .replace(
                hosts: [],
                mode: .exactHostHTTPS))

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [route.id],
            selectedRewriteIDs: [],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertEqual(
            plan.shortlinkPolicyChange,
            .replace(hosts: [], mode: .exactHostHTTPS))
        XCTAssertFalse(plan.enablesShortlinkResolution)
    }

    func testUnknownDynamicFinickyPolicyKeepsSettingsUnchanged() {
        let route = makeRule(name: "Route")
        let result = ConfigImporter.ImportResult(
            rules: [route],
            warnings: [],
            source: .finicky,
            finickyShortlinkPolicy: .unknownDynamic)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [route.id],
            selectedRewriteIDs: [],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertNil(plan.shortlinkPolicyChange)
    }

    func testOtherImporterDoesNotEnableShortlinkResolution() {
        let route = makeRule(name: "Choosy route")
        let result = ConfigImporter.ImportResult(
            rules: [route],
            warnings: [],
            source: .choosy)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [route.id],
            selectedRewriteIDs: [],
            existingRules: [],
            existingRewriteRules: [])

        XCTAssertFalse(plan.enablesShortlinkResolution)
    }

    func testRepeatV3ImportDeduplicatesConstantHandlerRewrite() throws {
        let source = #"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{
            match: "old.example/*",
            url: "https://new.example/",
            browser: "Safari"
          }]
        };
        """#
        let parser = FinickyConfigParser()
        let existing = try XCTUnwrap(parser.parse(source, version: .v3).rules.first)
        let repeated = try XCTUnwrap(parser.parse(source, version: .v3).rules.first)
        let result = ConfigImporter.ImportResult(
            rules: [repeated],
            warnings: [],
            source: .finicky)

        let plan = ConfigImportPlan.make(
            results: [result],
            selectedRuleIDs: [repeated.id],
            selectedRewriteIDs: [],
            existingRules: [existing],
            existingRewriteRules: [])

        XCTAssertTrue(plan.rules.isEmpty)
        XCTAssertEqual(plan.duplicateRuleCount, 1)
    }

    private func makeRule(
        name: String,
        matchType: MatchType = .domainSuffix,
        pattern: String = "example.com",
        targetBundleID: String = "com.apple.Safari"
    ) -> Rule {
        Rule(
            name: name,
            matchType: matchType,
            pattern: pattern,
            targetBundleId: targetBundleID,
            targetAppName: name,
            metadata: ["importedFrom": "test"])
    }
}

@MainActor
final class ConfigImporterDetectionTests: XCTestCase {
    func testDetectionUsesCurrentBundleIdentifiersWithoutReadingConfig() {
        let installed = Set([
            "com.letsgo.Handler",
            "com.choosyosx.Choosy",
            "se.johnste.finicky",
        ])
        var requested: [String] = []

        let sources = ConfigImporter.detectAvailable { bundleID in
            requested.append(bundleID)
            return installed.contains(bundleID)
                ? URL(fileURLWithPath: "/Applications/Test.app")
                : nil
        }

        XCTAssertEqual(sources, [.bumpr, .choosy, .finicky])
        XCTAssertTrue(requested.contains("com.letsgo.Handler"))
        XCTAssertTrue(requested.contains("se.johnste.finicky"))
        XCTAssertFalse(requested.contains("com.nickvdh.Bumpr"))
    }

    func testDetectionRecognisesLegacyFinickyBundleIdentifier() {
        let sources = ConfigImporter.detectAvailable { bundleID in
            bundleID == "net.kassett.finicky"
                ? URL(fileURLWithPath: "/Applications/Finicky.app")
                : nil
        }

        XCTAssertEqual(sources, [.finicky])
    }
}
