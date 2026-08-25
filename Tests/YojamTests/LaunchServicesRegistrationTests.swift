import Foundation
import XCTest

@testable import Yojam

final class LaunchServicesRegistrationTests: XCTestCase {
    func testRefreshForcesLaunchServicesUpdateForBundle() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Yojam.app")
        var registeredURL: URL?
        var requestedUpdate = false

        let status = LaunchServicesRegistration.refresh(
            bundleURL: bundleURL,
            register: { url, update in
                registeredURL = url as URL
                requestedUpdate = update
                return noErr
            })

        XCTAssertEqual(status, noErr)
        XCTAssertEqual(registeredURL, bundleURL)
        XCTAssertTrue(requestedUpdate)
    }
}
