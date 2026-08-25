import XCTest
@testable import Yojam
import YojamCore

final class SyncConflictResolverTests: XCTestCase {
    func testRemoteAdditionsAppear() {
        let local = [
            BrowserEntry(id: UUID(), bundleIdentifier: "com.local", displayName: "Local")
        ]
        let remoteId = UUID()
        let remote = [
            BrowserEntry(id: remoteId, bundleIdentifier: "com.remote", displayName: "Remote")
        ]
        let merged = SyncConflictResolver.mergeBrowserLists(local: local, remote: remote)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.id == remoteId }))
    }

    func testNewerTimestampWins() {
        let id = UUID()
        let old = BrowserEntry(
            id: id, bundleIdentifier: "com.test", displayName: "Old",
            lastModifiedAt: Date(timeIntervalSince1970: 1000))
        let new = BrowserEntry(
            id: id, bundleIdentifier: "com.test", displayName: "New",
            lastModifiedAt: Date(timeIntervalSince1970: 2000))
        let merged = SyncConflictResolver.mergeBrowserLists(local: [old], remote: [new])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].displayName, "New")
    }

    func testDisjointListsMerge() {
        let a = BrowserEntry(bundleIdentifier: "com.a", displayName: "A")
        let b = BrowserEntry(bundleIdentifier: "com.b", displayName: "B")
        let merged = SyncConflictResolver.mergeBrowserLists(local: [a], remote: [b])
        XCTAssertEqual(merged.count, 2)
    }

    func testBrowserMergeDeduplicatesSameSyncedBrowserWithDifferentIds() {
        let localId = UUID()
        let remoteId = UUID()
        let local = BrowserEntry(
            id: localId,
            bundleIdentifier: "com.vivaldi.Vivaldi",
            displayName: "Vivaldi",
            position: 0,
            profileId: "Profile 1",
            profileName: "Personal",
            lastSeenAt: Date(timeIntervalSince1970: 1000))
        let remote = BrowserEntry(
            id: remoteId,
            bundleIdentifier: "com.vivaldi.Vivaldi",
            displayName: "Vivaldi",
            position: 1,
            profileId: "Profile 1",
            profileName: "Personal",
            lastSeenAt: Date(timeIntervalSince1970: 2000))

        let result = SyncConflictResolver.mergeBrowserListsWithAliases(
            local: [local],
            remote: [remote])

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].id, localId)
        XCTAssertEqual(result.idAliases[remoteId], localId)
    }

    func testBrowserMergeKeepsDistinctCustomArgumentInstances() {
        let first = BrowserEntry(
            bundleIdentifier: "org.chromium.Chromium",
            displayName: "Chromium Tmp 1",
            userDataDirectory: "/tmp/temporary1",
            openAsNewInstance: true)
        let second = BrowserEntry(
            bundleIdentifier: "org.chromium.Chromium",
            displayName: "Chromium Tmp 2",
            userDataDirectory: "/tmp/temporary2",
            openAsNewInstance: true)

        let merged = SyncConflictResolver.mergeBrowserLists(
            local: [first],
            remote: [second])

        XCTAssertEqual(merged.count, 2)
    }

    func testBrowserAliasRemapsRuleTargets() {
        let oldId = UUID()
        let newId = UUID()
        let rule = Rule(
            name: "Profile rule",
            matchType: .all,
            pattern: "",
            targetBundleId: "com.vivaldi.Vivaldi",
            targetAppName: "Vivaldi",
            targetBrowserEntryId: oldId)

        let remapped = SyncConflictResolver.remapRuleBrowserTargets(
            [rule],
            aliases: [oldId: newId])

        XCTAssertEqual(remapped[0].targetBrowserEntryId, newId)
    }

    func testRewriteRuleMerge() {
        let local = [URLRewriteRule(name: "Local", matchPattern: "a", replacement: "b", scope: .global)]
        let remote = [URLRewriteRule(name: "Remote", matchPattern: "c", replacement: "d", scope: .global)]
        let merged = SyncConflictResolver.mergeRewriteRules(local: local, remote: remote)
        XCTAssertEqual(merged.count, 2)
    }

    func testRewriteRuleMergeLocalWinsOnConflict() {
        let id = UUID()
        let local = [URLRewriteRule(id: id, name: "Local", matchPattern: "a", replacement: "b", scope: .global)]
        let remote = [URLRewriteRule(id: id, name: "Remote", matchPattern: "c", replacement: "d", scope: .global)]
        let merged = SyncConflictResolver.mergeRewriteRules(local: local, remote: remote)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Local")
    }

    func testRuleMergeNewerWins() {
        let id = UUID()
        let old = Rule(id: id, name: "Old", matchType: .domain, pattern: "a.com",
                       targetBundleId: "com.test", targetAppName: "Test",
                       lastModifiedAt: Date(timeIntervalSince1970: 1000))
        let new = Rule(id: id, name: "New", matchType: .domain, pattern: "b.com",
                       targetBundleId: "com.test", targetAppName: "Test",
                       lastModifiedAt: Date(timeIntervalSince1970: 2000))
        let merged = SyncConflictResolver.mergeRules(local: [old], remote: [new])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "New")
    }

    func testRuleMergePreservesMachineScopeEditFromOlderRemoteRule() {
        let id = UUID()
        let local = Rule(id: id, name: "Local renamed", matchType: .domain, pattern: "a.com",
                         targetBundleId: "com.test", targetAppName: "Test",
                         lastModifiedAt: Date(timeIntervalSince1970: 3000))
        let remote = Rule(id: id, name: "Original", matchType: .domain, pattern: "a.com",
                          targetBundleId: "com.test", targetAppName: "Test",
                          machineScopeIdentifiers: ["work-mac"],
                          machineScopeNames: ["work-mac": "Work Mac"],
                          lastModifiedAt: Date(timeIntervalSince1970: 2000))

        let merged = SyncConflictResolver.mergeRules(local: [local], remote: [remote])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Local renamed")
        XCTAssertEqual(merged[0].machineScopeIdentifiers, ["work-mac"])
        XCTAssertEqual(merged[0].machineScopeNames?["work-mac"], "Work Mac")
    }

    func testRuleMergeAllowsNewerMachineScopeClear() {
        let id = UUID()
        let local = Rule(id: id, name: "Scoped", matchType: .domain, pattern: "a.com",
                         targetBundleId: "com.test", targetAppName: "Test",
                         machineScopeIdentifiers: ["work-mac"],
                         machineScopeNames: ["work-mac": "Work Mac"],
                         machineScopeModifiedAt: Date(timeIntervalSince1970: 1000),
                         lastModifiedAt: Date(timeIntervalSince1970: 1000))
        let remote = Rule(id: id, name: "Scoped", matchType: .domain, pattern: "a.com",
                          targetBundleId: "com.test", targetAppName: "Test",
                          machineScopeModifiedAt: Date(timeIntervalSince1970: 2000),
                          lastModifiedAt: Date(timeIntervalSince1970: 2000))

        let merged = SyncConflictResolver.mergeRules(local: [local], remote: [remote])

        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged[0].machineScopeIdentifiers)
        XCTAssertNil(merged[0].machineScopeNames)
        XCTAssertEqual(merged[0].machineScopeModifiedAt, Date(timeIntervalSince1970: 2000))
    }

    func testVersionedBrowserSyncRecordStaysBackwardDecodable() throws {
        let browser = BrowserEntry(
            bundleIdentifier: "com.example.browser",
            displayName: "Example",
            rewriteRules: [
                URLRewriteRule(
                    name: "Versioned rewrite",
                    matchPattern: "old",
                    replacement: "new",
                    urlNormalization: .whatwg),
            ])

        let data = try JSONEncoder().encode([ICloudBrowserSyncRecord(browser: browser)])
        let oldAppDecoded = try JSONDecoder().decode([BrowserEntry].self, from: data)
        let currentDecoded = try JSONDecoder().decode([ICloudBrowserSyncRecord].self, from: data)
        let objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(oldAppDecoded, [browser])
        XCTAssertEqual(
            currentDecoded.first?.schemaVersion,
            ICloudBrowserSyncRecord.currentSchemaVersion)
        XCTAssertFalse(try XCTUnwrap(currentDecoded.first).requiresLocalRewriteFields)
        XCTAssertEqual(
            objects.first?["_yojamSyncSchemaVersion"] as? Int,
            ICloudBrowserSyncRecord.currentSchemaVersion)
        XCTAssertEqual(objects.first?["displayName"] as? String, browser.displayName)
        XCTAssertNil(objects.first?["browser"])
    }

    func testLegacyBrowserSyncCannotEraseCurrentRewriteFields() throws {
        let browserId = UUID()
        let rewriteId = UUID()
        let local = BrowserEntry(
            id: browserId,
            bundleIdentifier: "com.example.browser",
            displayName: "Local",
            rewriteRules: [
                URLRewriteRule(
                    id: rewriteId,
                    name: "Local rewrite",
                    matchPattern: "old",
                    replacement: "local",
                    urlNormalization: .whatwg,
                    metadata: ["importedFrom": "finicky"]),
            ],
            lastSeenAt: nil,
            lastModifiedAt: Date(timeIntervalSince1970: 1_000))
        let remote = BrowserEntry(
            id: browserId,
            bundleIdentifier: "com.example.browser",
            displayName: "Remote",
            rewriteRules: [
                URLRewriteRule(
                    id: rewriteId,
                    name: "Remote rewrite",
                    matchPattern: "new",
                    replacement: "remote"),
            ],
            lastSeenAt: nil,
            lastModifiedAt: Date(timeIntervalSince1970: 2_000))
        let legacyData = try removingCurrentRewriteFields(
            from: JSONEncoder().encode([remote]))
        let records = try JSONDecoder().decode([ICloudBrowserSyncRecord].self, from: legacyData)
        let legacyIds = Set(
            records.lazy
                .filter(\.requiresLocalRewriteFields)
                .map { $0.browser.id })

        let merged = SyncConflictResolver.mergeBrowserLists(
            local: [local],
            remote: records.map(\.browser),
            preservingLocalRewriteFieldsForRemoteBrowserIDs: legacyIds)

        let result = try XCTUnwrap(merged.first)
        XCTAssertEqual(result.displayName, "Remote")
        XCTAssertEqual(result.rewriteRules.first?.name, "Remote rewrite")
        XCTAssertEqual(result.rewriteRules.first?.replacement, "remote")
        XCTAssertEqual(result.rewriteRules.first?.urlNormalization, .whatwg)
        XCTAssertEqual(result.rewriteRules.first?.metadata?["importedFrom"], "finicky")
    }

    func testVersionedRuleSyncRecordStaysBackwardDecodable() throws {
        let rule = Rule(
            name: "Versioned",
            matchType: .domain,
            pattern: "example.com",
            urlNormalization: .whatwg,
            targetBundleId: "com.example.browser",
            targetAppName: "Example")

        let data = try JSONEncoder().encode([ICloudRuleSyncRecord(rule: rule)])
        let oldAppDecoded = try JSONDecoder().decode([Rule].self, from: data)
        let currentDecoded = try JSONDecoder().decode([ICloudRuleSyncRecord].self, from: data)
        let objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(oldAppDecoded, [rule])
        XCTAssertEqual(currentDecoded.first?.schemaVersion, ICloudRuleSyncRecord.currentSchemaVersion)
        XCTAssertFalse(try XCTUnwrap(currentDecoded.first).requiresLocalRewriteFields)
        XCTAssertEqual(
            objects.first?["_yojamSyncSchemaVersion"] as? Int,
            ICloudRuleSyncRecord.currentSchemaVersion)
        XCTAssertEqual(objects.first?["name"] as? String, rule.name)
        XCTAssertNil(objects.first?["rule"])
    }

    func testLegacyRuleSyncCannotEraseCurrentRewriteFields() throws {
        let ruleId = UUID()
        let rewriteId = UUID()
        let local = Rule(
            id: ruleId,
            name: "Local",
            matchType: .domain,
            pattern: "old.example",
            urlNormalization: .whatwg,
            targetBundleId: "com.example.browser",
            targetAppName: "Example",
            rewriteRules: [
                URLRewriteRule(
                    id: rewriteId,
                    name: "Local rewrite",
                    matchPattern: "old",
                    replacement: "local",
                    urlNormalization: .whatwg,
                    metadata: ["importedFrom": "finicky"]),
            ],
            lastModifiedAt: Date(timeIntervalSince1970: 1_000))
        let remote = Rule(
            id: ruleId,
            name: "Remote",
            matchType: .domain,
            pattern: "new.example",
            targetBundleId: "com.example.browser",
            targetAppName: "Example",
            rewriteRules: [
                URLRewriteRule(
                    id: rewriteId,
                    name: "Remote rewrite",
                    matchPattern: "new",
                    replacement: "remote"),
            ],
            lastModifiedAt: Date(timeIntervalSince1970: 2_000))
        let legacyData = try removingCurrentRewriteFields(
            from: JSONEncoder().encode([remote]))
        let records = try JSONDecoder().decode([ICloudRuleSyncRecord].self, from: legacyData)
        let legacyIds = Set(
            records.lazy
                .filter(\.requiresLocalRewriteFields)
                .map { $0.rule.id })

        let merged = SyncConflictResolver.mergeRules(
            local: [local],
            remote: records.map(\.rule),
            preservingLocalRewriteFieldsForRemoteRuleIDs: legacyIds)

        let result = try XCTUnwrap(merged.first)
        XCTAssertEqual(result.name, "Remote")
        XCTAssertEqual(result.pattern, "new.example")
        XCTAssertEqual(result.urlNormalization, .whatwg)
        XCTAssertEqual(result.rewriteRules.first?.name, "Remote rewrite")
        XCTAssertEqual(result.rewriteRules.first?.replacement, "remote")
        XCTAssertEqual(result.rewriteRules.first?.urlNormalization, .whatwg)
        XCTAssertEqual(result.rewriteRules.first?.metadata?["importedFrom"], "finicky")
    }

    func testVersionedRewriteSyncRecordStaysBackwardDecodable() throws {
        let rewrite = URLRewriteRule(
            name: "Versioned rewrite",
            matchPattern: "old",
            replacement: "new",
            urlNormalization: .whatwg)

        let data = try JSONEncoder().encode([
            ICloudRewriteSyncRecord(rewriteRule: rewrite),
        ])
        let oldAppDecoded = try JSONDecoder().decode([URLRewriteRule].self, from: data)
        let currentDecoded = try JSONDecoder().decode([ICloudRewriteSyncRecord].self, from: data)
        let objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(oldAppDecoded, [rewrite])
        XCTAssertEqual(
            currentDecoded.first?.schemaVersion,
            ICloudRewriteSyncRecord.currentSchemaVersion)
        XCTAssertFalse(try XCTUnwrap(currentDecoded.first).requiresLocalRewriteFields)
        XCTAssertEqual(
            objects.first?["_yojamSyncSchemaVersion"] as? Int,
            ICloudRewriteSyncRecord.currentSchemaVersion)
        XCTAssertEqual(objects.first?["name"] as? String, rewrite.name)
        XCTAssertNil(objects.first?["rewriteRule"])
    }

    func testLegacyRewriteSyncCannotEraseCurrentFields() throws {
        let id = UUID()
        let local = URLRewriteRule(
            id: id,
            name: "Local",
            matchPattern: "old",
            replacement: "local",
            urlNormalization: .whatwg,
            metadata: ["importedFrom": "finicky"],
            lastModifiedAt: Date(timeIntervalSince1970: 1_000))
        let remote = URLRewriteRule(
            id: id,
            name: "Remote",
            matchPattern: "new",
            replacement: "remote",
            lastModifiedAt: Date(timeIntervalSince1970: 2_000))
        let legacyData = try removingCurrentRewriteFields(
            from: JSONEncoder().encode([remote]))
        let records = try JSONDecoder().decode([ICloudRewriteSyncRecord].self, from: legacyData)
        let legacyIds = Set(
            records.lazy
                .filter(\.requiresLocalRewriteFields)
                .map { $0.rewriteRule.id })

        let merged = SyncConflictResolver.mergeRewriteRules(
            local: [local],
            remote: records.map(\.rewriteRule),
            preservingLocalRewriteFieldsForRemoteRewriteRuleIDs: legacyIds)

        let result = try XCTUnwrap(merged.first)
        XCTAssertEqual(result.name, "Remote")
        XCTAssertEqual(result.matchPattern, "new")
        XCTAssertEqual(result.replacement, "remote")
        XCTAssertEqual(result.urlNormalization, .whatwg)
        XCTAssertEqual(result.metadata?["importedFrom"], "finicky")
    }

    func testCompatibilitySidecarRestoresLegacyPayloadOnNewDevice() throws {
        let browserID = UUID()
        let browserRewriteID = UUID()
        let ruleID = UUID()
        let nestedRewriteID = UUID()
        let globalRewriteID = UUID()
        let browserWithCurrentFields = BrowserEntry(
            id: browserID,
            bundleIdentifier: "com.example.browser",
            displayName: "Current browser",
            rewriteRules: [
                URLRewriteRule(
                    id: browserRewriteID,
                    name: "Current browser rewrite",
                    matchPattern: "browser-old",
                    replacement: "browser-current",
                    urlNormalization: .whatwg,
                    metadata: ["importedFrom": "finicky"]),
            ])
        let ruleWithCurrentFields = Rule(
            id: ruleID,
            name: "Current rule",
            matchType: .domain,
            pattern: "current.example",
            urlNormalization: .whatwg,
            targetBundleId: "com.example.browser",
            targetAppName: "Example",
            rewriteRules: [
                URLRewriteRule(
                    id: nestedRewriteID,
                    name: "Current nested rewrite",
                    matchPattern: "nested-old",
                    replacement: "nested-current",
                    urlNormalization: .whatwg,
                    metadata: ["importedFrom": "finicky"]),
            ])
        let globalWithCurrentFields = URLRewriteRule(
            id: globalRewriteID,
            name: "Current global rewrite",
            matchPattern: "global-old",
            replacement: "global-current",
            urlNormalization: .whatwg,
            metadata: ["importedFrom": "finicky"])
        let sidecarData = try JSONEncoder().encode(ICloudCompatibilitySidecar(
            browsers: [browserWithCurrentFields],
            emailClients: [],
            phoneClients: [],
            rules: [ruleWithCurrentFields],
            globalRewrites: [globalWithCurrentFields]))

        // An old client changes fields it understands, drops the new fields and
        // schema markers, and leaves the separate sidecar key unchanged.
        let legacyBrowser = BrowserEntry(
            id: browserID,
            bundleIdentifier: "com.example.browser",
            displayName: "Old-client browser edit",
            rewriteRules: [
                URLRewriteRule(
                    id: browserRewriteID,
                    name: "Old-client browser rewrite",
                    matchPattern: "browser-new",
                    replacement: "browser-remote"),
            ])
        let legacyRule = Rule(
            id: ruleID,
            name: "Old-client rule edit",
            matchType: .domain,
            pattern: "remote.example",
            targetBundleId: "com.example.browser",
            targetAppName: "Example",
            rewriteRules: [
                URLRewriteRule(
                    id: nestedRewriteID,
                    name: "Old-client nested rewrite",
                    matchPattern: "nested-new",
                    replacement: "nested-remote"),
            ])
        let legacyGlobal = URLRewriteRule(
            id: globalRewriteID,
            name: "Old-client global rewrite",
            matchPattern: "global-new",
            replacement: "global-remote")
        let browserRecords = try JSONDecoder().decode(
            [ICloudBrowserSyncRecord].self,
            from: removingCurrentRewriteFields(from: JSONEncoder().encode([legacyBrowser])))
        let ruleRecords = try JSONDecoder().decode(
            [ICloudRuleSyncRecord].self,
            from: removingCurrentRewriteFields(from: JSONEncoder().encode([legacyRule])))
        let globalRecords = try JSONDecoder().decode(
            [ICloudRewriteSyncRecord].self,
            from: removingCurrentRewriteFields(from: JSONEncoder().encode([legacyGlobal])))
        let sidecar = try JSONDecoder().decode(
            ICloudCompatibilitySidecar.self,
            from: sidecarData)

        let restoredBrowserRemote = browserRecords.map { record in
            record.requiresLocalRewriteFields
                ? sidecar.restoringLegacyBrowser(record.browser, in: .browsers)
                : record.browser
        }
        let restoredRuleRemote = ruleRecords.map { record in
            record.requiresLocalRewriteFields
                ? sidecar.restoringLegacyRule(record.rule)
                : record.rule
        }
        let restoredGlobalRemote = globalRecords.map { record in
            record.requiresLocalRewriteFields
                ? sidecar.restoringLegacyGlobalRewrite(record.rewriteRule)
                : record.rewriteRule
        }

        let mergedBrowser = try XCTUnwrap(SyncConflictResolver.mergeBrowserLists(
            local: [], remote: restoredBrowserRemote).first)
        let mergedRule = try XCTUnwrap(SyncConflictResolver.mergeRules(
            local: [], remote: restoredRuleRemote).first)
        let mergedGlobal = try XCTUnwrap(SyncConflictResolver.mergeRewriteRules(
            local: [], remote: restoredGlobalRemote).first)

        XCTAssertEqual(mergedBrowser.displayName, "Old-client browser edit")
        XCTAssertEqual(mergedBrowser.rewriteRules.first?.replacement, "browser-remote")
        XCTAssertEqual(mergedBrowser.rewriteRules.first?.urlNormalization, .whatwg)
        XCTAssertEqual(mergedBrowser.rewriteRules.first?.metadata?["importedFrom"], "finicky")
        XCTAssertEqual(mergedRule.name, "Old-client rule edit")
        XCTAssertEqual(mergedRule.pattern, "remote.example")
        XCTAssertEqual(mergedRule.urlNormalization, .whatwg)
        XCTAssertEqual(mergedRule.rewriteRules.first?.replacement, "nested-remote")
        XCTAssertEqual(mergedRule.rewriteRules.first?.urlNormalization, .whatwg)
        XCTAssertEqual(mergedRule.rewriteRules.first?.metadata?["importedFrom"], "finicky")
        XCTAssertEqual(mergedGlobal.name, "Old-client global rewrite")
        XCTAssertEqual(mergedGlobal.replacement, "global-remote")
        XCTAssertEqual(mergedGlobal.urlNormalization, .whatwg)
        XCTAssertEqual(mergedGlobal.metadata?["importedFrom"], "finicky")
    }

    func testCompatibilitySidecarDropsWebOnlyAfterLegacyMatchEdit() throws {
        let browserRewriteID = UUID()
        let ruleID = UUID()
        let nestedRewriteID = UUID()
        let globalRewriteID = UUID()
        let metadata = [
            "importedFrom": "finicky",
            "finickyWebOnly": "true",
        ]
        let originalBrowser = BrowserEntry(
            bundleIdentifier: "com.example.browser",
            displayName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: browserRewriteID,
                    name: "Browser rewrite",
                    matchPattern: "browser-old",
                    replacement: "browser-current",
                    urlNormalization: .whatwg,
                    metadata: metadata),
            ])
        let originalRule = Rule(
            id: ruleID,
            name: "Rule",
            matchType: .domain,
            pattern: "old.example",
            urlNormalization: .whatwg,
            targetBundleId: "com.example.browser",
            targetAppName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: nestedRewriteID,
                    name: "Nested rewrite",
                    matchPattern: "nested-old",
                    replacement: "nested-current",
                    urlNormalization: .whatwg,
                    metadata: metadata),
            ],
            metadata: metadata)
        let originalGlobal = URLRewriteRule(
            id: globalRewriteID,
            name: "Global rewrite",
            matchPattern: "global-old",
            replacement: "global-current",
            urlNormalization: .whatwg,
            metadata: metadata)
        let sidecar = try JSONDecoder().decode(
            ICloudCompatibilitySidecar.self,
            from: JSONEncoder().encode(ICloudCompatibilitySidecar(
                browsers: [originalBrowser],
                emailClients: [],
                phoneClients: [],
                rules: [originalRule],
                globalRewrites: [originalGlobal])))

        let legacyBrowser = BrowserEntry(
            id: originalBrowser.id,
            bundleIdentifier: originalBrowser.bundleIdentifier,
            displayName: originalBrowser.displayName,
            rewriteRules: [
                URLRewriteRule(
                    id: browserRewriteID,
                    name: "Browser rewrite",
                    matchPattern: "browser-new",
                    replacement: "browser-remote"),
            ])
        let legacyRule = Rule(
            id: ruleID,
            name: "Rule",
            matchType: .domain,
            pattern: "new.example",
            targetBundleId: "com.example.browser",
            targetAppName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: nestedRewriteID,
                    name: "Nested rewrite",
                    matchPattern: "nested-new",
                    replacement: "nested-remote"),
            ],
            metadata: metadata)
        let legacyGlobal = URLRewriteRule(
            id: globalRewriteID,
            name: "Global rewrite",
            matchPattern: "global-new",
            replacement: "global-remote")

        let restoredBrowser = sidecar.restoringLegacyBrowser(
            legacyBrowser,
            in: .browsers)
        let restoredRule = sidecar.restoringLegacyRule(legacyRule)
        let restoredGlobal = sidecar.restoringLegacyGlobalRewrite(legacyGlobal)
        let unchangedGlobal = sidecar.restoringLegacyGlobalRewrite(URLRewriteRule(
            id: globalRewriteID,
            name: "Global rewrite",
            matchPattern: "global-old",
            replacement: "global-remote"))

        XCTAssertEqual(
            restoredBrowser.rewriteRules.first?.metadata?["importedFrom"],
            "finicky")
        XCTAssertNil(restoredBrowser.rewriteRules.first?.metadata?["finickyWebOnly"])
        XCTAssertEqual(restoredRule.metadata?["importedFrom"], "finicky")
        XCTAssertNil(restoredRule.metadata?["finickyWebOnly"])
        XCTAssertEqual(
            restoredRule.rewriteRules.first?.metadata?["importedFrom"],
            "finicky")
        XCTAssertNil(restoredRule.rewriteRules.first?.metadata?["finickyWebOnly"])
        XCTAssertEqual(restoredGlobal.metadata?["importedFrom"], "finicky")
        XCTAssertNil(restoredGlobal.metadata?["finickyWebOnly"])
        XCTAssertEqual(unchangedGlobal.metadata?["finickyWebOnly"], "true")
    }

    func testDelayedCompatibilitySidecarWinsEqualTimestampMerge() throws {
        let timestamp = Date(timeIntervalSince1970: 2_000)
        let browserID = UUID()
        let browserRewriteID = UUID()
        let ruleID = UUID()
        let nestedRewriteID = UUID()
        let globalRewriteID = UUID()
        let metadata = [
            "importedFrom": "finicky",
            "finickyWebOnly": "true",
        ]
        let currentBrowser = BrowserEntry(
            id: browserID,
            bundleIdentifier: "com.example.browser",
            displayName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: browserRewriteID,
                    name: "Browser rewrite",
                    matchPattern: "browser",
                    replacement: "browser-current",
                    urlNormalization: .whatwg,
                    metadata: metadata),
            ])
        let currentRule = Rule(
            id: ruleID,
            name: "Rule",
            matchType: .domain,
            pattern: "example.com",
            urlNormalization: .whatwg,
            targetBundleId: "com.example.browser",
            targetAppName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: nestedRewriteID,
                    name: "Nested rewrite",
                    matchPattern: "nested",
                    replacement: "nested-current",
                    urlNormalization: .whatwg,
                    metadata: metadata),
            ],
            lastModifiedAt: timestamp)
        let currentGlobal = URLRewriteRule(
            id: globalRewriteID,
            name: "Global rewrite",
            matchPattern: "global",
            replacement: "global-current",
            urlNormalization: .whatwg,
            metadata: metadata,
            lastModifiedAt: timestamp)
        let sidecar = ICloudCompatibilitySidecar(
            browsers: [currentBrowser],
            emailClients: [],
            phoneClients: [],
            rules: [currentRule],
            globalRewrites: [currentGlobal])
        let legacyBrowser = BrowserEntry(
            id: browserID,
            bundleIdentifier: "com.example.browser",
            displayName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: browserRewriteID,
                    name: "Browser rewrite",
                    matchPattern: "browser",
                    replacement: "browser-current"),
            ])
        let legacyRule = Rule(
            id: ruleID,
            name: "Rule",
            matchType: .domain,
            pattern: "example.com",
            targetBundleId: "com.example.browser",
            targetAppName: "Browser",
            rewriteRules: [
                URLRewriteRule(
                    id: nestedRewriteID,
                    name: "Nested rewrite",
                    matchPattern: "nested",
                    replacement: "nested-current"),
            ],
            lastModifiedAt: timestamp)
        let legacyGlobal = URLRewriteRule(
            id: globalRewriteID,
            name: "Global rewrite",
            matchPattern: "global",
            replacement: "global-current",
            lastModifiedAt: timestamp)

        var firstBrowser = try XCTUnwrap(SyncConflictResolver.mergeBrowserLists(
            local: [],
            remote: [legacyBrowser]).first)
        firstBrowser.lastSeenAt = Date(timeIntervalSince1970: 3_000)
        let firstRule = try XCTUnwrap(SyncConflictResolver.mergeRules(
            local: [],
            remote: [legacyRule]).first)
        let firstGlobal = try XCTUnwrap(SyncConflictResolver.mergeRewriteRules(
            local: [],
            remote: [legacyGlobal]).first)
        XCTAssertEqual(
            firstBrowser.rewriteRules.first?.urlNormalization,
            URLNormalizationMode.none)
        XCTAssertEqual(firstRule.urlNormalization, .none)
        XCTAssertEqual(firstGlobal.urlNormalization, .none)

        let restoredBrowser = sidecar.restoringLegacyBrowser(
            legacyBrowser,
            in: .browsers)
        let restoredRule = sidecar.restoringLegacyRule(legacyRule)
        let restoredGlobal = sidecar.restoringLegacyGlobalRewrite(legacyGlobal)
        let secondBrowser = try XCTUnwrap(SyncConflictResolver.mergeBrowserLists(
            local: [firstBrowser],
            remote: [restoredBrowser],
            preferringRemoteOnEqualTimestampForBrowserIDs: [browserID]).first)
        let secondRule = try XCTUnwrap(SyncConflictResolver.mergeRules(
            local: [firstRule],
            remote: [restoredRule],
            preferringRemoteOnEqualTimestampForRuleIDs: [ruleID]).first)
        let secondGlobal = try XCTUnwrap(SyncConflictResolver.mergeRewriteRules(
            local: [firstGlobal],
            remote: [restoredGlobal],
            preferringRemoteOnEqualTimestampForRewriteRuleIDs: [globalRewriteID]).first)

        XCTAssertEqual(secondBrowser.rewriteRules.first?.urlNormalization, .whatwg)
        XCTAssertEqual(
            secondBrowser.rewriteRules.first?.metadata?["finickyWebOnly"],
            "true")
        XCTAssertEqual(secondRule.urlNormalization, .whatwg)
        XCTAssertEqual(secondRule.rewriteRules.first?.urlNormalization, .whatwg)
        XCTAssertEqual(
            secondRule.rewriteRules.first?.metadata?["finickyWebOnly"],
            "true")
        XCTAssertEqual(secondGlobal.urlNormalization, .whatwg)
        XCTAssertEqual(secondGlobal.metadata?["finickyWebOnly"], "true")
    }

    func testVersionedRewriteSyncCanClearURLNormalization() throws {
        let id = UUID()
        let local = URLRewriteRule(
            id: id,
            name: "Local",
            matchPattern: "old",
            replacement: "local",
            urlNormalization: .whatwg,
            metadata: ["importedFrom": "finicky"],
            lastModifiedAt: Date(timeIntervalSince1970: 1_000))
        let remote = URLRewriteRule(
            id: id,
            name: "Remote",
            matchPattern: "new",
            replacement: "remote",
            urlNormalization: .none,
            lastModifiedAt: Date(timeIntervalSince1970: 2_000))
        let data = try JSONEncoder().encode([
            ICloudRewriteSyncRecord(rewriteRule: remote),
        ])
        let records = try JSONDecoder().decode([ICloudRewriteSyncRecord].self, from: data)
        let legacyIds = Set(
            records.lazy
                .filter(\.requiresLocalRewriteFields)
                .map { $0.rewriteRule.id })

        let merged = SyncConflictResolver.mergeRewriteRules(
            local: [local],
            remote: records.map(\.rewriteRule),
            preservingLocalRewriteFieldsForRemoteRewriteRuleIDs: legacyIds)

        XCTAssertEqual(
            try XCTUnwrap(merged.first).urlNormalization,
            URLNormalizationMode.none)
        XCTAssertNil(try XCTUnwrap(merged.first).metadata)
    }

    private func removingCurrentRewriteFields(from data: Data) throws -> Data {
        var objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for index in objects.indices {
            objects[index].removeValue(forKey: "urlNormalization")
            if objects[index]["matchPattern"] != nil {
                objects[index].removeValue(forKey: "metadata")
            }
            guard var rewrites = objects[index]["rewriteRules"] as? [[String: Any]] else {
                continue
            }
            for rewriteIndex in rewrites.indices {
                rewrites[rewriteIndex].removeValue(forKey: "urlNormalization")
                rewrites[rewriteIndex].removeValue(forKey: "metadata")
            }
            objects[index]["rewriteRules"] = rewrites
        }
        return try JSONSerialization.data(withJSONObject: objects)
    }
}
