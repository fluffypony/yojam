import XCTest
@testable import Yojam

final class RegexMatcherTests: XCTestCase {
    func testSimpleMatch() {
        XCTAssertTrue(RegexMatcher.matches("hello world", pattern: "hello"))
        XCTAssertFalse(RegexMatcher.matches("goodbye", pattern: "hello"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(RegexMatcher.matches("HELLO", pattern: "hello"))
    }
}
