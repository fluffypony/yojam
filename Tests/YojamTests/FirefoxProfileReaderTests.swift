import XCTest
@testable import Yojam

final class FirefoxProfileReaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testSelectableFirefoxProfilesUseAbsolutePathIds() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory.appendingPathComponent("Profile Groups"),
            withIntermediateDirectories: true)

        let profilesIni = """
        [Install123]
        Default=Profiles/default-release

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/default-release
        Default=1

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/abc123.Work Profile
        storeID=group-123
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in nil }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        let defaultProfile = try XCTUnwrap(
            profiles.first { $0.name == "default-release" })
        let workProfile = try XCTUnwrap(
            profiles.first { $0.name == "Work" })

        XCTAssertEqual(defaultProfile.id, "default-release")
        XCTAssertTrue(defaultProfile.isDefault)
        XCTAssertEqual(
            workProfile.id,
            firefoxDirectory
                .appendingPathComponent("Profiles/abc123.Work Profile")
                .path)
    }

    func testFirefox138StoreIDProfilesUseAbsolutePathIdsWithoutProfileGroups() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory,
            withIntermediateDirectories: true)

        let profilesIni = """
        [Profile2]
        Name=profile2name
        IsRelative=1
        Path=Profiles/qwer.Profile 2
        StoreID=xxx663
        ShowSelector=1
        Default=1

        [Profile1]
        Name=profile1name
        IsRelative=1
        Path=Profiles/asdf.Profile 1
        StoreID=xxx663
        ShowSelector=1
        Default=1

        [Profile0]
        Name=profile0name
        IsRelative=1
        Path=Profiles/zxcv.default-release
        StoreID=xxx663
        ShowSelector=1
        Default=1

        [General]
        StartWithLastProfile=1
        Version=2

        [Installxxxxx]
        Default=Profiles/zxcv.default-release
        Locked=1
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in "138.0.1" }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(
            profiles.first { $0.name == "profile2name" }?.id,
            firefoxDirectory.appendingPathComponent("Profiles/qwer.Profile 2").path)
        XCTAssertEqual(
            profiles.first { $0.name == "profile1name" }?.id,
            firefoxDirectory.appendingPathComponent("Profiles/asdf.Profile 1").path)
        XCTAssertEqual(
            profiles.first { $0.name == "profile0name" }?.id,
            firefoxDirectory.appendingPathComponent("Profiles/zxcv.default-release").path)
        XCTAssertTrue(profiles.first { $0.name == "profile0name" }?.isDefault == true)
    }

    func testStoreIDProfileKeepsLegacyNameBeforeFirefox138WhenSelectorIsAbsent() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory,
            withIntermediateDirectories: true)

        let profilesIni = """
        [Profile0]
        Name=Work
        IsRelative=1
        Path=Profiles/abc123.Work
        StoreID=group-123
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in "137.0" }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        XCTAssertEqual(profiles.first?.id, "Work")
    }

    func testFirefox138StoreIDProfileUsesPathWhenSelectorIsAbsent() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory,
            withIntermediateDirectories: true)

        let profilesIni = """
        [Profile0]
        Name=Work
        IsRelative=1
        Path=Profiles/abc123.Work
        StoreID=group-123
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in "138.0" }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        XCTAssertEqual(
            profiles.first?.id,
            firefoxDirectory.appendingPathComponent("Profiles/abc123.Work").path)
    }

    func testAllInstallDefaultProfilesAreMarkedDefault() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory,
            withIntermediateDirectories: true)

        let profilesIni = """
        [Install111]
        Default=Profiles/release.default-release
        Locked=1

        [Install222]
        Default=Profiles/dev.dev-edition-default
        Locked=1

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/release.default-release

        [Profile1]
        Name=dev-edition-default
        IsRelative=1
        Path=Profiles/dev.dev-edition-default

        [Profile2]
        Name=Work
        IsRelative=1
        Path=Profiles/work.Work
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in "138.0" }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        XCTAssertEqual(profiles.first { $0.name == "default-release" }?.isDefault, true)
        XCTAssertEqual(profiles.first { $0.name == "dev-edition-default" }?.isDefault, true)
        XCTAssertEqual(profiles.first { $0.name == "Work" }?.isDefault, false)
    }

    func testShowSelectorStoreIDProfileUsesPathWhenVersionIsUnavailable() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory,
            withIntermediateDirectories: true)

        let profilesIni = """
        [Profile0]
        Name=Work
        IsRelative=1
        Path=Profiles/abc123.Work
        StoreID=group-123
        ShowSelector=1
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in nil }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        XCTAssertEqual(
            profiles.first?.id,
            firefoxDirectory.appendingPathComponent("Profiles/abc123.Work").path)
    }

    func testShowSelectorLookupIsCaseInsensitive() throws {
        let firefoxDirectory = tempDirectory.appendingPathComponent("Firefox")
        try FileManager.default.createDirectory(
            at: firefoxDirectory,
            withIntermediateDirectories: true)

        let profilesIni = """
        [Profile0]
        Name=Work
        IsRelative=1
        Path=Profiles/abc123.Work
        StoreID=group-123
        showselector=1
        """
        try profilesIni.write(
            to: firefoxDirectory.appendingPathComponent("profiles.ini"),
            atomically: true,
            encoding: .utf8)

        let profiles = FirefoxProfileReader(
            applicationSupportDirectory: tempDirectory,
            firefoxVersionProvider: { _ in nil }
        ).readProfiles(bundleId: "org.mozilla.firefox")

        XCTAssertEqual(
            profiles.first?.id,
            firefoxDirectory.appendingPathComponent("Profiles/abc123.Work").path)
    }

    func testSelectableProfilesVersionDetection() {
        XCTAssertTrue(FirefoxProfileReader.supportsSelectableProfiles(versionString: "138.0.1"))
        XCTAssertTrue(FirefoxProfileReader.supportsSelectableProfiles(versionString: "149.0a1"))
        XCTAssertFalse(FirefoxProfileReader.supportsSelectableProfiles(versionString: "137.0"))
        XCTAssertFalse(FirefoxProfileReader.supportsSelectableProfiles(versionString: nil))
    }
}
