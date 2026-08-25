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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
#endif
}
