import XCTest
@testable import Yojam
@testable import YojamCore

final class RegexMatcherTests: XCTestCase {
    func testSimpleMatch() {
        XCTAssertTrue(RegexMatcher.matches("hello world", pattern: "hello"))
        XCTAssertFalse(RegexMatcher.matches("goodbye", pattern: "hello"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(RegexMatcher.matches("HELLO", pattern: "hello"))
    }

    func testInvalidPatternReturnsFalse() {
        XCTAssertFalse(RegexMatcher.matches("test", pattern: "[invalid"))
    }

    func testReplaceMatches() {
        let result = RegexMatcher.replaceMatches(
            in: "https://old.com/path",
            pattern: #"old\.com"#,
            replacement: "new.com")
        XCTAssertEqual(result, "https://new.com/path")
    }

    func testReplaceInvalidPatternReturnsOriginal() {
        let input = "test string"
        let result = RegexMatcher.replaceMatches(
            in: input, pattern: "[invalid", replacement: "x")
        XCTAssertEqual(result, input)
    }

    func testValidation() {
        XCTAssertTrue(RegexMatcher.isValid(pattern: #"https://.*\.example\.com"#))
        XCTAssertFalse(RegexMatcher.isValid(pattern: "[invalid"))
        XCTAssertTrue(RegexMatcher.isValid(pattern: "simple"))
    }
}
