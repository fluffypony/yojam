import Foundation
import XCTest

#if SWIFT_PACKAGE
final class ProvisioningProfileValidationTests: XCTestCase {
    func testBundleValidatorChecksKVSProvisioningProfileAuthorisation() throws {
        let validator = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/validate-bundle.sh"),
            encoding: .utf8)

        XCTAssertTrue(validator.contains("require_profile_string_authorisation"))
        XCTAssertEqual(
            validator.components(
                separatedBy: "require_profile_string_authorisation").count,
            3)
        XCTAssertTrue(validator.contains("if [ \"$BUNDLE\" = \"$APP\" ]; then"))
        XCTAssertTrue(validator.contains(
            "com.apple.developer.ubiquity-kvstore-identifier"))
        XCTAssertTrue(validator.contains(
            "Print :Entitlements:${entitlement}"))
        XCTAssertTrue(validator.contains(
            "[[ \"$signed_value\" != \"$profile_prefix\"* ]]"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
#endif
