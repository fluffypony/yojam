import XCTest
@testable import Yojam

final class ScreenEdgeDetectorTests: XCTestCase {
    func testReturnsFinitePoint() {
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: NSSize(width: 300, height: 80))
        XCTAssertFalse(origin.x.isNaN)
        XCTAssertFalse(origin.y.isNaN)
    }

    func testCenterOfScreen() {
        let size = NSSize(width: 200, height: 100)
        let cursor = NSPoint(x: 500, y: 500)
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: size, cursor: cursor, visibleFrame: frame)
        // Picker should center horizontally on cursor
        XCTAssertEqual(origin.x, cursor.x - size.width / 2, accuracy: 1)
    }

    func testRightEdge() {
        let size = NSSize(width: 200, height: 100)
        let cursor = NSPoint(x: 1900, y: 500)
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: size, cursor: cursor, visibleFrame: frame)
        // Picker should not exceed right edge
        XCTAssertLessThanOrEqual(origin.x + size.width, frame.maxX)
    }

    func testBottomEdge() {
        let size = NSSize(width: 200, height: 100)
        let cursor = NSPoint(x: 500, y: 50)
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: size, cursor: cursor, visibleFrame: frame)
        // Picker should appear within frame
        XCTAssertGreaterThanOrEqual(origin.y, frame.minY)
    }

    func testLeftEdge() {
        let size = NSSize(width: 200, height: 100)
        let cursor = NSPoint(x: 10, y: 500)
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: size, cursor: cursor, visibleFrame: frame)
        // Picker should not go past left edge
        XCTAssertGreaterThanOrEqual(origin.x, frame.minX)
    }

    func testTopEdge() {
        let size = NSSize(width: 200, height: 100)
        let cursor = NSPoint(x: 500, y: 1070)
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = ScreenEdgeDetector.calculateOrigin(
            pickerSize: size, cursor: cursor, visibleFrame: frame)
        // Picker should not exceed top edge
        XCTAssertLessThanOrEqual(origin.y + size.height, frame.maxY)
    }
}
