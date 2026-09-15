import Foundation
import XCTest
@testable import Yojam

final class NativeMessagingInstallerTests: IsolatedSettingsTestCase {
    private let firstID = String(repeating: "a", count: 32)
    private let secondID = String(repeating: "b", count: 32)

    @MainActor
    func testUpgradeAtSamePathAddsChromeWithoutRewritingFirefox() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [])
        XCTAssertTrue(reconcile(plan: before, settingsStore: store, files: files.access))
        XCTAssertEqual(files.writes.count, 1)

        files.clearOperations()
        let after = try plan(ids: [firstID])
        XCTAssertTrue(reconcile(plan: after, settingsStore: store, files: files.access))
        XCTAssertEqual(files.writes, [try manifest("Chrome", in: after).fileURL])
        XCTAssertEqual(try json("Chrome", in: after, files: files)["allowed_origins"] as? [String], [
            "chrome-extension://\(firstID)/"
        ])
        XCTAssertEqual(store.lastNativeMessagingRegistrationKey, after.registrationKey)
    }

    @MainActor
    func testChangedExtensionIDsReplaceAllowedOrigins() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [firstID])
        reconcile(plan: before, settingsStore: store, files: files.access)
        files.clearOperations()

        let after = try plan(ids: [secondID])
        reconcile(plan: after, settingsStore: store, files: files.access)
        XCTAssertEqual(files.writes, [try manifest("Chrome", in: after).fileURL])
        XCTAssertEqual(try json("Chrome", in: after, files: files)["allowed_origins"] as? [String], [
            "chrome-extension://\(secondID)/"
        ])
    }

    @MainActor
    func testUnchangedLaunchDoesNotAccessBrowserDirectories() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let expected = try plan(ids: [firstID])
        reconcile(plan: expected, settingsStore: store, files: files.access)
        files.clearOperations()

        XCTAssertTrue(reconcile(
            plan: expected, settingsStore: makeSettingsStore(), files: files.access))
        XCTAssertEqual(files.operationCount, 0)
    }

    @MainActor
    func testEquivalentExtensionIDListDoesNotTriggerReconciliation() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [firstID, secondID])
        reconcile(plan: before, settingsStore: store, files: files.access)
        files.clearOperations()

        let after = try plan(ids: [" \(secondID)\n", firstID, "", secondID])
        XCTAssertEqual(before.registrationKey, after.registrationKey)
        reconcile(plan: after, settingsStore: store, files: files.access)
        XCTAssertEqual(files.operationCount, 0)
    }

    @MainActor
    func testChangedHostPathRepairsBothBrowserManifests() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        reconcile(plan: try plan(ids: [firstID]), settingsStore: store, files: files.access)
        files.clearOperations()

        let host = "/Applications/Moved Yojam.app/Contents/Helpers/YojamNativeHost.app/Contents/MacOS/YojamNativeHost"
        let after = try plan(ids: [firstID], hostPath: host)
        reconcile(plan: after, settingsStore: store, files: files.access)
        XCTAssertEqual(files.writes.count, 2)
        for browser in ["Chrome", "Firefox"] {
            XCTAssertEqual(try json(browser, in: after, files: files)["path"] as? String, host)
        }
    }

    @MainActor
    func testChangedHelperManifestContentInvalidatesMarkerAtSamePath() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [firstID])
        reconcile(plan: before, settingsStore: store, files: files.access)
        files.clearOperations()

        // A later app release can change a manifest field without moving its host.
        let changed = try before.manifests.map { item in
            guard item.browserName == "Firefox", let contents = item.contents else { return item }
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any])
            value["description"] = "Updated browser helper"
            return NativeMessagingInstaller.Manifest(
                browserName: item.browserName, fileURL: item.fileURL,
                contents: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys))
        }
        let after = NativeMessagingInstaller.Plan(manifests: changed)
        XCTAssertNotEqual(before.registrationKey, after.registrationKey)
        reconcile(plan: after, settingsStore: store, files: files.access)
        XCTAssertEqual(files.writes, [try manifest("Firefox", in: after).fileURL])
    }

    @MainActor
    func testBrowserInstallationChangesAddAndRemoveOnlyItsManifest() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [firstID], browsers: ["org.mozilla.firefox"])
        reconcile(plan: before, settingsStore: store, files: files.access)
        files.clearOperations()

        let after = try plan(ids: [firstID], browsers: ["com.google.Chrome"])
        reconcile(plan: after, settingsStore: store, files: files.access)
        XCTAssertNotNil(files.contents[try manifest("Chrome", in: after).fileURL])
        XCTAssertNil(files.contents[try manifest("Firefox", in: after).fileURL])
        XCTAssertEqual(files.writes.count, 1)
    }

    @MainActor
    func testExplicitRepairPreservesMatchingJSONAndRestoresMissingFile() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let expected = try plan(ids: [firstID])
        reconcile(plan: expected, settingsStore: store, files: files.access)
        let chrome = try manifest("Chrome", in: expected)
        let firefox = try manifest("Firefox", in: expected)
        // Existing formatting does not justify another write to a protected directory.
        files.contents[chrome.fileURL] = try JSONSerialization.data(
            withJSONObject: json("Chrome", in: expected, files: files), options: [])
        files.contents.removeValue(forKey: firefox.fileURL)
        files.clearOperations()

        XCTAssertTrue(reconcile(
            plan: expected, settingsStore: store, force: true, files: files.access))
        XCTAssertEqual(files.writes, [firefox.fileURL])
        XCTAssertEqual(store.lastNativeMessagingRegistrationKey, expected.registrationKey)
    }

    @MainActor
    func testFailedWriteRetriesWithoutRewritingSuccessfulFiles() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let expected = try plan(ids: [firstID])
        let chrome = try manifest("Chrome", in: expected).fileURL
        files.failedWrites.insert(chrome)
        XCTAssertFalse(reconcile(
            plan: expected, settingsStore: store, files: files.access))
        XCTAssertNil(store.lastNativeMessagingRegistrationKey)
        files.failedWrites.removeAll()
        files.clearOperations()

        XCTAssertTrue(reconcile(
            plan: expected, settingsStore: store, files: files.access))
        XCTAssertEqual(files.writes, [chrome])
        XCTAssertEqual(store.lastNativeMessagingRegistrationKey, expected.registrationKey)
    }

    @MainActor
    func testFailedForcedRepairClearsPreviousMarker() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let expected = try plan(ids: [firstID])
        reconcile(plan: expected, settingsStore: store, files: files.access)
        let chrome = try manifest("Chrome", in: expected).fileURL
        files.contents[chrome] = Data("altered".utf8)
        files.failedWrites.insert(chrome)
        XCTAssertFalse(reconcile(
            plan: expected, settingsStore: store, force: true, files: files.access))
        XCTAssertNil(store.lastNativeMessagingRegistrationKey)
    }

    @MainActor
    func testReadFailureDoesNotOverwriteTheExistingManifest() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let expected = try plan(ids: [firstID])
        let chrome = try manifest("Chrome", in: expected).fileURL
        let existing = Data("unreadable existing file".utf8)
        files.contents[chrome] = existing
        files.failedReads.insert(chrome)
        XCTAssertFalse(reconcile(
            plan: expected, settingsStore: store, files: files.access))
        XCTAssertEqual(files.contents[chrome], existing)
        XCTAssertFalse(files.writes.contains(chrome))
        XCTAssertNil(store.lastNativeMessagingRegistrationKey)
    }

    @MainActor
    func testLegacyPathMarkerRequiresOneContentCheckWithoutRewriting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: appSuiteName))
        defaults.set("/Applications/Yojam.app", forKey: "lastNativeMessagingBundlePath")
        let store = makeSettingsStore()
        XCTAssertNil(defaults.object(forKey: "lastNativeMessagingBundlePath"))
        XCTAssertNil(store.lastNativeMessagingRegistrationKey)
        let expected = try plan(ids: [firstID])
        let files = MemoryFiles()
        for manifest in expected.manifests { files.contents[manifest.fileURL] = manifest.contents }

        XCTAssertTrue(reconcile(
            plan: expected, settingsStore: store, files: files.access))
        XCTAssertTrue(files.writes.isEmpty)
        XCTAssertEqual(makeSettingsStore().lastNativeMessagingRegistrationKey, expected.registrationKey)
        files.clearOperations()
        reconcile(plan: expected, settingsStore: store, files: files.access)
        XCTAssertEqual(files.operationCount, 0)
    }

    @MainActor
    func testOlderAppMarkerInvalidatesAnExistingFingerprint() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: appSuiteName))
        let key = try plan(ids: [firstID]).registrationKey
        defaults.set(key, forKey: "lastNativeMessagingRegistrationKey")
        defaults.set("/Applications/Yojam.app", forKey: "lastNativeMessagingBundlePath")
        XCTAssertNil(makeSettingsStore().lastNativeMessagingRegistrationKey)
        XCTAssertNil(defaults.object(forKey: "lastNativeMessagingBundlePath"))
    }

    @MainActor
    func testFailedRemovalRemainsRetryable() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [firstID])
        reconcile(plan: before, settingsStore: store, files: files.access)
        let chrome = try manifest("Chrome", in: before).fileURL
        let after = try plan(ids: [])
        files.failedRemovals.insert(chrome)
        XCTAssertFalse(reconcile(plan: after, settingsStore: store, files: files.access))
        XCTAssertNil(store.lastNativeMessagingRegistrationKey)
        XCTAssertNotNil(files.contents[chrome])

        files.failedRemovals.removeAll()
        files.clearOperations()
        XCTAssertTrue(reconcile(plan: after, settingsStore: store, files: files.access))
        XCTAssertNil(files.contents[chrome])
        XCTAssertTrue(files.writes.isEmpty)
    }

    @MainActor
    func testResetClearsSuccessfulRegistrationMarker() {
        let store = makeSettingsStore()
        store.lastNativeMessagingRegistrationKey = "completed"
        store.resetToDefaults()
        XCTAssertNil(store.lastNativeMessagingRegistrationKey)
        XCTAssertNil(makeSettingsStore().lastNativeMessagingRegistrationKey)
    }

    func testOnlyTheProvisionedHelperBundlePathIsResolved() throws {
        let app = configDirectory.appendingPathComponent("Yojam.app")
        let oldHost = app.appendingPathComponent("Contents/MacOS/YojamNativeHost")
        try FileManager.default.createDirectory(at: oldHost.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy helper".utf8).write(to: oldHost)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldHost.path)
        XCTAssertNil(NativeMessagingInstaller.resolveHostPath(in: app))

        let helper = app.appendingPathComponent("Contents/Helpers/YojamNativeHost.app/Contents/MacOS/YojamNativeHost")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bundled helper".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        XCTAssertEqual(NativeMessagingInstaller.resolveHostPath(in: app), helper.path)
    }

    @MainActor
    func testUpgradeReplacesBareToolPathsInExistingManifests() throws {
        let store = makeSettingsStore()
        let files = MemoryFiles()
        let before = try plan(ids: [firstID], hostPath: "/Applications/Yojam.app/Contents/MacOS/YojamNativeHost")
        reconcile(plan: before, settingsStore: store, files: files.access)
        files.clearOperations()
        let after = try plan(ids: [firstID])

        XCTAssertTrue(reconcile(plan: after, settingsStore: store, files: files.access))
        XCTAssertEqual(files.writes.count, 2)
        for browser in ["Chrome", "Firefox"] {
            let path = try XCTUnwrap(json(browser, in: after, files: files)["path"] as? String)
            XCTAssertTrue(path.contains("/Helpers/YojamNativeHost.app/Contents/MacOS/"))
        }
    }

    @MainActor
    func testFileAdapterCreatesUpdatesAndRemovesOnlyTemporaryManifests() throws {
        let store = makeSettingsStore()
        let before = try plan(ids: [firstID])
        XCTAssertTrue(reconcile(plan: before, settingsStore: store, files: .live))
        let firefox = try manifest("Firefox", in: before).fileURL
        let originalDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: firefox.path)

        let after = try plan(ids: [secondID])
        XCTAssertTrue(reconcile(plan: after, settingsStore: store, files: .live))
        let chromeData = try Data(contentsOf: manifest("Chrome", in: after).fileURL)
        let chrome = try XCTUnwrap(JSONSerialization.jsonObject(with: chromeData) as? [String: Any])
        XCTAssertEqual(chrome["allowed_origins"] as? [String], ["chrome-extension://\(secondID)/"])
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: firefox.path)[.modificationDate] as? Date,
            originalDate)

        let noBrowsers = try plan(ids: [secondID], browsers: [])
        XCTAssertTrue(reconcile(plan: noBrowsers, settingsStore: store, files: .live))
        for item in noBrowsers.manifests {
            XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL.path))
        }
    }

    @MainActor
    @discardableResult
    private func reconcile(
        plan: NativeMessagingInstaller.Plan, settingsStore: SettingsStore,
        force: Bool = false, files: NativeMessagingInstaller.FileAccess
    ) -> Bool {
        NativeMessagingInstaller.reconcile(
            plan: plan, settingsStore: settingsStore, force: force, files: files, log: { _ in })
    }

    private func plan(
        ids: [String],
        hostPath: String = "/Applications/Yojam.app/Contents/Helpers/YojamNativeHost.app/Contents/MacOS/YojamNativeHost",
        browsers: Set<String> = ["com.google.Chrome", "org.mozilla.firefox"]
    ) throws -> NativeMessagingInstaller.Plan {
        try NativeMessagingInstaller.makePlan(.init(
            applicationSupportDirectory: configDirectory.appendingPathComponent("Fake Application Support"),
            hostPath: hostPath, chromeExtensionIds: ids, installedBrowserBundleIds: browsers))
    }

    private func manifest(_ browser: String, in plan: NativeMessagingInstaller.Plan) throws -> NativeMessagingInstaller.Manifest {
        try XCTUnwrap(plan.manifests.first { $0.browserName == browser })
    }

    @MainActor
    private func json(_ browser: String, in plan: NativeMessagingInstaller.Plan, files: MemoryFiles) throws -> [String: Any] {
        let data = try XCTUnwrap(files.contents[manifest(browser, in: plan).fileURL])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private final class MemoryFiles {
        var contents: [URL: Data] = [:]
        var reads: [URL] = []
        var writes: [URL] = []
        var removals: [URL] = []
        var failedReads: Set<URL> = []
        var failedWrites: Set<URL> = []
        var failedRemovals: Set<URL> = []
        var operationCount: Int { reads.count + writes.count + removals.count }

        var access: NativeMessagingInstaller.FileAccess {
            .init(read: { url in
                self.reads.append(url)
                if self.failedReads.contains(url) { throw CocoaError(.fileReadNoPermission) }
                return self.contents[url]
            }, write: { data, url in
                if self.failedWrites.contains(url) { throw CocoaError(.fileWriteNoPermission) }
                self.writes.append(url)
                self.contents[url] = data
            }, remove: { url in
                self.removals.append(url)
                if self.failedRemovals.contains(url) { throw CocoaError(.fileWriteNoPermission) }
                self.contents.removeValue(forKey: url)
            })
        }

        func clearOperations() {
            reads.removeAll()
            writes.removeAll()
            removals.removeAll()
        }
    }
}
