import Foundation

/// Result of evaluating a `Rule` against a URL. Carries enough information
/// to explain a match or non-match to the user in the URL Tester and in
/// the Add Rule sheet's live test feedback.
public struct RuleMatchResult: Sendable, Equatable {
    public let matched: Bool
    public let matcherFired: MatchType?
    public let normalizedURL: String
    public let explanation: String

    public init(matched: Bool, matcherFired: MatchType?, normalizedURL: String, explanation: String) {
        self.matched = matched
        self.matcherFired = matcherFired
        self.normalizedURL = normalizedURL
        self.explanation = explanation
    }
}
