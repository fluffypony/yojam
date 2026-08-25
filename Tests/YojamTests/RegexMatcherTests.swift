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

    func testMatchesAndRewritesURLsUpToTheRoutingLimit() {
        let input = "https://example.com/" + String(repeating: "a", count: 9_000)

        XCTAssertTrue(RegexMatcher.matches(input, pattern: "example\\.com"))
        XCTAssertTrue(RegexMatcher.replaceMatches(
            in: input,
            pattern: "example\\.com",
            replacement: "new.example").contains("new.example"))
    }

    func testRejectsInputAboveTheRoutingLimit() {
        let input = String(repeating: "a", count: 32_769)

        XCTAssertFalse(RegexMatcher.matches(input, pattern: "a"))
        XCTAssertEqual(RegexMatcher.replaceMatches(
            in: input,
            pattern: "a",
            replacement: "b"), input)
    }
}
