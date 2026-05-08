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
            applicationSupportDirectory: tempDirectory
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
}
