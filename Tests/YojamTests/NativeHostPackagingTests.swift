import Foundation
import XCTest

final class NativeHostPackagingTests: XCTestCase {
    func testNativeHostDeclaresBackgroundApplicationIdentity() throws {
        let plist = try nativeHostInfoPlist()

        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSBackgroundOnly"] as? Bool, true)
#if SWIFT_PACKAGE
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
#else
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.yojam.app.NativeHost")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "YojamNativeHost")
#endif
    }

    func testNativeHostVersionAndBuildMatchApp() throws {
        let plist = try nativeHostInfoPlist()
#if SWIFT_PACKAGE
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")
#else
        let appVersion = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let appBuild = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, appVersion)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, appBuild)
#endif
    }

#if SWIFT_PACKAGE
    func testNativeHostRequestsSharedAppGroup() throws {
        let entitlements = try readPlist(at: repositoryRoot.appendingPathComponent(
            "Sources/YojamNativeHost/YojamNativeHost.entitlements"))
        let appGroups = try XCTUnwrap(
            entitlements["com.apple.security.application-groups"] as? [String])

        XCTAssertTrue(appGroups.contains("group.org.yojam.shared"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
#else
    func testEmbeddedNativeHostHasExecutableAndProvisioningProfile() throws {
        let helper = try embeddedNativeHostBundle()
        let executableURL = try XCTUnwrap(helper.executableURL)

        XCTAssertEqual(
            executableURL.standardizedFileURL,
            helper.bundleURL.appendingPathComponent(
                "Contents/MacOS/YojamNativeHost").standardizedFileURL)
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: executableURL.path),
            "The embedded native host executable is missing or is not executable")

        let profileURL = helper.bundleURL.appendingPathComponent(
            "Contents/embedded.provisionprofile")
        let profile = try Data(contentsOf: profileURL)
        XCTAssertFalse(profile.isEmpty, "The native host provisioning profile is empty")
    }

    private func embeddedNativeHostBundle() throws -> Bundle {
        let helperURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/YojamNativeHost.app")
        return try XCTUnwrap(
            Bundle(url: helperURL),
            "YojamNativeHost.app is not embedded in Yojam.app/Contents/Helpers")
    }
#endif

    private func nativeHostInfoPlist() throws -> [String: Any] {
#if SWIFT_PACKAGE
        let infoPlistURL = repositoryRoot.appendingPathComponent(
            "Sources/YojamNativeHost/Info.plist")
#else
        let infoPlistURL = try embeddedNativeHostBundle().bundleURL.appendingPathComponent(
            "Contents/Info.plist")
#endif
        return try readPlist(at: infoPlistURL)
    }

    private func readPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])
    }
}
