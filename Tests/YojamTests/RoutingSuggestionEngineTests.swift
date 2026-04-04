import XCTest
@testable import Yojam

final class RoutingSuggestionEngineTests: XCTestCase {
    @MainActor
    func testNoSuggestionBelowThreshold() {
        let engine = RoutingSuggestionEngine()
        engine.clearAll()
        engine.recordChoice(domain: "example.com", entryId: "browser-a")
        engine.recordChoice(domain: "example.com", entryId: "browser-a")
        // Below minimum confidence of 3
        XCTAssertNil(engine.suggestion(for: "example.com"))
    }

    @MainActor
    func testSuggestionAfterThreshold() {
        let engine = RoutingSuggestionEngine()
        engine.clearAll()
        for _ in 0..<4 {
            engine.recordChoice(domain: "test.com", entryId: "browser-x")
        }
        XCTAssertEqual(engine.suggestion(for: "test.com"), "browser-x")
    }

    @MainActor
    func testNoSuggestionWhenSplit() {
        let engine = RoutingSuggestionEngine()
        engine.clearAll()
        // 2 choices for A, 2 for B — total 4 but neither > 70%
        engine.recordChoice(domain: "split.com", entryId: "a")
        engine.recordChoice(domain: "split.com", entryId: "a")
        engine.recordChoice(domain: "split.com", entryId: "b")
        engine.recordChoice(domain: "split.com", entryId: "b")
        XCTAssertNil(engine.suggestion(for: "split.com"))
    }

    @MainActor
    func testClearAll() {
        let engine = RoutingSuggestionEngine()
        for _ in 0..<5 {
            engine.recordChoice(domain: "clear.com", entryId: "x")
        }
        XCTAssertNotNil(engine.suggestion(for: "clear.com"))
        engine.clearAll()
        XCTAssertNil(engine.suggestion(for: "clear.com"))
    }

    @MainActor
    func testUnknownDomainReturnsNil() {
        let engine = RoutingSuggestionEngine()
        XCTAssertNil(engine.suggestion(for: "never-seen.com"))
    }
}
