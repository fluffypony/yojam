import XCTest
@testable import Yojam

final class ScreenEdgeDetectorTests: XCTestCase {
    func testReturnsFinitePoint() {
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: NSSize(width: 300, height: 80))
        XCTAssertFalse(origin.x.isNaN)
        XCTAssertFalse(origin.y.isNaN)
    }
}
