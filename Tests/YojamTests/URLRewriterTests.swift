import XCTest
@testable import Yojam
import YojamCore

final class URLRewriterTests: XCTestCase {
    func testRegexRewrite() {
        let result = RegexMatcher.replaceMatches(
            in: "https://twitter.com/user/status/123",
            pattern: #"https://(www\.)?twitter\.com/(.*)"#,
            replacement: "https://nitter.net/$2")
        XCTAssertEqual(result, "https://nitter.net/user/status/123")
    }

    func testRegexValidation() {
        XCTAssertTrue(RegexMatcher.isValid(
            pattern: #"https://.*\.example\.com"#))
        XCTAssertFalse(RegexMatcher.isValid(pattern: "[invalid"))
    }
}
