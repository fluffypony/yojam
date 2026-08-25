import XCTest
import Darwin

@testable import Yojam

final class FinickyRuntimeOptionsTests: XCTestCase {
    func testReadsArgumentsFromARunningProcess() throws {
        let arguments = try XCTUnwrap(ProcessArgumentReader.arguments(for: getpid()))

        XCTAssertEqual(arguments.first, ProcessInfo.processInfo.arguments.first)
    }

    func testParsesGoFlagForms() {
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "/Applications/Finicky.app/Contents/MacOS/Finicky",
                "--config", "/tmp/work config.ts",
                "--rules=/tmp/rules.json",
                "--no-config",
            ]),
            FinickyRuntimeOptions(
                configPath: "/tmp/work config.ts",
                rulesPath: "/tmp/rules.json",
                skipsJavaScriptConfig: true))
    }

    func testEqualsStringFlagsMatchGoFlagSemantics() {
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "Finicky",
                "--config=/tmp/config.js",
                "--rules=/tmp/rules.json",
            ]),
            FinickyRuntimeOptions(
                configPath: "/tmp/config.js",
                rulesPath: "/tmp/rules.json"))
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "Finicky",
                "--config=",
                "--rules=",
            ]),
            FinickyRuntimeOptions())
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "Finicky",
                "--config",
                "--rules=/tmp/consumed-as-config.json",
                "--rules=/tmp/rules.json",
            ]),
            FinickyRuntimeOptions(
                configPath: "--rules=/tmp/consumed-as-config.json",
                rulesPath: "/tmp/rules.json"))
    }

    func testParsesGoBooleanFormsAndStopsAtArgumentBoundary() {
        XCTAssertTrue(FinickyRuntimeOptions.parse(arguments: [
            "Finicky", "--no-config=1",
        ]).skipsJavaScriptConfig)
        XCTAssertFalse(FinickyRuntimeOptions.parse(arguments: [
            "Finicky", "--no-config=False",
        ]).skipsJavaScriptConfig)
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "Finicky",
                "--config=/tmp/first.js",
                "--",
                "--config=/tmp/ignored.js",
                "--no-config",
            ]),
            FinickyRuntimeOptions(configPath: "/tmp/first.js"))
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "Finicky",
                "positional",
                "--rules=/tmp/ignored.json",
            ]),
            FinickyRuntimeOptions())
    }

    func testKnownWindowAndDryRunFlagsDoNotHideLaterPaths() {
        XCTAssertEqual(
            FinickyRuntimeOptions.parse(arguments: [
                "Finicky",
                "--window",
                "--dry-run=false",
                "--config", "/tmp/config.js",
                "--rules=/tmp/rules.json",
            ]),
            FinickyRuntimeOptions(
                configPath: "/tmp/config.js",
                rulesPath: "/tmp/rules.json"))
    }

    func testRuntimeDetectionReturnsTheMatchedLegacyBundle() {
        let detection = FinickyRuntimeOptions.detect(bundleIdentifiers: [
            "se.johnste.finicky",
            "net.kassett.Finicky",
        ]) { bundleIdentifier in
            guard bundleIdentifier == "net.kassett.Finicky" else { return nil }
            return (["Finicky", "--config=/tmp/legacy.js"], "3.4.2")
        }

        XCTAssertEqual(
            detection,
            FinickyRuntimeDetection(
                bundleIdentifier: "net.kassett.Finicky",
                appVersion: "3.4.2",
                options: FinickyRuntimeOptions(configPath: "/tmp/legacy.js")))
    }

    func testExpandsHomePathsAndRejectsRelativePaths() {
        let home = URL(fileURLWithPath: "/Users/test")
        let options = FinickyRuntimeOptions(
            configPath: "$HOME/.config/finicky.ts",
            rulesPath: "~/rules.json")

        XCTAssertEqual(
            options.configURL(homeDirectory: home)?.path,
            "/Users/test/.config/finicky.ts")
        XCTAssertNil(options.rulesURL(homeDirectory: home))
    }

    func testNoConfigSkipsAStaleJavaScriptFile() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try #"export default { handlers: [{ match: "stale.example/*", browser: "Safari" }] };"#
            .write(to: home.appendingPathComponent(".finicky.js"), atomically: true, encoding: .utf8)
        let rulesURL = home.appendingPathComponent(
            "Library/Application Support/Finicky/rules.json")
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try #"{"defaultBrowser":"Safari","rules":[{"match":"live.example/*","browser":"Google Chrome"}]}"#
            .write(to: rulesURL, atomically: true, encoding: .utf8)

        let result = ConfigImporter.importFinicky(
            homeDirectory: home,
            currentAppInstalled: true,
            runtimeOptions: FinickyRuntimeOptions(skipsJavaScriptConfig: true))

        XCTAssertEqual(result.rules.count, 1, result.warnings.joined(separator: "\n"))
        XCTAssertEqual(result.rules.first?.targetBundleId, "com.google.Chrome")
        XCTAssertTrue(result.warnings.contains { $0.contains("--no-config") })
    }

    func testCustomRulesFlagOverridesTheDefaultRulesFile() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let defaultURL = home.appendingPathComponent(
            "Library/Application Support/Finicky/rules.json")
        try FileManager.default.createDirectory(
            at: defaultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try #"{"defaultBrowser":"Safari","rules":[{"match":"wrong.example/*","browser":"Safari"}]}"#
            .write(to: defaultURL, atomically: true, encoding: .utf8)
        let customURL = home.appendingPathComponent("custom-rules.json")
        try #"{"defaultBrowser":"Safari","rules":[{"match":"right.example/*","browser":"Firefox"}]}"#
            .write(to: customURL, atomically: true, encoding: .utf8)

        let result = ConfigImporter.importFinicky(
            homeDirectory: home,
            currentAppInstalled: true,
            runtimeOptions: FinickyRuntimeOptions(
                rulesPath: customURL.path,
                skipsJavaScriptConfig: true))

        XCTAssertEqual(result.rules.count, 1, result.warnings.joined(separator: "\n"))
        XCTAssertEqual(result.rules.first?.targetBundleId, "org.mozilla.firefox")
        XCTAssertTrue(result.rules.first?.pattern.contains("right\\.example") == true)
    }

    func testFinickyThreeNeverLoadsAStaleRulesJSONFile() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try #"module.exports = { defaultBrowser: "Safari", handlers: [{ match: "legacy.example/*", browser: "Safari" }] };"#
            .write(
                to: home.appendingPathComponent(".finicky.js"),
                atomically: true,
                encoding: .utf8)
        let rulesURL = home.appendingPathComponent(
            "Library/Application Support/Finicky/rules.json")
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try #"{"defaultBrowser":"Safari","rules":[{"match":"stale.example/*","browser":"Google Chrome"}]}"#
            .write(to: rulesURL, atomically: true, encoding: .utf8)

        let result = ConfigImporter.importFinicky(
            homeDirectory: home,
            currentAppInstalled: false)

        XCTAssertEqual(result.rules.count, 1, result.warnings.joined(separator: "\n"))
        XCTAssertTrue(result.rules.first?.pattern.contains("legacy\\.example") == true)
    }

    func testMissingExplicitRulesPathProducesAWarning() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let result = ConfigImporter.importFinicky(
            homeDirectory: home,
            currentAppInstalled: true,
            runtimeOptions: FinickyRuntimeOptions(
                rulesPath: home.appendingPathComponent("missing.json").path,
                skipsJavaScriptConfig: true))

        XCTAssertTrue(result.warnings.contains { $0.contains("explicit --rules file") })
    }

    func testUnreadableExplicitRulesPathProducesAPathWarning() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let rulesDirectory = home.appendingPathComponent("rules-directory")
        try FileManager.default.createDirectory(
            at: rulesDirectory,
            withIntermediateDirectories: true)

        let result = ConfigImporter.importFinicky(
            homeDirectory: home,
            currentAppInstalled: true,
            runtimeOptions: FinickyRuntimeOptions(
                rulesPath: rulesDirectory.path,
                skipsJavaScriptConfig: true))

        XCTAssertTrue(result.warnings.contains {
            $0.contains("explicit --rules file") && $0.contains(rulesDirectory.path)
        }, result.warnings.joined(separator: "\n"))
    }

    func testCacheSelectionUsesTheInstalledAppVersion() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/Finicky")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let selectedConfig = home.appendingPathComponent("selected.js")
        let otherConfig = home.appendingPathComponent("other.js")
        try "export default {};".write(
            to: selectedConfig,
            atomically: true,
            encoding: .utf8)
        try "export default {};".write(
            to: otherConfig,
            atomically: true,
            encoding: .utf8)

        let selectedCache = cache.appendingPathComponent("config_cache_selected.json")
        let otherCache = cache.appendingPathComponent("config_cache_other.json")
        try JSONSerialization.data(withJSONObject: [
            "appVersion": "4.2.1",
            "configPath": selectedConfig.path,
        ]).write(to: selectedCache)
        try JSONSerialization.data(withJSONObject: [
            "appVersion": "4.2.2",
            "configPath": otherConfig.path,
        ]).write(to: otherCache)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: selectedCache.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: otherCache.path)

        XCTAssertEqual(
            FinickyConfigPaths.preferredConfigURL(
                homeDirectory: home,
                version: .v4,
                appVersion: "4.2.1")?.path,
            selectedConfig.path)
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-finicky-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true)
        return url
    }
}
