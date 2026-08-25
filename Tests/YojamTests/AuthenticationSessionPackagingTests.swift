import Foundation
import XCTest

final class AuthenticationSessionPackagingTests: XCTestCase {
    func testAppDeclaresAuthenticationSessionSupport() throws {
#if SWIFT_PACKAGE
        let infoPlistURL = repositoryRoot
            .appendingPathComponent("Sources/Yojam/Resources/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])
#else
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)
#endif
        let capabilities = try XCTUnwrap(
            plist["ASWebAuthenticationSessionWebBrowserSupportCapabilities"]
                as? [String: Any])

        XCTAssertEqual(capabilities["IsSupported"] as? Bool, true)
        XCTAssertNil(capabilities["CallbackURLMatchingIsSupported"])
        XCTAssertNil(capabilities["EphemeralBrowserSessionIsSupported"])
    }

#if SWIFT_PACKAGE
    func testProjectAndBundleValidatorKeepAuthenticationSupport() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8)
        let validator = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/validate-bundle.sh"),
            encoding: .utf8)

        XCTAssertTrue(project.contains(
            "ASWebAuthenticationSessionWebBrowserSupportCapabilities:"))
        XCTAssertFalse(project.contains("CallbackURLMatchingIsSupported:"))
        XCTAssertFalse(project.contains("EphemeralBrowserSessionIsSupported:"))
        XCTAssertTrue(validator.contains(
            "ASWebAuthenticationSessionWebBrowserSupportCapabilities.IsSupported"))
    }

    func testSessionHandlerInstallsBeforeLaunchServicesRefresh() throws {
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/Yojam/App/AppDelegate.swift"),
            encoding: .utf8)
        let willFinish = try XCTUnwrap(
            source.range(of: "func applicationWillFinishLaunching"))
        let didFinish = try XCTUnwrap(
            source.range(
                of: "func applicationDidFinishLaunching",
                range: willFinish.upperBound..<source.endIndex))
        let launchBody = source[willFinish.lowerBound..<didFinish.lowerBound]
        let install = try XCTUnwrap(
            launchBody.range(of: "authenticationSessionHandler.install()"))
        let refresh = try XCTUnwrap(
            launchBody.range(of: "LaunchServicesRegistration.refresh()"))

        XCTAssertLessThan(install.lowerBound, refresh.lowerBound)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
#endif
}
