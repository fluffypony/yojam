import Foundation
import XCTest

final class ExtensionVersionPackagingTests: XCTestCase {
    func testShareExtensionVersionTracksAppBuildSettings() throws {
#if SWIFT_PACKAGE
        let infoPlist = repositoryRoot
            .appendingPathComponent("Sources/YojamShareExtension/Info.plist")
#else
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let infoPlist = plugInsURL
            .appendingPathComponent("YojamShareExtension.appex/Contents/Info.plist")
#endif
        let data = try Data(contentsOf: infoPlist)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])

#if SWIFT_PACKAGE
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8)
        let shareStart = try XCTUnwrap(project.range(of: "  YojamShareExtension:"))
        let safariStart = try XCTUnwrap(
            project.range(of: "  YojamSafariExtension:", range: shareStart.upperBound..<project.endIndex))
        let shareTarget = project[shareStart.lowerBound..<safariStart.lowerBound]
        XCTAssertTrue(shareTarget.contains(
            "CFBundleShortVersionString: \"$(MARKETING_VERSION)\""))
        XCTAssertTrue(shareTarget.contains(
            "CFBundleVersion: \"$(CURRENT_PROJECT_VERSION)\""))
#else
        XCTAssertEqual(
            plist["CFBundleShortVersionString"] as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(
            plist["CFBundleVersion"] as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
#endif
    }

#if SWIFT_PACKAGE
    func testBundleValidatorChecksBothExtensionVersionsAndBuilds() throws {
        let validator = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/validate-bundle.sh"),
            encoding: .utf8)

        XCTAssertTrue(validator.contains("CFBundleShortVersionString"))
        XCTAssertTrue(validator.contains("CFBundleVersion"))
        XCTAssertTrue(validator.contains(
            "check_bundle_version \"$SHARE_INFO\" \"Share extension\""))
        XCTAssertTrue(validator.contains(
            "check_bundle_version \"$SAFARI_INFO\" \"Safari extension\""))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
#endif
}
