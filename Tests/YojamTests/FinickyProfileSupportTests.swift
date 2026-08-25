import XCTest
@testable import Yojam
import YojamCore

final class FinickyProfileSupportTests: XCTestCase {
    func testCatalogUsesExactFinickyProfileLocations() {
        for fixture in allProfileFixtures {
            XCTAssertEqual(
                BrowserProfileCatalog.configuration(for: fixture.bundleIdentifier),
                BrowserProfileConfiguration(
                    engine: fixture.engine,
                    appSupportPath: fixture.appSupportPath),
                fixture.name)
        }
    }

    func testDiscoveryReadsEveryExactMappedLocation() throws {
        let applicationSupport = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        try writeProfileData(
            for: allProfileFixtures,
            applicationSupportDirectory: applicationSupport)
        let discovery = ProfileDiscovery(
            applicationSupportDirectory: applicationSupport)

        for fixture in allProfileFixtures {
            let profiles = discovery.discoverProfiles(
                for: fixture.bundleIdentifier)
            let profile = try XCTUnwrap(
                profiles.first { $0.name == "Work" },
                fixture.name)
            XCTAssertEqual(profile.id, fixture.profileIdentifier, fixture.name)
            XCTAssertEqual(
                profile.browserBundleId,
                fixture.bundleIdentifier,
                fixture.name)
        }
    }

    func testDiscoveryDoesNotGuessAProfileFolderFromTheBundleID() throws {
        let applicationSupport = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let guessedFixture = ProfileFixture.chromium(
            "Google Chrome Beta",
            "com.google.Chrome.beta",
            "com.google.Chrome.beta")
        try writeProfileData(
            for: [guessedFixture],
            applicationSupportDirectory: applicationSupport)

        XCTAssertTrue(ProfileDiscovery(
            applicationSupportDirectory: applicationSupport
        ).discoverProfiles(for: guessedFixture.bundleIdentifier).isEmpty)
    }

    func testLaunchArgumentsUseEachBrowserEngineFlag() {
        let emptySupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firefoxReader = FirefoxProfileReader(
            applicationSupportDirectory: emptySupport)

        for fixture in allProfileFixtures {
            let arguments = ProfileLaunchHelper.launchArguments(
                forProfile: fixture.profileIdentifier,
                browserBundleId: fixture.bundleIdentifier,
                firefoxProfileReader: firefoxReader)
            switch fixture.engine {
            case .chromium:
                XCTAssertEqual(
                    arguments,
                    ["--profile-directory=Profile 7"],
                    fixture.name)
                XCTAssertTrue(ProfileLaunchHelper.supportsUserDataDirectory(
                    browserBundleId: fixture.bundleIdentifier), fixture.name)
            case .firefox:
                XCTAssertEqual(arguments, ["-P", "Work"], fixture.name)
                XCTAssertFalse(ProfileLaunchHelper.supportsUserDataDirectory(
                    browserBundleId: fixture.bundleIdentifier), fixture.name)
            }
        }
    }

    func testFinickyFourImportsProfilesForEveryMappedBrowser() throws {
        let applicationSupport = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        try writeProfileData(
            for: finickyFourFixtures,
            applicationSupportDirectory: applicationSupport)
        let result = parser(applicationSupportDirectory: applicationSupport).parse(
            configurationSource(
                fixtures: finickyFourFixtures,
                profileName: "Work"),
            version: .v4)

        XCTAssertEqual(
            result.rules.count,
            finickyFourFixtures.count,
            result.warningMessages.joined(separator: "\n"))
        for fixture in finickyFourFixtures {
            let rule = try XCTUnwrap(result.rules.first {
                $0.targetBundleId.caseInsensitiveCompare(
                    fixture.bundleIdentifier) == .orderedSame
            }, fixture.name)
            XCTAssertEqual(
                rule.ruleProfileId,
                fixture.profileIdentifier,
                fixture.name)
        }
    }

