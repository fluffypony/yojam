import XCTest
@testable import Yojam

final class ProfileLaunchHelperTests: XCTestCase {
    func testFirefoxProfileArgumentsDoNotForceNewInstance() {
        let args = ProfileLaunchHelper.launchArguments(
            forProfile: "Work",
            browserBundleId: "org.mozilla.firefox")

        XCTAssertEqual(args, ["-P", "Work"])
        XCTAssertFalse(args.contains("--new-instance"))
        XCTAssertFalse(args.contains("-no-remote"))
    }

    func testChromiumProfileArgumentsStillUseProfileDirectory() {
        let args = ProfileLaunchHelper.launchArguments(
            forProfile: "Profile 2",
            browserBundleId: "com.vivaldi.Vivaldi")

        XCTAssertEqual(args, ["--profile-directory=Profile 2"])
    }
}