    func testFinickyThreeImportsProfilesForVerifiedBrowserSubset() throws {
        let applicationSupport = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        try writeProfileData(
            for: finickyThreeFixtures,
            applicationSupportDirectory: applicationSupport)
        let result = parser(applicationSupportDirectory: applicationSupport).parse(
            configurationSource(
                fixtures: finickyThreeFixtures,
                profileName: "Profile 7",
                commonJS: true),
            version: .v3)

        XCTAssertEqual(
            result.rules.count,
            finickyThreeFixtures.count,
            result.warningMessages.joined(separator: "\n"))
        for fixture in finickyThreeFixtures {
            let rule = try XCTUnwrap(result.rules.first {
                $0.targetBundleId.caseInsensitiveCompare(
                    fixture.bundleIdentifier) == .orderedSame
            }, fixture.name)
            XCTAssertEqual(rule.ruleProfileId, "Profile 7", fixture.name)
        }
    }

    func testProfileResolutionUsesEachFinickyVersionOrder() throws {
        let applicationSupport = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let chromeDirectory = applicationSupport.appendingPathComponent("Google/Chrome")
        try FileManager.default.createDirectory(
            at: chromeDirectory,
            withIntermediateDirectories: true)
        try Data(#"""
        {
          "profile": {
            "last_used": "Profile 7",
            "info_cache": {
              "Work": { "name": "Personal" },
              "Profile 7": { "name": "Work" }
            }
          }
        }
        """#.utf8).write(
            to: chromeDirectory.appendingPathComponent("Local State"),
            options: .atomic)
        let resolver = LocalFinickyProfileResolver(
            discovery: ProfileDiscovery(
                applicationSupportDirectory: applicationSupport))

        XCTAssertEqual(
            resolver.resolveProfile(
                named: "Work",
                browserBundleIdentifier: "com.google.Chrome",
                version: .v3)?.id,
            "Work")
        XCTAssertEqual(
            resolver.resolveProfile(
                named: "Work",
                browserBundleIdentifier: "com.google.Chrome",
                version: .v4)?.id,
            "Profile 7")
    }

    private func parser(
        applicationSupportDirectory: URL
    ) -> FinickyConfigParser {
        FinickyConfigParser(
            applicationResolver: WorkspaceFinickyApplicationResolver(),
            profileResolver: LocalFinickyProfileResolver(
                discovery: ProfileDiscovery(
                    applicationSupportDirectory: applicationSupportDirectory)))
    }

    private func configurationSource(
        fixtures: [ProfileFixture],
        profileName: String,
        commonJS: Bool = false
    ) -> String {
        let handlers = fixtures.enumerated().map { offset, fixture in
            """
            {
              match: "profile\(offset).example/*",
              browser: { name: "\(fixture.name)", profile: "\(profileName)" }
            }
            """
        }.joined(separator: ",\n")
        let assignment = commonJS ? "module.exports =" : "export default"
        return """
        \(assignment) {
          defaultBrowser: "Safari",
          handlers: [
        \(handlers)
          ]
        };
        """
    }

    private func writeProfileData(
        for fixtures: [ProfileFixture],
        applicationSupportDirectory: URL
    ) throws {
        for fixture in fixtures {
            let directory = applicationSupportDirectory
                .appendingPathComponent(fixture.appSupportPath)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
            switch fixture.engine {
            case .chromium:
                let localState = Data(#"""
                {
                  "profile": {
                    "last_used": "Profile 7",
                    "info_cache": {
                      "Profile 7": { "name": "Work" }
                    }
                  }
                }
                """#.utf8)
                try localState.write(
                    to: directory.appendingPathComponent("Local State"),
                    options: .atomic)
            case .firefox:
                let profilesINI = """
                [Profile0]
                Name=Work
                IsRelative=1
                Path=Profiles/work
                """
                try profilesINI.write(
                    to: directory.appendingPathComponent("profiles.ini"),
                    atomically: true,
                    encoding: .utf8)
            }
        }
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private var allProfileFixtures: [ProfileFixture] {
        finickyFourFixtures + finickyThreeAdditionalFixtures
    }

    private var finickyFourFixtures: [ProfileFixture] {
        [
            .chromium("Brave Browser", "com.brave.Browser", "BraveSoftware/Brave-Browser"),
            .chromium("Google Chrome", "com.google.Chrome", "Google/Chrome"),
            .chromium("Google Chrome Beta", "com.google.Chrome.beta", "Google/Chrome Beta"),
            .chromium("Google Chrome Canary", "com.google.Chrome.canary", "Google/Chrome Canary"),
            .chromium("Chromium", "org.chromium.Chromium", "Chromium"),
            .chromium("Microsoft Edge", "com.microsoft.edgemac", "Microsoft Edge"),
            .chromium("Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi"),
            .chromium("Wavebox", "com.bookry.wavebox", "WaveboxApp"),
            .chromium("Helium", "net.imput.helium", "net.imput.helium"),
            .chromium("Comet", "ai.perplexity.comet", "Comet"),
            .chromium("Yandex", "ru.yandex.desktop.yandex-browser", "Yandex/YandexBrowser"),
            .chromium("Opera", "com.operasoftware.Opera", "com.operasoftware.Opera"),
            .chromium("Opera GX", "com.operasoftware.OperaGX", "com.operasoftware.OperaGX"),
            .firefox("Firefox", "org.mozilla.firefox", "Firefox"),
            .firefox(
                "Firefox Developer Edition",
                "org.mozilla.firefoxdeveloperedition",
                "Firefox"),
            .firefox("Zen", "app.zen-browser.zen", "zen"),
        ]
    }

    private var finickyThreeAdditionalFixtures: [ProfileFixture] {
        [
            .chromium(
                "Brave Browser Beta",
                "com.brave.Browser.beta",
                "BraveSoftware/Brave-Browser-Beta"),
            .chromium(
                "Brave Browser Dev",
                "com.brave.Browser.dev",
                "BraveSoftware/Brave-Browser-Dev"),
            .chromium(
                "Microsoft Edge Beta",
                "com.microsoft.edgemac.Beta",
                "Microsoft Edge Beta"),
        ]
    }

    private var finickyThreeFixtures: [ProfileFixture] {
        [
            .chromium("Brave Browser", "com.brave.Browser", "BraveSoftware/Brave-Browser"),
            .chromium(
                "Brave Browser Beta",
                "com.brave.Browser.beta",
                "BraveSoftware/Brave-Browser-Beta"),
            .chromium(
                "Brave Browser Dev",
                "com.brave.Browser.dev",
                "BraveSoftware/Brave-Browser-Dev"),
            .chromium("Google Chrome", "com.google.Chrome", "Google/Chrome"),
            .chromium("Microsoft Edge", "com.microsoft.edgemac", "Microsoft Edge"),
            .chromium(
                "Microsoft Edge Beta",
                "com.microsoft.edgemac.Beta",
                "Microsoft Edge Beta"),
            .chromium("Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi"),
        ]
    }
}

private struct ProfileFixture {
    let name: String
    let bundleIdentifier: String
    let appSupportPath: String
    let engine: BrowserProfileEngine

    var profileIdentifier: String {
        engine == .chromium ? "Profile 7" : "Work"
    }

    static func chromium(
        _ name: String,
        _ bundleIdentifier: String,
        _ appSupportPath: String
    ) -> ProfileFixture {
        ProfileFixture(
            name: name,
            bundleIdentifier: bundleIdentifier,
            appSupportPath: appSupportPath,
            engine: .chromium)
    }

    static func firefox(
        _ name: String,
        _ bundleIdentifier: String,
        _ appSupportPath: String
    ) -> ProfileFixture {
        ProfileFixture(
            name: name,
            bundleIdentifier: bundleIdentifier,
            appSupportPath: appSupportPath,
            engine: .firefox)
    }
}
